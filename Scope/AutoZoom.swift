//
//  AutoZoom.swift
//  Scope
//

import Foundation

/// A stretch of the recording that's shown zoomed in. Zooming in happens just before `start`
/// and zooming out just after `end`, so the view is fully zoomed for the whole segment.
nonisolated struct ZoomSegment: Identifiable, Equatable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
}

nonisolated enum AutoZoom {
    /// Clicks closer together than this, in time and in position, are treated as one piece of work.
    private static let maxClickGap = 3.0
    private static let maxClickDistance = 0.3
    /// Fully zoomed this long before the first click and after the last one.
    private static let leadIn = 0.3
    private static let hold = 1.2
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

    /// How far zoomed in the view is at `time`, from 0 (not at all) to 1 (fully), easing in over
    /// `transition` seconds before each segment and out over the same time after it.
    static func amount(at time: Double, segments: [ZoomSegment], transition: Double) -> Double {
        let transition = max(transition, 0.01)
        return segments.reduce(0) { amount, segment in
            let zoomingIn = ease((time - (segment.start - transition)) / transition)
            let zoomingOut = ease((segment.end + transition - time) / transition)
            return max(amount, min(zoomingIn, zoomingOut))
        }
    }

    /// Slow at both ends, fast in the middle.
    private static func ease(_ progress: Double) -> Double {
        let x = min(max(progress, 0), 1)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
}
