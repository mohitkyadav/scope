//
//  EditorModel.swift
//  Scope
//

import AVFoundation
import Combine
import CoreImage
import Observation

/// Playback state for one project open in the editor.
@Observable
final class EditorModel {
    let project: ScopeProject
    let player = AVPlayer()

    private(set) var duration: TimeInterval = 0
    private(set) var currentTime: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var errorMessage: String?
    /// Where the preview zooms in, suggested from the recorded clicks.
    private(set) var zoomSegments: [ZoomSegment] = []

    var settings = EditorSettings() {
        didSet {
            if settings != oldValue, !isRestoringSettings {
                settingsChanged()
            }
        }
    }
    /// Set while loading saved settings, which shouldn't be saved straight back.
    private var isRestoringSettings = false

    /// The size of the frames the renderer draws.
    var canvasSize: CGSize { videoSize }
    var hasWebcam: Bool { scene?.webcamTrackID != nil }

    private var videoSize: CGSize = .zero
    private var cursorTrack: CursorTrack?
    private var cursorPath: CursorPath?
    private var cameraPath: CursorPath?
    /// The smoothing `cursorPath` was built with, so it's only rebuilt when that changes.
    private var cursorPathSmoothing: Double?
    private var renderTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var pixelsPerPoint: CGFloat = 2
    private var sprite: CursorSprite?
    private var firstFrame: CIImage?
    /// The screen video, its audio and the webcam video lined up on one timeline.
    private var scene: ProjectComposition?

    private var timeObserver: Any?
    private var statusTask: Task<Void, Never>?

    init(project: ScopeProject) {
        self.project = project
    }

    func load() async {
        let asset = AVURLAsset(url: project.videoURL)
        do {
            duration = try await asset.load(.duration).seconds
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                errorMessage = "The recording has no video."
                return
            }
            videoSize = try await videoTrack.load(.naturalSize)
            scene = try await ProjectComposition.make(for: project, screen: asset)
        } catch {
            errorMessage = "The recording couldn't be opened: \(error.localizedDescription)"
            return
        }

        // A project that hasn't been edited yet has no project file and uses the default settings.
        if let file = try? ProjectFile.read(from: project.projectFileURL) {
            isRestoringSettings = true
            settings = file.settings
            isRestoringSettings = false
        }

        // Without cursor data the video still plays, just with no cursor drawn.
        if let track = try? CursorTrack.read(from: project.cursorURL) {
            cursorTrack = track
            if track.areaWidth > 0 {
                pixelsPerPoint = videoSize.width / track.areaWidth
            }
            zoomSegments = AutoZoom.segments(for: track.clicks, duration: duration)
            cameraPath = await Task.detached { CursorPath.camera(for: track) }.value
        }
        sprite = CursorSprite.arrow()
        firstFrame = await Self.firstFrame(of: asset)

        guard let scene else { return }
        player.replaceCurrentItem(with: AVPlayerItem(asset: scene.composition))
        await applyRenderer()

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

    private func save() {
        saveTask = nil
        do {
            try ProjectFile(settings: settings).write(to: project.projectFileURL)
        } catch {
            errorMessage = "Your changes couldn't be saved: \(error.localizedDescription)"
        }
    }

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

    private func settingsChanged() {
        saveTask?.cancel()
        saveTask = Task {
            // Save once changes settle rather than on every step of a slider drag.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            save()
        }

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
            zoomSegments: zoomSegments,
            cameraPath: cameraPath,
            firstFrame: firstFrame
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

    func seek(to time: TimeInterval) {
        currentTime = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
