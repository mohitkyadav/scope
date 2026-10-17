//
//  ZoomCamera.swift
//  Scope
//

import CoreGraphics
import Foundation

/// Where the view points while zoomed in, worked out separately for each zoom segment.
///
/// Each zoom starts on its first click (or the cursor), then holds still while the cursor moves
/// around the middle of the zoomed-in view, and only glides after it when it heads towards an edge.
/// While typing it holds on where the typing is. A zoom with a point picked by hand stays on it.
/// Nothing outside a segment affects it, and outside segments the view isn't zoomed at all.
nonisolated struct ZoomCamera: Sendable {
    private static let rate = 60.0
    /// The cursor can move this far from the centre, as a fraction of the zoomed-in view, before the camera follows.
    private static let deadZone = 0.25
    /// How stiff the spring the camera pans on is; this settles in about a second, like the zooms.
    private static let stiffness = 6.0
    /// A click this soon after a zoom starts is what the zoom is about, so it starts there.
    private static let startClickWindow = 1.5

    private struct Track: Sendable {
        let start: Double
        let end: Double
        /// Focus points as fractions of the frame, one per 1/60 s from `start`.
        let points: [CGPoint]
    }

    private let tracks: [Track]

    /// `cursor`, `clicks` and `typing` (from `AutoZoom.typingBursts`) are in recording time, like the
    /// segments. Segments without their own level use `defaultLevel`.
    init(segments: [ZoomSegment], cursor: CursorPath?, clicks: [CursorTrack.Click], typing: [CursorTrack.Click] = [], defaultLevel: Double) {
        let events = (clicks + typing).sorted { $0.t < $1.t }
        tracks = segments.map { segment in
            let visible = 1 / max(segment.level ?? defaultLevel, 1)
            return Self.track(for: segment, cursor: cursor, clicks: events, typing: typing, visible: visible)
        }
    }

    /// The point the view is centred on at `time`, as fractions of the frame, or `nil` outside every segment.
    func focus(at time: Double) -> CGPoint? {
        guard let track = tracks.first(where: { time >= $0.start && time <= $0.end }), !track.points.isEmpty else { return nil }
        let index = min(max(Int(((time - track.start) * Self.rate).rounded()), 0), track.points.count - 1)
        return track.points[index]
    }

    /// Typing holds the camera on where it is for this long after the last key press.
    private static let typingHold = 0.5

    private static func track(for segment: ZoomSegment, cursor: CursorPath?, clicks: [CursorTrack.Click], typing: [CursorTrack.Click], visible: Double) -> Track {
        let step = 1 / rate
        let count = max(Int(((segment.end - segment.start) * rate).rounded(.up)), 0) + 1

        // A point picked by hand is where the zoom stays.
        if let focus = segment.focus {
            return Track(start: segment.start, end: segment.end, points: Array(repeating: clamp(focus, visible: visible), count: count))
        }

        let typing = typing.filter { $0.t <= segment.end && $0.t + $0.duration + typingHold >= segment.start }
        func cursorPosition(at time: Double) -> CGPoint {
            if let burst = typing.first(where: { time >= $0.t && time <= $0.t + $0.duration + typingHold }) {
                return CGPoint(x: burst.x, y: burst.y)
            }
            return cursor?.position(at: time) ?? CGPoint(x: 0.5, y: 0.5)
        }
        let firstClick = clicks.first {
            $0.t >= segment.start && $0.t <= min(segment.start + startClickWindow, segment.end)
                && (0...1).contains($0.x) && (0...1).contains($0.y)
        }
        var camera = clamp(firstClick.map { CGPoint(x: $0.x, y: $0.y) } ?? cursorPosition(at: segment.start), visible: visible)
        var target = camera
        var velocity = CGPoint.zero
        // A zoom that doesn't follow the cursor stays where it started.
        let follows = segment.followsCursor ?? true

        var points: [CGPoint] = []
        points.reserveCapacity(count)

        for index in 0..<count {
            guard follows else {
                points.append(camera)
                continue
            }
            let time = segment.start + Double(index) * step
            // The target only moves when the cursor leaves the middle of the view.
            let cursor = cursorPosition(at: time)
            let reach = visible * deadZone
            if cursor.x - target.x > reach { target.x = cursor.x - reach }
            if target.x - cursor.x > reach { target.x = cursor.x + reach }
            if cursor.y - target.y > reach { target.y = cursor.y - reach }
            if target.y - cursor.y > reach { target.y = cursor.y + reach }
            target = clamp(target, visible: visible)

            // The camera follows the target on a critically damped spring: a quick start, a soft stop.
            let omega = stiffness
            velocity.x += (omega * omega * (target.x - camera.x) - 2 * omega * velocity.x) * step
            velocity.y += (omega * omega * (target.y - camera.y) - 2 * omega * velocity.y) * step
            camera = clamp(CGPoint(x: camera.x + velocity.x * step, y: camera.y + velocity.y * step), visible: visible)
            points.append(camera)
        }
        return Track(start: segment.start, end: segment.end, points: points)
    }

    /// Keeps the zoomed-in view inside the frame.
    private static func clamp(_ point: CGPoint, visible: Double) -> CGPoint {
        let half = visible / 2
        return CGPoint(x: min(max(point.x, half), 1 - half), y: min(max(point.y, half), 1 - half))
    }

}
