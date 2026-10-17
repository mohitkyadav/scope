//
//  AutoZoom.swift
//  Scope
//

import CoreGraphics
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
    var easing: ZoomEasing?
    /// Whether the spotlight is on during this zoom. `nil` follows the Spotlight setting.
    var spotlight: Bool?
    /// The point the zoom is centred on, as fractions of the recording from the top left, when it's
    /// been picked by hand. `nil` aims at the first click and follows the cursor as set.
    var focusX: Double?
    var focusY: Double?
    /// Added or changed by hand, so suggesting zooms again keeps it. `nil` for suggested zooms.
    var isManual: Bool?

    var focus: CGPoint? {
        guard let focusX, let focusY else { return nil }
        return CGPoint(x: focusX, y: focusY)
    }

    var hasOwnSettings: Bool {
        level != nil || transition != nil || followsCursor != nil || easing != nil || focus != nil || spotlight != nil
    }

    func overlaps(_ other: ZoomSegment) -> Bool {
        start < other.end && other.start < end
    }
}

/// How a zoom moves in and out.
nonisolated enum ZoomEasing: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Starts quickly and lands softly, like a camera on a spring.
    case spring
    /// Eases in and out evenly, gentle at both ends.
    case smooth
    /// Fast from the start, with a short soft landing.
    case snappy

    var id: Self { self }

    var name: String {
        switch self {
        case .spring: "Spring"
        case .smooth: "Smooth"
        case .snappy: "Snappy"
        }
    }

    /// How far along a move is, from 0 to 1, `elapsed` seconds into a move that takes `duration`.
    func progress(_ elapsed: Double, duration: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        let x = min(elapsed / max(duration, 0.01), 1)
        switch self {
        case .spring:
            return AutoZoom.spring(elapsed, duration: duration)
        case .smooth:
            return x * x * x * (x * (6 * x - 15) + 10)
        case .snappy:
            return 1 - pow(1 - x, 5)
        }
    }
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

    /// One zoom segment per group of clicks and typing: ones that follow each other within a few
    /// seconds in roughly the same part of the screen. `typing` is from `typingBursts`.
    /// `sensitivity` runs from 0 (fewer, longer zooms) to 1 (more, shorter ones); at 0.5 clicks
    /// up to 3 s apart and a third of the screen away from each other share a zoom.
    static func segments(for clicks: [CursorTrack.Click], typing: [CursorTrack.Click] = [], duration: Double, sensitivity: Double = 0.5) -> [ZoomSegment] {
        // Doubles the reach at 0 and halves it at 1.
        let reach = pow(2, (0.5 - min(max(sensitivity, 0), 1)) * 2)
        let maxGap = maxClickGap * reach
        let maxDistance = maxClickDistance * reach
        let minGap = minGap * reach

        // Clicks outside the recorded area, e.g. on another display, aren't in the video.
        let events = (clicks + typing)
            .filter { (0...1).contains($0.x) && (0...1).contains($0.y) }
            .sorted { $0.t < $1.t }

        var groups: [[CursorTrack.Click]] = []
        for event in events {
            if let previous = groups.last?.last,
               event.t - (previous.t + previous.duration) <= maxGap,
               hypot(event.x - previous.x, event.y - previous.y) <= maxDistance {
                groups[groups.count - 1].append(event)
            } else {
                groups.append([event])
            }
        }

        var segments: [ZoomSegment] = []
        for group in groups {
            guard let first = group.first else { continue }
            let end = group.map { $0.t + $0.duration }.max() ?? first.t
            let segment = ZoomSegment(
                start: max(0, first.t - leadIn),
                end: min(duration, end + hold)
            )
            if let previous = segments.last, segment.start - previous.end < minGap {
                segments[segments.count - 1].end = max(previous.end, segment.end)
            } else {
                segments.append(segment)
            }
        }
        return segments
    }

    /// Key presses this close together are one stretch of typing.
    private static let maxKeyGap = 1.5
    /// Fewer presses than this, like Return or an arrow key, aren't typing.
    private static let minKeyPresses = 3
    /// Typing this soon after a click is probably in what was clicked, e.g. a text field.
    private static let clickToTyping = 15.0

    /// Stretches of typing, each as a click lasting as long as the typing, placed where the typing
    /// probably was: at the last click before it, or else at the cursor. Only when keys were pressed
    /// is known, not where the text cursor was.
    static func typingBursts(keyPresses: [Double], clicks: [CursorTrack.Click], cursor: CursorPath?) -> [CursorTrack.Click] {
        var bursts: [[Double]] = []
        for time in keyPresses.sorted() {
            if let last = bursts.last?.last, time - last <= maxKeyGap {
                bursts[bursts.count - 1].append(time)
            } else {
                bursts.append([time])
            }
        }

        let inside = clicks.filter { (0...1).contains($0.x) && (0...1).contains($0.y) }
        return bursts.compactMap { burst in
            guard burst.count >= minKeyPresses, let start = burst.first, let end = burst.last else { return nil }
            let point: CGPoint
            if let click = inside.last(where: { $0.t <= start && $0.t >= start - clickToTyping }) {
                point = CGPoint(x: click.x, y: click.y)
            } else if let position = cursor?.position(at: start), (0...1).contains(position.x), (0...1).contains(position.y) {
                point = position
            } else {
                return nil
            }
            return CursorTrack.Click(t: start, duration: end - start, x: point.x, y: point.y, button: .left)
        }
    }

    /// The zoom at a moment: how far in it is, from 0 (not at all) to 1 (fully), and how far it
    /// goes when fully in.
    struct State {
        var amount = 0.0
        var level = 1.0

        /// How much the recording is magnified: 1 when not zoomed, `level` when fully zoomed.
        var scale: Double { 1 + (level - 1) * amount }
    }

    /// The zoom at `time`. Each segment eases in from its start and back out so it's done by its end,
    /// each taking its transition time (or half the segment if that's shorter). Segments without
    /// their own settings use the defaults.
    static func state(at time: Double, segments: [ZoomSegment], defaultLevel: Double, defaultTransition: Double, defaultEasing: ZoomEasing = .spring) -> State {
        var state = State()
        for segment in segments {
            let level = segment.level ?? defaultLevel
            guard level > 1 else { continue }
            let amount = amount(of: segment, at: time, defaultTransition: defaultTransition, defaultEasing: defaultEasing)
            if amount > state.amount {
                state = State(amount: amount, level: level)
            }
        }
        return state
    }

    /// How far `segment` alone is zoomed in at `time`, from 0 to 1.
    static func amount(of segment: ZoomSegment, at time: Double, defaultTransition: Double, defaultEasing: ZoomEasing) -> Double {
        guard time >= segment.start, time <= segment.end else { return 0 }
        let transition = max(min(segment.transition ?? defaultTransition, (segment.end - segment.start) / 2), 0.01)
        let easing = segment.easing ?? defaultEasing
        let zoomedIn = easing.progress(time - segment.start, duration: transition)
        let zoomedOut = easing.progress(time - (segment.end - transition), duration: transition)
        return zoomedIn * (1 - zoomedOut)
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
