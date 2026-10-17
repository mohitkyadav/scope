//
//  CursorIdle.swift
//  Scope
//

import Foundation

/// How much of the cursor shows at any moment when it fades out while standing still: it goes
/// once it's been still for `delay` seconds and comes back as soon as it moves or clicks.
/// Worked out once on a 60 Hz grid, in recording time.
nonisolated struct CursorIdle: Sendable {
    private static let rate = 60.0
    private static let fadeOut = 0.4
    private static let fadeIn = 0.12
    /// Moves smaller than this, as a fraction of the recorded area, are a hand resting on the mouse.
    private static let stillness = 0.001

    let delay: Double
    private let visibility: [Float]

    init(track: CursorTrack, delay: Double) {
        self.delay = delay

        // Moments the cursor moved or a button went down or up.
        var activity: [Double] = []
        var anchor: CursorTrack.Sample?
        for sample in track.samples {
            if let anchor, abs(sample.x - anchor.x) < Self.stillness, abs(sample.y - anchor.y) < Self.stillness {
                continue
            }
            anchor = sample
            activity.append(sample.t)
        }
        activity += track.clicks.flatMap { [$0.t, $0.t + $0.duration] }
        activity.sort()
        let presses = track.clicks.sorted { $0.t < $1.t }

        let end = max(activity.last ?? 0, track.samples.last?.t ?? 0) + delay + Self.fadeOut + 1
        let count = Int((end * Self.rate).rounded(.up)) + 1
        var values: [Float] = []
        values.reserveCapacity(count)
        var lastActive = 0.0
        var activityIndex = 0
        var shown = 1.0
        for step in 0..<count {
            let time = Double(step) / Self.rate
            while activityIndex < activity.count, activity[activityIndex] <= time {
                lastActive = activity[activityIndex]
                activityIndex += 1
            }
            // Holding a button down, e.g. to drag, counts as using the cursor.
            let isPressed = presses.contains { time >= $0.t && time <= $0.t + $0.duration }
            let target = isPressed || time - lastActive < delay ? 1.0 : 0.0
            if target > shown {
                shown = min(shown + 1 / (Self.fadeIn * Self.rate), 1)
            } else if target < shown {
                shown = max(shown - 1 / (Self.fadeOut * Self.rate), 0)
            }
            values.append(Float(shown))
        }
        visibility = values
    }

    /// From 0 (hidden) to 1 (fully showing), eased so it doesn't fade at a constant rate.
    func visibility(at time: Double) -> Double {
        guard let last = visibility.indices.last else { return 1 }
        let index = min(max(Int((time * Self.rate).rounded()), 0), last)
        let shown = Double(visibility[index])
        return shown * shown * (3 - 2 * shown)
    }
}
