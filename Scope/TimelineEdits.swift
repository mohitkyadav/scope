//
//  TimelineEdits.swift
//  Scope
//

import Foundation

/// A stretch of the recording kept in the final video, played at `speed`.
/// `start` and `end` are seconds in the recording.
nonisolated struct Clip: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    var speed = 1.0

    /// How long the clip lasts in the final video.
    var duration: Double { (end - start) / speed }
}

/// Text shown over the video for a while. Times are seconds in the recording, so a note stays
/// with the moment it describes when clips around it are trimmed.
nonisolated struct Note: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var text = "Note"
    var start: Double
    var duration = 3.0
    /// Centre of the note as fractions of the frame, from the top left.
    var x = 0.5
    var y = 0.12

    var end: Double { start + duration }
}

/// A stretch of the recording where the webcam bubble is hidden. It shrinks and fades out from
/// `start` and is back by `end`. Times are seconds in the recording, like zooms.
nonisolated struct WebcamHide: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double

    /// How long the bubble takes to go and come back.
    static let fade = 0.3

    /// How much of the bubble shows at `time`, from 0 (hidden) to 1, easing out and back in.
    static func visibility(at time: Double, hides: [WebcamHide]) -> Double {
        var visibility = 1.0
        for hide in hides where time > hide.start && time < hide.end {
            let fade = min(Self.fade, (hide.end - hide.start) / 2)
            let progress = min((time - hide.start) / fade, (hide.end - time) / fade, 1)
            visibility = min(visibility, 1 - progress * progress * (3 - 2 * progress))
        }
        return visibility
    }
}

/// Volume for one of the recording's own audio tracks (system audio or microphone).
nonisolated struct TrackMix: Codable, Equatable, Sendable {
    var volume = 1.0
    var muted = false
}

/// An audio file added to the project, e.g. music. Its `offset` is seconds into the final video,
/// so it stays put when the recording is trimmed.
nonisolated struct AudioClip: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    /// File name inside the project's `audio` folder.
    var fileName: String
    var name: String
    /// Length of the file in seconds.
    var duration: Double
    var offset = 0.0
    var mix = TrackMix()
}

/// Everything the timeline changes about a project.
nonisolated struct TimelineEdits: Codable, Equatable, Sendable {
    /// In playback order, not overlapping, with increasing `start`.
    var clips: [Clip] = []
    /// Times are seconds in the recording.
    var zooms: [ZoomSegment] = []
    var notes: [Note] = []
    /// Where the webcam bubble is hidden. Times are seconds in the recording.
    var webcamHides: [WebcamHide] = []
    /// One per audio track in the recording, in track order.
    var recordedAudio: [TrackMix] = []
    var importedAudio: [AudioClip] = []
    /// A video file in the project used instead of the recorded webcam, and how far into the
    /// recording it starts. `nil` means the recorded webcam and its own timing.
    var webcamFileName: String?
    var webcamOffset: Double?

    /// The untouched recording: one clip covering all of it, with the suggested zooms.
    static func initial(duration: Double, zooms: [ZoomSegment]) -> TimelineEdits {
        TimelineEdits(clips: [Clip(start: 0, end: duration)], zooms: zooms)
    }

    private enum CodingKeys: String, CodingKey {
        case clips, zooms, notes, webcamHides, recordedAudio, importedAudio, webcamFileName, webcamOffset
    }

    init(clips: [Clip] = [], zooms: [ZoomSegment] = []) {
        self.clips = clips
        self.zooms = zooms
    }

    /// Anything missing from the file keeps its default, so projects saved by older versions still open.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clips = (try? container.decodeIfPresent([Clip].self, forKey: .clips)) ?? []
        zooms = (try? container.decodeIfPresent([ZoomSegment].self, forKey: .zooms)) ?? []
        notes = (try? container.decodeIfPresent([Note].self, forKey: .notes)) ?? []
        webcamHides = (try? container.decodeIfPresent([WebcamHide].self, forKey: .webcamHides)) ?? []
        recordedAudio = (try? container.decodeIfPresent([TrackMix].self, forKey: .recordedAudio)) ?? []
        importedAudio = (try? container.decodeIfPresent([AudioClip].self, forKey: .importedAudio)) ?? []
        webcamFileName = try? container.decodeIfPresent(String.self, forKey: .webcamFileName)
        webcamOffset = try? container.decodeIfPresent(Double.self, forKey: .webcamOffset)
    }
}

/// Converts between time in the final video ("output") and time in the recording ("source").
nonisolated struct TimeMap: Sendable {
    let clips: [Clip]
    /// Where each clip starts in the final video.
    let outputStarts: [Double]
    /// Length of the final video.
    let duration: Double

    init(clips: [Clip]) {
        self.clips = clips
        var starts: [Double] = []
        var position = 0.0
        for clip in clips {
            starts.append(position)
            position += clip.duration
        }
        outputStarts = starts
        duration = position
    }

    /// The index of the clip playing at `output`.
    func clipIndex(at output: Double) -> Int? {
        guard !clips.isEmpty else { return nil }
        let index = outputStarts.lastIndex { $0 <= output } ?? 0
        return min(index, clips.count - 1)
    }

    /// The moment in the recording shown at `output` in the final video.
    func sourceTime(at output: Double) -> Double {
        guard let index = clipIndex(at: output) else { return output }
        let clip = clips[index]
        let into = min(max(output - outputStarts[index], 0), clip.duration)
        return clip.start + into * clip.speed
    }

    /// Where a moment of the recording appears in the final video. Moments that were cut out
    /// map to where the cut is, so ranges across a cut stay continuous.
    func outputTime(at source: Double) -> Double {
        for (index, clip) in clips.enumerated() {
            if source < clip.start {
                return outputStarts[index]
            }
            if source <= clip.end {
                return outputStarts[index] + (source - clip.start) / clip.speed
            }
        }
        return duration
    }
}
