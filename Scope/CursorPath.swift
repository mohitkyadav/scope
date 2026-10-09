//
//  CursorPath.swift
//  Scope
//

import CoreGraphics

/// The cursor's position at any moment of a recording, resampled from the recorded track
/// onto an even 120 Hz grid so it can be looked up quickly for every video frame.
nonisolated struct CursorPath: Sendable {
    static let rate: Double = 120

    /// Positions as fractions of the recorded area, one per 1/120 s.
    private let points: [CGPoint]
    let clicks: [CursorTrack.Click]

    init(track: CursorTrack) {
        points = Self.resample(track)
        clicks = track.clicks
    }

    /// Where the cursor was at `time`, or `nil` if nothing was recorded.
    func position(at time: Double) -> CGPoint? {
        guard let last = points.indices.last else { return nil }
        let index = time * Self.rate
        let lower = min(max(Int(index), 0), last)
        let upper = min(lower + 1, last)
        let fraction = min(max(index - Double(lower), 0), 1)
        return Self.mix(points[lower], points[upper], fraction)
    }

    func isPressed(at time: Double) -> Bool {
        clicks.contains { time >= $0.t && time <= $0.t + $0.duration }
    }

    private static func resample(_ track: CursorTrack) -> [CGPoint] {
        let samples = track.samples
        guard !samples.isEmpty else { return [] }

        let end = max(samples.last?.t ?? 0, track.clicks.map { $0.t + $0.duration }.max() ?? 0)
        let count = Int((end * rate).rounded(.up)) + 1

        var points: [CGPoint] = []
        points.reserveCapacity(count)
        var index = 0
        for step in 0..<count {
            let time = Double(step) / rate
            while index + 1 < samples.count, samples[index + 1].t <= time {
                index += 1
            }

            let a = samples[index]
            var point = CGPoint(x: a.x, y: a.y)
            // Samples are only saved when the cursor moves. Close samples mean it was moving, so
            // glide between them; after a longer gap it was standing still, so hold the position.
            if index + 1 < samples.count {
                let b = samples[index + 1]
                if b.t - a.t < 0.05, time >= a.t {
                    point = mix(point, CGPoint(x: b.x, y: b.y), (time - a.t) / (b.t - a.t))
                }
            }
            points.append(point)
        }
        return points
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ fraction: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }
}
