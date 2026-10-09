//
//  EditorModel.swift
//  Scope
//

import AVFoundation
import Combine
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

    private var timeObserver: Any?
    private var statusTask: Task<Void, Never>?

    init(project: ScopeProject) {
        self.project = project
    }

    func load() async {
        let asset = AVURLAsset(url: project.videoURL)
        do {
            duration = try await asset.load(.duration).seconds
        } catch {
            errorMessage = "The recording couldn't be opened: \(error.localizedDescription)"
            return
        }

        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))

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

    func seek(to time: TimeInterval) {
        currentTime = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
