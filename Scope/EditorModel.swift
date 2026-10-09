//
//  EditorModel.swift
//  Scope
//

import AVFoundation
import Combine
import CoreImage
import Observation

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
    private var cameraPath: CursorPath?
    /// The smoothing `cursorPath` was built with, so it's only rebuilt when that changes.
    private var cursorPathSmoothing: Double?
    private var pixelsPerPoint: CGFloat = 2
    private var sprite: CursorSprite?
    private var firstFrame: CIImage?
    /// The project's videos and audio lined up as the timeline says; what the player plays.
    private(set) var scene: ProjectComposition?

    private var renderTask: Task<Void, Never>?
    private var rebuildTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var statusTask: Task<Void, Never>?

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
            cameraPath = await Task.detached { CursorPath.camera(for: track) }.value
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

        statusTask = Task { [weak self, player] in
            for await status in player.publisher(for: \.timeControlStatus).values {
                self?.isPlaying = status != .paused
            }
        }
    }

    func close() {
        if saveTask != nil {
            saveTask?.cancel()
            save()
        }
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusTask?.cancel()
        statusTask = nil
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
        guard let item = player.currentItem, let scene else { return }

        if let cursorTrack, cursorPathSmoothing != settings.cursorSmoothing {
            let smoothing = settings.cursorSmoothing
            cursorPath = await Task.detached {
                CursorPath(track: cursorTrack, smoothing: smoothing)
            }.value
            cursorPathSmoothing = smoothing
        }

        let renderer = FrameRenderer(
            videoSize: videoSize,
            cursorPath: cursorPath,
            sprite: sprite,
            pixelsPerPoint: pixelsPerPoint,
            settings: settings,
            zoomSegments: edits.zooms,
            cameraPath: cameraPath,
            firstFrame: firstFrame,
            timeMap: scene.timeMap
        )
        item.videoComposition = scene.videoComposition(renderer: renderer)

        // A paused player keeps showing the old frame until it's asked for this one again.
        if !isPlaying {
            await player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
        }
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

    private func save() {
        saveTask = nil
        do {
            try ProjectFile(settings: settings, edits: edits).write(to: project.projectFileURL)
        } catch {
            errorMessage = "Your changes couldn't be saved: \(error.localizedDescription)"
        }
    }
}
