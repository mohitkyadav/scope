//
//  AutoZoom.swift
//  Scope
//

import Foundation

/// A stretch of the recording that's shown zoomed in. The view zooms in from `start` and is back
/// to the full frame by `end`; outside the segment it isn't zoomed at all.
nonisolated struct ZoomSegment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
}

nonisolated enum AutoZoom {
    /// Clicks closer together than this, in time and in position, are treated as one piece of work.
    private static let maxClickGap = 3.0
    private static let maxClickDistance = 0.3
    /// Segments start this long before the first click and end this long after the last one,
    /// so zooming in has finished by the click and zooming out starts after it.
    private static let leadIn = 0.8
    private static let hold = 1.6
    /// Segments with a shorter gap between them are joined, rather than zooming out and straight back in.
    private static let minGap = 1.0

    /// One zoom segment per group of clicks: clicks that follow each other within a few seconds
    /// in roughly the same part of the screen.
    static func segments(for clicks: [CursorTrack.Click], duration: Double) -> [ZoomSegment] {
        // Clicks outside the recorded area, e.g. on another display, aren't in the video.
        let clicks = clicks
            .filter { (0...1).contains($0.x) && (0...1).contains($0.y) }
            .sorted { $0.t < $1.t }

        var groups: [[CursorTrack.Click]] = []
        for click in clicks {
            if let previous = groups.last?.last,
               click.t - (previous.t + previous.duration) <= maxClickGap,
               hypot(click.x - previous.x, click.y - previous.y) <= maxClickDistance {
                groups[groups.count - 1].append(click)
            } else {
                groups.append([click])
            }
        }

        var segments: [ZoomSegment] = []
        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            let segment = ZoomSegment(
                start: max(0, first.t - leadIn),
                end: min(duration, last.t + last.duration + hold)
            )
            if let previous = segments.last, segment.start - previous.end < minGap {
                segments[segments.count - 1].end = max(previous.end, segment.end)
            } else {
                segments.append(segment)
            }
        }
        return segments
    }

    /// How far zoomed in the view is at `time`, from 0 (not at all) to 1 (fully). Each segment eases
    /// in over `transition` seconds from its start and out over the same time before its end, or
    /// half the segment each way if it's shorter than that.
    static func amount(at time: Double, segments: [ZoomSegment], transition: Double) -> Double {
        segments.reduce(0) { amount, segment in
            guard time >= segment.start, time <= segment.end else { return amount }
            let transition = max(min(transition, (segment.end - segment.start) / 2), 0.01)
            let zoomingIn = ease((time - segment.start) / transition)
            let zoomingOut = ease((segment.end - time) / transition)
            return max(amount, min(zoomingIn, zoomingOut))
        }
    }

    /// Slow at both ends, fast in the middle.
    private static func ease(_ progress: Double) -> Double {
        let x = min(max(progress, 0), 1)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
}
