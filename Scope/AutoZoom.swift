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
    /// This zoom's own settings. `nil` uses the defaults from the Zoom settings.
    var level: Double?
    var transition: Double?
    var followsCursor: Bool?

    var hasOwnSettings: Bool { level != nil || transition != nil || followsCursor != nil }
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

    /// The zoom at a moment: how far in it is, from 0 (not at all) to 1 (fully), and how far it
    /// goes when fully in.
    struct State {
        var amount = 0.0
        var level = 1.0

        /// How much the recording is magnified: 1 when not zoomed, `level` when fully zoomed.
        var scale: Double { 1 + (level - 1) * amount }
    }

    /// The zoom at `time`. Each segment springs in from its start and springs back out so it's done by
    /// its end, each taking its transition time (or half the segment if that's shorter). Segments
    /// without their own level or transition use the defaults.
    static func state(at time: Double, segments: [ZoomSegment], defaultLevel: Double, defaultTransition: Double) -> State {
        var state = State()
        for segment in segments where time >= segment.start && time <= segment.end {
            let level = segment.level ?? defaultLevel
            guard level > 1 else { continue }
            let transition = max(min(segment.transition ?? defaultTransition, (segment.end - segment.start) / 2), 0.01)
            let zoomedIn = spring(time - segment.start, duration: transition)
            let zoomedOut = spring(time - (segment.end - transition), duration: transition)
            let amount = zoomedIn * (1 - zoomedOut)
            if amount > state.amount {
                state = State(amount: amount, level: level)
            }
        }
        return state
    }

    /// A critically damped spring going from 0 to 1 that has settled after `duration` seconds: it
    /// starts quickly and lands softly, without overshooting. Half done after about a quarter of the
    /// duration and 90% after about 60%, which is how polished screen recordings zoom.
    static func spring(_ elapsed: Double, duration: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        // (1 + x)·e^-x falls to 1% at x ≈ 6.64, so this stiffness settles in `duration`.
        let x = 6.64 * elapsed / max(duration, 0.01)
        return min((1 - (1 + x) * exp(-x)) / 0.99, 1)
    }
}
