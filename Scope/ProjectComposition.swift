//
//  ProjectComposition.swift
//  Scope
//

import AVFoundation

/// A project's videos on one timeline, ready to be drawn by `SceneCompositor`.
nonisolated struct ProjectComposition: @unchecked Sendable {
    let composition: AVComposition
    let screenTrackID: CMPersistentTrackID
    let webcamTrackID: CMPersistentTrackID?

    func videoComposition(renderer: FrameRenderer) -> AVVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = SceneCompositor.self
        videoComposition.renderSize = renderer.canvasSize
        videoComposition.instructions = [
            SceneInstruction(
                timeRange: CMTimeRange(start: .zero, duration: composition.duration),
                renderer: renderer,
                screenTrackID: screenTrackID,
                webcamTrackID: webcamTrackID
            ),
        ]

        // Recordings only get a new video frame when something on screen changes, so a still screen
        // can go a quarter of a second or more without one. Render at a steady 60 fps instead of
        // following the video's frames, so the cursor keeps moving smoothly in between.
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)
        videoComposition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        return videoComposition
    }

    /// Lines the project's videos up on one timeline: the screen video and its audio tracks from
    /// the start, and the webcam video, if there is one, from when it started recording.
    static func make(for project: ScopeProject, screen: AVAsset) async throws -> ProjectComposition {
        let composition = AVMutableComposition()
        let duration = try await screen.load(.duration)
        let wholeVideo = CMTimeRange(start: .zero, duration: duration)

        guard let screenVideo = try await screen.loadTracks(withMediaType: .video).first,
              let screenTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw AVError(.noSourceTrack) }
        try screenTrack.insertTimeRange(wholeVideo, of: screenVideo, at: .zero)

        // System audio and the microphone are separate tracks; keep both.
        for audio in try await screen.loadTracks(withMediaType: .audio) {
            let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try track?.insertTimeRange(wholeVideo, of: audio, at: .zero)
        }

        var webcamTrackID: CMPersistentTrackID?
        if let info = try? WebcamInfo.read(from: project.webcamInfoURL) {
            let webcam = AVURLAsset(url: project.webcamURL)
            if let webcamVideo = try await webcam.loadTracks(withMediaType: .video).first,
               let webcamTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                // Webcam time 0 belongs at `offset` in the screen video. If the webcam started first,
                // skip its beginning instead.
                let webcamDuration = try await webcam.load(.duration).seconds
                let skip = max(-info.offset, 0)
                let at = max(info.offset, 0)
                let length = min(webcamDuration - skip, duration.seconds - at)
                if length > 0 {
                    try webcamTrack.insertTimeRange(
                        CMTimeRange(start: CMTime(seconds: skip, preferredTimescale: 600), duration: CMTime(seconds: length, preferredTimescale: 600)),
                        of: webcamVideo,
                        at: CMTime(seconds: at, preferredTimescale: 600)
                    )
                    webcamTrackID = webcamTrack.trackID
                }
            }
        }

        return ProjectComposition(composition: composition, screenTrackID: screenTrack.trackID, webcamTrackID: webcamTrackID)
    }
}
