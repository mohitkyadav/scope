//
//  EditorModel.swift
//  Scope
//

import AppKit
import AVFoundation
import Combine
import CoreImage
import Observation

/// Which part of a timeline item a drag changes.
enum BlockEdit {
    case move
    case trimStart
    case trimEnd
}

/// What's selected on the timeline.
enum TimelineSelection: Equatable {
    case clip(UUID)
    case zoom(UUID)
    case note(UUID)
    case audio(UUID)
}

/// Playback and editing state for one project open in the editor.
@Observable
final class EditorModel {
    let project: ScopeProject
    let player = AVPlayer()

    /// Playback position in the final video.
    private(set) var currentTime: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var errorMessage: String?
    var selection: TimelineSelection?
    /// Set while a text field has focus, so single-key shortcuts like Space type instead.
    var isEditingText = false

    var settings = EditorSettings() {
        didSet {
            if settings != oldValue, !isRestoring {
                scheduleSave()
                scheduleRender()
            }
        }
    }

    /// The timeline: clips, zooms, notes and audio. Change it through `perform` or a gesture so the
    /// change can be undone.
    private(set) var edits = TimelineEdits() {
        didSet {
            if edits != oldValue, !isRestoring {
                editsChanged(from: oldValue)
            }
        }
    }

    /// Set while loading saved state, which shouldn't be saved straight back.
    private var isRestoring = false

    /// Length of the recording, before any edits.
    private(set) var sourceDuration: TimeInterval = 0
    /// The size of the frames the renderer draws.
    var canvasSize: CGSize { videoSize }
    var hasWebcam: Bool { scene?.webcamTrackID != nil }
    var recordedAudioNames: [String] { scene?.recordedAudio.map(\.name) ?? [] }

    /// Follows the timeline as it's edited, including mid-drag, before playback catches up.
    var timeMap: TimeMap { TimeMap(clips: edits.clips) }
    /// Length of the final video.
    var duration: TimeInterval { timeMap.duration }

    private var screen: AVURLAsset?
    private var videoSize: CGSize = .zero
    private var cursorTrack: CursorTrack?
    private var cursorPath: CursorPath?
    /// A lightly smoothed cursor path for the zoom camera, which follows it only inside zooms.
    private var cameraCursor: CursorPath?
    /// The zoom camera, and the zooms and zoom level it was worked out for.
    private var zoomCamera: (camera: ZoomCamera, zooms: [ZoomSegment], level: Double)?
    /// The smoothing `cursorPath` was built with, so it's only rebuilt when that changes.
    private var cursorPathSmoothing: Double?
    private var pixelsPerPoint: CGFloat = 2
    private var sprite: CursorSprite?
    private var firstFrame: CIImage?
    /// Notes drawn as images, by text, so they're only drawn again when their text changes.
    private(set) var noteImages: [String: CIImage] = [:]
    /// The project's videos and audio lined up as the timeline says; what the player plays.
    private(set) var scene: ProjectComposition?

    private var renderTask: Task<Void, Never>?
    private var rebuildTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var statusSubscription: AnyCancellable?
    private var terminationObserver: (any NSObjectProtocol)?

    /// The timeline as it was when the current drag began, for undo.
    private var gestureStart: TimelineEdits?
    /// Playback needs rebuilding once the current drag ends.
    private var needsRebuild = false

    init(project: ScopeProject) {
        self.project = project
    }

    // MARK: - Loading and closing

    func load() async {
        let screen = AVURLAsset(url: project.videoURL)
        self.screen = screen
        do {
            sourceDuration = try await screen.load(.duration).seconds
            guard let videoTrack = try await screen.loadTracks(withMediaType: .video).first else {
                errorMessage = "The recording has no video."
                return
            }
            videoSize = try await videoTrack.load(.naturalSize)
        } catch {
            errorMessage = "The recording couldn't be opened: \(error.localizedDescription)"
            return
        }

        // Without cursor data the video still plays, just with no cursor drawn.
        if let track = try? CursorTrack.read(from: project.cursorURL) {
            cursorTrack = track
            if track.areaWidth > 0 {
                pixelsPerPoint = videoSize.width / track.areaWidth
            }
            cameraCursor = await Task.detached { CursorPath(track: track, smoothing: 0.5) }.value
        }
        sprite = CursorSprite.arrow()
        firstFrame = await Self.firstFrame(of: screen)

        // A project that hasn't been edited yet has no project file: default settings, and the
        // whole recording with zooms suggested from its clicks.
        let file = try? ProjectFile.read(from: project.projectFileURL)
        isRestoring = true
        settings = file?.settings ?? EditorSettings()
        edits = file?.edits ?? .initial(duration: sourceDuration, clicks: cursorTrack?.clicks ?? [])
        isRestoring = false

        await rebuild()

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds
            }
        }

        // Subscribed to directly: an async loop over this publisher can miss the change to "playing"
        // while the window is busy drawing, which left the button stuck on Play.
        statusSubscription = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.isPlaying = status != .paused
            }

        // Changes are saved half a second after they're made; quitting sooner still keeps them.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveNow()
            }
        }
    }

    func close() {
        saveNow()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        terminationObserver = nil
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusSubscription = nil
    }

    // MARK: - Playback

    func togglePlayback() {
        if isPlaying {
            player.pause()
            return
        }
        // Start again from the beginning once the end has been reached.
        if duration > 0, currentTime >= duration - 0.05 {
            seek(to: 0)
        }
        player.play()
    }

    /// Moves the playhead to `time` in the final video.
    func seek(to time: TimeInterval) {
        let time = min(max(time, 0), duration)
        currentTime = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Editing

    /// Applies a change to the timeline as one undoable step called `actionName`.
    func perform(_ actionName: String, undoManager: UndoManager?, _ change: (inout TimelineEdits) -> Void) {
        var changed = edits
        change(&changed)
        setEdits(changed, actionName: actionName, undoManager: undoManager)
    }

    /// Call when a drag on the timeline begins. Changes during the drag go through `update` and
    /// become one undoable step when `endGesture` is called.
    func beginGesture() {
        if gestureStart == nil {
            gestureStart = edits
        }
    }

    /// Changes the timeline during a drag.
    func update(_ change: (inout TimelineEdits) -> Void) {
        beginGesture()
        change(&edits)
    }

    func endGesture(_ actionName: String, undoManager: UndoManager?) {
        guard let start = gestureStart else { return }
        gestureStart = nil
        if start != edits {
            undoManager?.registerUndo(withTarget: self) { model in
                model.setEdits(start, actionName: actionName, undoManager: undoManager)
            }
            undoManager?.setActionName(actionName)
        }
        if needsRebuild {
            scheduleRebuild()
        }
    }

    /// Sets the timeline and registers the opposite change with `undoManager`. Undoing calls this
    /// again with the earlier timeline, which in turn registers the redo.
    private func setEdits(_ new: TimelineEdits, actionName: String, undoManager: UndoManager?) {
        let old = edits
        guard new != old else { return }
        edits = new
        undoManager?.registerUndo(withTarget: self) { model in
            model.setEdits(old, actionName: actionName, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
    }

    /// Works out what a timeline change affects: what plays (clips, webcam, imported audio), only
    /// how loud it is, or only how frames are drawn (zooms, notes).
    private func editsChanged(from old: TimelineEdits) {
        scheduleSave()

        if Self.playbackChanged(from: old, to: edits) {
            if gestureStart != nil {
                needsRebuild = true
            } else {
                scheduleRebuild()
            }
        } else if edits.recordedAudio != old.recordedAudio || edits.importedAudio != old.importedAudio {
            player.currentItem?.audioMix = scene?.audioMix(edits: edits)
        }

        if edits.zooms != old.zooms || edits.notes != old.notes {
            scheduleRender()
        }
    }

    private static func playbackChanged(from old: TimelineEdits, to new: TimelineEdits) -> Bool {
        func placements(_ clips: [AudioClip]) -> [String] {
            clips.map { "\($0.id) \($0.fileName) \($0.offset)" }
        }
        return new.clips != old.clips
            || new.webcamFileName != old.webcamFileName
            || new.webcamOffset != old.webcamOffset
            || placements(new.importedAudio) != placements(old.importedAudio)
    }

    // MARK: - Clips

    /// The shortest a clip can be trimmed to, in seconds of the recording.
    private static let minimumClipLength = 0.1

    /// Splits the clip under `time` (in the final video) in two.
    func splitClip(at time: TimeInterval, undoManager: UndoManager?) {
        let map = timeMap
        guard let index = map.clipIndex(at: time) else { return }
        let clip = edits.clips[index]
        let cut = map.sourceTime(at: time)
        guard cut - clip.start >= Self.minimumClipLength, clip.end - cut >= Self.minimumClipLength else { return }

        perform("Split Clip", undoManager: undoManager) { edits in
            var second = clip
            second.id = UUID()
            second.start = cut
            edits.clips[index].end = cut
            edits.clips.insert(second, at: index + 1)
        }
    }

    /// Trims a clip during a drag. `seconds` is how far the edge has been dragged along the final
    /// video. Edges stop at the neighbouring clips and the ends of the recording, so dragging back
    /// out restores what was trimmed.
    func dragClip(_ id: UUID, _ edit: BlockEdit, by seconds: Double) {
        beginGesture()
        guard let original = gestureStart?.clips.first(where: { $0.id == id }) else { return }
        update { edits in
            guard let index = edits.clips.firstIndex(where: { $0.id == id }) else { return }
            let delta = seconds * original.speed
            switch edit {
            case .trimStart:
                let lowest = index > 0 ? edits.clips[index - 1].end : 0
                edits.clips[index].start = min(max(original.start + delta, lowest), original.end - Self.minimumClipLength)
            case .trimEnd:
                let highest = index + 1 < edits.clips.count ? edits.clips[index + 1].start : sourceDuration
                edits.clips[index].end = max(min(original.end + delta, highest), original.start + Self.minimumClipLength)
            case .move:
                break
            }
        }
    }

    static let speeds = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    /// The selected clip, if a clip is selected.
    var selectedClip: Clip? {
        guard case .clip(let id) = selection else { return nil }
        return edits.clips.first { $0.id == id }
    }

    /// The clip a speed change applies to: the selected one, or else the one under the playhead.
    var speedTarget: Clip? {
        selectedClip ?? timeMap.clipIndex(at: currentTime).map { edits.clips[$0] }
    }

    func setSpeed(_ speed: Double, ofClip id: UUID, undoManager: UndoManager?) {
        perform("Change Speed", undoManager: undoManager) { edits in
            guard let index = edits.clips.firstIndex(where: { $0.id == id }) else { return }
            edits.clips[index].speed = speed
        }
    }

    /// Deletes whatever is selected. The last clip can't be deleted.
    func deleteSelection(undoManager: UndoManager?) {
        guard let selection else { return }
        switch selection {
        case .clip(let id):
            guard edits.clips.count > 1 else { return }
            perform("Delete Clip", undoManager: undoManager) { $0.clips.removeAll { $0.id == id } }
        case .zoom(let id):
            perform("Delete Zoom", undoManager: undoManager) { $0.zooms.removeAll { $0.id == id } }
        case .note(let id):
            perform("Delete Note", undoManager: undoManager) { $0.notes.removeAll { $0.id == id } }
        case .audio(let id):
            perform("Remove Audio", undoManager: undoManager) { $0.importedAudio.removeAll { $0.id == id } }
        }
        self.selection = nil
    }

    var canDeleteSelection: Bool {
        guard let selection else { return false }
        if case .clip = selection {
            return edits.clips.count > 1
        }
        return true
    }

    // MARK: - Zooms

    private static let minimumZoomLength = 0.3

    /// Adds a two-second zoom at the playhead and selects it.
    func addZoom(undoManager: UndoManager?) {
        let start = timeMap.sourceTime(at: currentTime)
        let zoom = ZoomSegment(start: start, end: min(start + 2, sourceDuration))
        guard zoom.end - zoom.start >= Self.minimumZoomLength else { return }
        perform("Add Zoom", undoManager: undoManager) { $0.zooms.append(zoom) }
        selection = .zoom(zoom.id)
    }

    /// Replaces the zooms with ones suggested from the recorded clicks.
    func suggestZooms(undoManager: UndoManager?) {
        let zooms = AutoZoom.segments(for: cursorTrack?.clicks ?? [], duration: sourceDuration)
        perform("Suggest Zooms", undoManager: undoManager) { $0.zooms = zooms }
    }

    /// Moves or resizes a zoom during a drag. `seconds` is how far it's been dragged along the final
    /// video; zooms keep their place in the recording, so the drag is converted back to recording time.
    func dragZoom(_ id: UUID, _ edit: BlockEdit, by seconds: Double) {
        beginGesture()
        guard let original = gestureStart?.zooms.first(where: { $0.id == id }) else { return }
        let map = timeMap
        let limit = sourceDuration
        func moved(_ time: Double) -> Double {
            map.sourceTime(at: map.outputTime(at: time) + seconds)
        }
        update { edits in
            guard let index = edits.zooms.firstIndex(where: { $0.id == id }) else { return }
            switch edit {
            case .move:
                let length = original.end - original.start
                let start = min(max(moved(original.start), 0), limit - length)
                edits.zooms[index].start = start
                edits.zooms[index].end = start + length
            case .trimStart:
                edits.zooms[index].start = min(max(moved(original.start), 0), original.end - Self.minimumZoomLength)
            case .trimEnd:
                edits.zooms[index].end = max(min(moved(original.end), limit), original.start + Self.minimumZoomLength)
            }
        }
    }

    // MARK: - Notes

    var selectedNote: Note? {
        guard case .note(let id) = selection else { return nil }
        return edits.notes.first { $0.id == id }
    }

    /// Whether `note` is on screen at the playhead.
    func isShowing(_ note: Note) -> Bool {
        let time = timeMap.sourceTime(at: currentTime)
        return time >= note.start && time <= note.end
    }

    /// The size of a note on the frame, in pixels.
    func noteSize(_ note: Note) -> CGSize {
        (noteImages[note.text] ?? NoteImage.make(text: note.text, canvasSize: canvasSize))?.extent.size ?? .zero
    }

    /// Adds a three-second note at the playhead and selects it.
    func addNote(undoManager: UndoManager?) {
        let start = timeMap.sourceTime(at: currentTime)
        let note = Note(start: start, duration: min(3, max(sourceDuration - start, 0.5)))
        perform("Add Note", undoManager: undoManager) { $0.notes.append(note) }
        selection = .note(note.id)
    }

    /// Changes a note while its text is typed or it's dragged around the preview; finish with `endGesture`.
    func updateNote(_ id: UUID, _ change: (inout Note) -> Void) {
        update { edits in
            if let index = edits.notes.firstIndex(where: { $0.id == id }) {
                change(&edits.notes[index])
            }
        }
    }

    /// Moves or resizes a note on the timeline during a drag, like a zoom.
    func dragNote(_ id: UUID, _ edit: BlockEdit, by seconds: Double) {
        beginGesture()
        guard let original = gestureStart?.notes.first(where: { $0.id == id }) else { return }
        let map = timeMap
        let limit = sourceDuration
        func moved(_ time: Double) -> Double {
            map.sourceTime(at: map.outputTime(at: time) + seconds)
        }
        update { edits in
            guard let index = edits.notes.firstIndex(where: { $0.id == id }) else { return }
            switch edit {
            case .move:
                edits.notes[index].start = min(max(moved(original.start), 0), limit - original.duration)
            case .trimStart:
                let start = min(max(moved(original.start), 0), original.end - 0.5)
                edits.notes[index].start = start
                edits.notes[index].duration = original.end - start
            case .trimEnd:
                edits.notes[index].duration = max(min(moved(original.end), limit), original.start + 0.5) - original.start
            }
        }
    }

    // MARK: - Audio

    /// Volume and mute for a timeline audio row: one of the recording's own tracks or an imported file.
    func mix(for row: TimelineRow) -> TrackMix? {
        switch row {
        case .recordedAudio(let index): edits.recordedAudio[safe: index]
        case .importedAudio(let id): edits.importedAudio.first { $0.id == id }?.mix
        default: nil
        }
    }

    /// Changes a row's volume or mute. Pass `undoManager` for a single change, or leave it out
    /// while a volume slider is being dragged and call `endGesture` when it's let go.
    func setMix(_ mix: TrackMix, for row: TimelineRow, actionName: String = "Change Volume", undoManager: UndoManager? = nil, isDragging: Bool = false) {
        let change: (inout TimelineEdits) -> Void = { edits in
            switch row {
            case .recordedAudio(let index) where edits.recordedAudio.indices.contains(index):
                edits.recordedAudio[index] = mix
            case .importedAudio(let id):
                if let index = edits.importedAudio.firstIndex(where: { $0.id == id }) {
                    edits.importedAudio[index].mix = mix
                }
            default:
                break
            }
        }
        if isDragging {
            update(change)
        } else {
            perform(actionName, undoManager: undoManager, change)
        }
    }

    /// Copies an audio file into the project and adds it at the playhead.
    func importAudio(from url: URL, undoManager: UndoManager?) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = "\(UUID().uuidString).\(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)"
        let destination = project.audioFolderURL.appending(path: fileName)
        do {
            try FileManager.default.createDirectory(at: project.audioFolderURL, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            let asset = AVURLAsset(url: destination)
            guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
                try? FileManager.default.removeItem(at: destination)
                errorMessage = "“\(url.lastPathComponent)” has no audio."
                return
            }
            let clip = AudioClip(
                fileName: fileName,
                name: url.deletingPathExtension().lastPathComponent,
                duration: try await asset.load(.duration).seconds,
                offset: currentTime
            )
            perform("Add Audio", undoManager: undoManager) { $0.importedAudio.append(clip) }
            selection = .audio(clip.id)
        } catch {
            errorMessage = "The audio couldn't be added: \(error.localizedDescription)"
        }
    }

    /// Slides an imported audio file along the final video during a drag. It can start before the
    /// video, which skips its beginning.
    func dragAudio(_ id: UUID, by seconds: Double) {
        beginGesture()
        guard let original = gestureStart?.importedAudio.first(where: { $0.id == id }) else { return }
        let end = duration
        update { edits in
            guard let index = edits.importedAudio.firstIndex(where: { $0.id == id }) else { return }
            edits.importedAudio[index].offset = min(max(original.offset + seconds, -original.duration + 0.5), end - 0.5)
        }
    }

    // MARK: - Webcam

    /// The stretch of the recording the webcam covers, following the timeline as it's edited.
    var webcamRange: ClosedRange<Double>? {
        guard let range = scene?.webcamRange else { return nil }
        let offset = edits.webcamOffset ?? range.lowerBound
        return offset...(offset + range.upperBound - range.lowerBound)
    }

    /// Copies a video into the project and uses it for the webcam bubble, starting at the playhead.
    func importWebcam(from url: URL, undoManager: UndoManager?) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = "webcam-\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)"
        let destination = project.url.appending(path: fileName)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            guard try await !AVURLAsset(url: destination).loadTracks(withMediaType: .video).isEmpty else {
                try? FileManager.default.removeItem(at: destination)
                errorMessage = "“\(url.lastPathComponent)” has no video."
                return
            }
            let start = timeMap.sourceTime(at: currentTime)
            perform("Use Webcam Video", undoManager: undoManager) { edits in
                edits.webcamFileName = fileName
                edits.webcamOffset = start
            }
        } catch {
            errorMessage = "The video couldn't be added: \(error.localizedDescription)"
        }
    }

    /// Slides the webcam video against the recording during a drag, to line it up.
    func dragWebcam(by seconds: Double) {
        beginGesture()
        guard let range = scene?.webcamRange else { return }
        let original = gestureStart?.webcamOffset ?? range.lowerBound
        let length = range.upperBound - range.lowerBound
        let limit = sourceDuration
        update { edits in
            edits.webcamOffset = min(max(original + seconds, -length + 0.5), limit - 0.5)
        }
    }

    // MARK: - Rebuilding playback

    private func scheduleRebuild() {
        needsRebuild = false
        rebuildTask?.cancel()
        rebuildTask = Task {
            await rebuild()
        }
    }

    /// Lines the project up again as the timeline says, keeping the playhead on the same moment
    /// of the recording.
    private func rebuild() async {
        guard let screen else { return }
        let sourceTime = scene?.timeMap.sourceTime(at: currentTime) ?? 0
        let wasPlaying = isPlaying

        let scene: ProjectComposition
        do {
            scene = try await ProjectComposition.make(for: project, screen: screen, edits: edits)
        } catch {
            errorMessage = "The timeline couldn't be built: \(error.localizedDescription)"
            return
        }
        guard !Task.isCancelled else { return }
        self.scene = scene

        // The recording's audio tracks get default volumes the first time they're seen.
        if edits.recordedAudio.count < scene.recordedAudio.count {
            isRestoring = true
            edits.recordedAudio += Array(repeating: TrackMix(), count: scene.recordedAudio.count - edits.recordedAudio.count)
            isRestoring = false
        }

        let item = AVPlayerItem(asset: scene.composition)
        // Keep voices at their normal pitch in sped-up or slowed-down clips.
        item.audioTimePitchAlgorithm = .timeDomain
        item.audioMix = scene.audioMix(edits: edits)
        player.replaceCurrentItem(with: item)
        await applyRenderer()
        seek(to: scene.timeMap.outputTime(at: sourceTime))
        if wasPlaying {
            player.play()
        }
    }

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task {
            // Dragging a slider changes settings many times a second; rebuild once it pauses briefly.
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            await applyRenderer()
        }
    }

    /// Rebuilds the frame renderer and hands it to the player. Called whenever the look changes.
    private func applyRenderer() async {
        guard let item = player.currentItem, let renderer = await makeRenderer(), let scene else { return }
        item.videoComposition = scene.videoComposition(renderer: renderer)

        // A paused player keeps showing the old frame until it's asked for this one again.
        if !isPlaying {
            await player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    /// Everything an export needs: the timeline, how to draw it, and how loud each track is.
    func exportJob() async -> ExportJob? {
        guard let scene, let renderer = await makeRenderer() else { return nil }
        return ExportJob(scene: scene, renderer: renderer, audioMix: scene.audioMix(edits: edits), name: project.name)
    }

    /// A frame renderer for the current settings and timeline.
    private func makeRenderer() async -> FrameRenderer? {
        guard let scene else { return nil }

        if let cursorTrack, cursorPathSmoothing != settings.cursorSmoothing {
            let smoothing = settings.cursorSmoothing
            cursorPath = await Task.detached {
                CursorPath(track: cursorTrack, smoothing: smoothing)
            }.value
            cursorPathSmoothing = smoothing
        }

        var images: [UUID: CIImage] = [:]
        for note in edits.notes {
            if noteImages[note.text] == nil {
                noteImages[note.text] = NoteImage.make(text: note.text, canvasSize: canvasSize)
            }
            images[note.id] = noteImages[note.text]
        }
        // Forget images of text that's no longer used, e.g. from typing.
        let texts = Set(edits.notes.map(\.text))
        noteImages = noteImages.filter { texts.contains($0.key) }

        let renderer = FrameRenderer(
            videoSize: videoSize,
            cursorPath: cursorPath,
            sprite: sprite,
            pixelsPerPoint: pixelsPerPoint,
            settings: settings,
            zoomSegments: edits.zooms,
            camera: currentZoomCamera(),
            firstFrame: firstFrame,
            notes: edits.notes,
            noteImages: images,
            timeMap: scene.timeMap
        )
        return renderer
    }

    /// The zoom camera for the current zooms and zoom level, worked out again only when they change.
    private func currentZoomCamera() -> ZoomCamera {
        if let zoomCamera, zoomCamera.zooms == edits.zooms, zoomCamera.level == settings.zoomLevel {
            return zoomCamera.camera
        }
        let camera = ZoomCamera(segments: edits.zooms, cursor: cameraCursor, clicks: cursorTrack?.clicks ?? [], zoomLevel: settings.zoomLevel)
        zoomCamera = (camera, edits.zooms, settings.zoomLevel)
        return camera
    }

    private nonisolated static func firstFrame(of asset: AVAsset) async -> CIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceAfter = .positiveInfinity
        guard let (image, _) = try? await generator.image(at: .zero) else { return nil }
        return CIImage(cgImage: image)
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            // Save once changes settle rather than on every step of a drag.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    /// Saves straight away if there are unsaved changes.
    private func saveNow() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        save()
    }

    private func save() {
        saveTask = nil
        do {
            try ProjectFile(settings: settings, edits: edits).write(to: project.projectFileURL)
        } catch {
            errorMessage = "Your changes couldn't be saved: \(error.localizedDescription)"
        }
    }
}
