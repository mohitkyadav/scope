//
//  ProjectComposition.swift
//  Scope
//

import AVFoundation

/// A recorded audio track, named by what it most likely holds.
nonisolated struct RecordedAudioTrack: Sendable {
    let trackID: CMPersistentTrackID
    let name: String
}

/// A project's videos and audio on one timeline, following the timeline's clips, ready to be
/// drawn by `SceneCompositor`.
nonisolated struct ProjectComposition: @unchecked Sendable {
    let composition: AVComposition
    let screenTrackID: CMPersistentTrackID
    let webcamTrackID: CMPersistentTrackID?
    /// The recording's own audio tracks, in the same order as `TimelineEdits.recordedAudio`.
    let recordedAudio: [RecordedAudioTrack]
    /// Imported audio tracks, by `AudioClip.id`.
    let importedAudio: [UUID: CMPersistentTrackID]
    let timeMap: TimeMap
    /// The stretch of the recording the webcam covers, in recording time.
    let webcamRange: ClosedRange<Double>?

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

    /// Volume for each audio track; muted tracks are silent.
    func audioMix(edits: TimelineEdits) -> AVAudioMix {
        var parameters: [AVAudioMixInputParameters] = []
        for (index, track) in recordedAudio.enumerated() {
            let mix = index < edits.recordedAudio.count ? edits.recordedAudio[index] : TrackMix()
            parameters.append(Self.parameters(trackID: track.trackID, mix: mix))
        }
        for clip in edits.importedAudio {
            if let trackID = importedAudio[clip.id] {
                parameters.append(Self.parameters(trackID: trackID, mix: clip.mix))
            }
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        return audioMix
    }

    private static func parameters(trackID: CMPersistentTrackID, mix: TrackMix) -> AVAudioMixInputParameters {
        let parameters = AVMutableAudioMixInputParameters()
        parameters.trackID = trackID
        parameters.setVolume(mix.muted ? 0 : Float(mix.volume), at: .zero)
        return parameters
    }

    /// Builds the final video's timeline: each clip of the recording in turn, at its speed, with
    /// the webcam alongside it; then any imported audio at its place in the final video.
    static func make(for project: ScopeProject, screen: AVAsset, edits: TimelineEdits) async throws -> ProjectComposition {
        let composition = AVMutableComposition()
        let timeMap = TimeMap(clips: edits.clips)

        guard let screenVideo = try await screen.loadTracks(withMediaType: .video).first,
              let screenTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw AVError(.noSourceTrack) }

        let screenVideoRange = try await screenVideo.load(.timeRange)
        var audioPairs: [(source: AVAssetTrack, target: AVMutableCompositionTrack, range: CMTimeRange)] = []
        var recordedAudio: [RecordedAudioTrack] = []
        let screenAudio = try await screen.loadTracks(withMediaType: .audio)
        for (index, audio) in screenAudio.enumerated() {
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            audioPairs.append((audio, track, try await audio.load(.timeRange)))
            recordedAudio.append(RecordedAudioTrack(trackID: track.trackID, name: try await name(of: audio, index: index, count: screenAudio.count)))
        }

        // The webcam: the recorded one with its own timing, or an imported video with the timeline's offset.
        // The asset is kept alongside its track: a track only holds a weak reference to its asset,
        // and inserting from a track whose asset is gone fails.
        var webcam: (asset: AVAsset, source: AVAssetTrack, target: AVMutableCompositionTrack, range: CMTimeRange, offset: Double, duration: Double)?
        let webcamURL = edits.webcamFileName.map { project.url.appending(path: $0) } ?? project.webcamURL
        let webcamOffset = edits.webcamOffset ?? (try? WebcamInfo.read(from: project.webcamInfoURL))?.offset
        if let webcamOffset, FileManager.default.fileExists(atPath: webcamURL.path) {
            let asset = AVURLAsset(url: webcamURL)
            if let video = try await asset.loadTracks(withMediaType: .video).first,
               let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                webcam = (asset, video, track, try await video.load(.timeRange), webcamOffset, try await asset.load(.duration).seconds)
            }
        }

        for (index, clip) in edits.clips.enumerated() {
            let at = timeMap.outputStarts[index]
            let range = CMTimeRange(start: time(clip.start), end: time(clip.end))

            try insert(range, of: screenVideo, covering: screenVideoRange, into: screenTrack, at: at, speed: clip.speed)
            for pair in audioPairs {
                try insert(range, of: pair.source, covering: pair.range, into: pair.target, at: at, speed: clip.speed)
            }

            // Recording time t shows webcam time t - offset; only insert the part the webcam covers.
            if let webcam {
                let start = max(clip.start, webcam.offset)
                let end = min(clip.end, webcam.offset + webcam.duration)
                if end > start {
                    try insert(
                        CMTimeRange(start: time(start - webcam.offset), end: time(end - webcam.offset)),
                        of: webcam.source,
                        covering: webcam.range,
                        into: webcam.target,
                        at: at + (start - clip.start) / clip.speed,
                        speed: clip.speed
                    )
                }
            }
        }

        var importedAudio: [UUID: CMPersistentTrackID] = [:]
        for clip in edits.importedAudio {
            let asset = AVURLAsset(url: project.audioFolderURL.appending(path: clip.fileName))
            guard let audio = try await asset.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            // Starting before the video means skipping the beginning of the file.
            let skip = max(-clip.offset, 0)
            let at = max(clip.offset, 0)
            let length = min(try await asset.load(.duration).seconds - skip, timeMap.duration - at)
            guard length > 0 else { continue }
            try track.insertTimeRange(CMTimeRange(start: time(skip), duration: time(length)), of: audio, at: time(at))
            importedAudio[clip.id] = track.trackID
        }

        let webcamTrackID = webcam.flatMap { $0.target.segments.isEmpty ? nil : $0.target.trackID }
        return ProjectComposition(
            composition: composition,
            screenTrackID: screenTrack.trackID,
            webcamTrackID: webcamTrackID,
            recordedAudio: recordedAudio,
            importedAudio: importedAudio,
            timeMap: timeMap,
            webcamRange: webcam.map { $0.offset...($0.offset + $0.duration) }
        )
    }

    /// Inserts `range` of `source` at `output` seconds, then stretches it to play at `speed`.
    /// Tracks in a recording can be a little shorter than the recording (audio often ends a few
    /// frames early), and inserting past a track's end fails, so only the part `available` from
    /// the track is inserted, at the matching position.
    private static func insert(_ range: CMTimeRange, of source: AVAssetTrack, covering available: CMTimeRange, into track: AVMutableCompositionTrack, at output: Double, speed: Double) throws {
        let covered = range.intersection(available)
        guard covered.duration.seconds > 0.001 else { return }
        let at = time(output + (covered.start - range.start).seconds / speed)
        try track.insertTimeRange(covered, of: source, at: at)
        if speed != 1 {
            track.scaleTimeRange(CMTimeRange(start: at, duration: covered.duration), toDuration: time(covered.duration.seconds / speed))
        }
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 60_000)
    }

    /// Recordings don't label their audio tracks. Scope records system audio in stereo and most
    /// microphones are mono, so go by the channel count.
    private static func name(of track: AVAssetTrack, index: Int, count: Int) async throws -> String {
        let channels = try await track.load(.formatDescriptions).first?.audioStreamBasicDescription?.mChannelsPerFrame
        switch channels {
        case 1: return "Microphone"
        case 2: return "System audio"
        default: return count == 1 ? "Audio" : "Audio \(index + 1)"
        }
    }
}
