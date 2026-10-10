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
/// Nothing outside a segment affects it, and outside segments the view isn't zoomed at all.
nonisolated struct ZoomCamera: Sendable {
    private static let rate = 60.0
    /// The cursor can move this far from the centre, as a fraction of the zoomed-in view, before the camera follows.
    private static let deadZone = 0.25
    /// Roughly how long the camera takes to catch up, in seconds.
    private static let followTime = 0.45
    /// A click this soon after a zoom starts is what the zoom is about, so it starts there.
    private static let startClickWindow = 1.5

    private struct Track: Sendable {
        let start: Double
        let end: Double
        /// Focus points as fractions of the frame, one per 1/60 s from `start`.
        let points: [CGPoint]
    }

    private let tracks: [Track]

    /// `cursor` and `clicks` are in recording time, like the segments. Segments without their own
    /// level use `defaultLevel`.
    init(segments: [ZoomSegment], cursor: CursorPath?, clicks: [CursorTrack.Click], defaultLevel: Double) {
        tracks = segments.map { segment in
            let visible = 1 / max(segment.level ?? defaultLevel, 1)
            return Self.track(for: segment, cursor: cursor, clicks: clicks, visible: visible)
        }
    }

    /// The point the view is centred on at `time`, as fractions of the frame, or `nil` outside every segment.
    func focus(at time: Double) -> CGPoint? {
        guard let track = tracks.first(where: { time >= $0.start && time <= $0.end }), !track.points.isEmpty else { return nil }
        let index = min(max(Int(((time - track.start) * Self.rate).rounded()), 0), track.points.count - 1)
        return track.points[index]
    }

    private static func track(for segment: ZoomSegment, cursor: CursorPath?, clicks: [CursorTrack.Click], visible: Double) -> Track {
        func cursorPosition(at time: Double) -> CGPoint {
            cursor?.position(at: time) ?? CGPoint(x: 0.5, y: 0.5)
        }
        let firstClick = clicks.first {
            $0.t >= segment.start && $0.t <= min(segment.start + startClickWindow, segment.end)
                && (0...1).contains($0.x) && (0...1).contains($0.y)
        }
        var camera = clamp(firstClick.map { CGPoint(x: $0.x, y: $0.y) } ?? cursorPosition(at: segment.start), visible: visible)
        var easedTarget = camera
        // A zoom that doesn't follow the cursor stays where it started.
        let follows = segment.followsCursor ?? true

        let step = 1 / rate
        // Two gentle smoothing stages, so the camera eases into a move instead of jolting.
        let follow = 1 - exp(-step / (followTime / 2))
        let count = max(Int(((segment.end - segment.start) * rate).rounded(.up)), 0) + 1
        var points: [CGPoint] = []
        points.reserveCapacity(count)

        for index in 0..<count {
            guard follows else {
                points.append(camera)
                continue
            }
            let time = segment.start + Double(index) * step
            let cursor = cursorPosition(at: time)
            var target = easedTarget
            let reach = visible * deadZone
            if cursor.x - target.x > reach { target.x = cursor.x - reach }
            if target.x - cursor.x > reach { target.x = cursor.x + reach }
            if cursor.y - target.y > reach { target.y = cursor.y - reach }
            if target.y - cursor.y > reach { target.y = cursor.y + reach }

            easedTarget = clamp(mix(easedTarget, target, follow), visible: visible)
            camera = clamp(mix(camera, easedTarget, follow), visible: visible)
            points.append(camera)
        }
        return Track(start: segment.start, end: segment.end, points: points)
    }

    /// Keeps the zoomed-in view inside the frame.
    private static func clamp(_ point: CGPoint, visible: Double) -> CGPoint {
        let half = visible / 2
        return CGPoint(x: min(max(point.x, half), 1 - half), y: min(max(point.y, half), 1 - half))
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ amount: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount)
    }
}
