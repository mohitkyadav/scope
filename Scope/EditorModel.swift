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
            if settings != oldValue {
                settingsChanged()
            }
        }
    }

    private var videoSize: CGSize = .zero
    private var cursorTrack: CursorTrack?
    private var cursorPath: CursorPath?
    private var cameraPath: CursorPath?
    /// The smoothing `cursorPath` was built with, so it's only rebuilt when that changes.
    private var cursorPathSmoothing: Double?
    private var renderTask: Task<Void, Never>?
    private var pixelsPerPoint: CGFloat = 2
    private var sprite: CursorSprite?
    private var firstFrame: CIImage?

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
            zoomSegments = AutoZoom.segments(for: track.clicks, duration: duration)
            cameraPath = await Task.detached { CursorPath.camera(for: track) }.value
        }
        sprite = CursorSprite.arrow()
        firstFrame = await Self.firstFrame(of: asset)

        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
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
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusTask?.cancel()
        statusTask = nil
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
        guard let item = player.currentItem else { return }

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
        do {
            item.videoComposition = try await Self.makeVideoComposition(for: item.asset, renderer: renderer)
        } catch {
            errorMessage = "The preview couldn't be set up: \(error.localizedDescription)"
            return
        }

        // A paused player keeps showing the old frame until it's asked for this one again.
        if !isPlaying {
            await player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    /// Built outside the main actor because Core Image calls the handler on its own threads.
    private nonisolated static func makeVideoComposition(
        for asset: AVAsset,
        renderer: FrameRenderer
    ) async throws -> AVVideoComposition {
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let frame = renderer.render(source: request.sourceImage, time: request.compositionTime.seconds)
            request.finish(with: frame, context: nil)
        }
        composition.renderSize = renderer.canvasSize

        // Recordings only get a new video frame when something on screen changes, so a still screen
        // can go a quarter of a second or more without one. Render at a steady 60 fps instead of
        // following the video's frames, so the cursor keeps moving smoothly in between.
        composition.frameDuration = CMTime(value: 1, timescale: 60)
        composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        return composition
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
