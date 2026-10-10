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

    /// `smoothing` runs from 0 (the recorded path as is) to 1 (the smoothest).
    init(track: CursorTrack, smoothing: Double = 0) {
        self.init(track: track, sigma: smoothing * 0.2, anchoredToClicks: true)
    }

    /// `sigma` is the blur's width in seconds.
    private init(track: CursorTrack, sigma: Double, anchoredToClicks: Bool) {
        let raw = Self.resample(track)
        points = Self.smooth(raw, sigma: sigma, clicks: anchoredToClicks ? track.clicks : [])
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

    /// Averages each position with its neighbours in time (a Gaussian blur `sigma` seconds wide),
    /// which takes out jitter and small wobbles. Around each of `clicks` the path eases back to the
    /// recorded one, so they still land exactly where they happened.
    private static func smooth(_ raw: [CGPoint], sigma: Double, clicks: [CursorTrack.Click]) -> [CGPoint] {
        let sigma = sigma * rate
        guard sigma >= 0.5, raw.count > 1 else { return raw }

        let radius = Int((sigma * 3).rounded(.up))
        let kernel = (-radius...radius).map { exp(-0.5 * pow(Double($0) / sigma, 2)) }
        let kernelTotal = kernel.reduce(0, +)

        var smoothed = [CGPoint](repeating: .zero, count: raw.count)
        for index in raw.indices {
            var x = 0.0
            var y = 0.0
            for (offset, weight) in kernel.enumerated() {
                let neighbour = raw[min(max(index + offset - radius, 0), raw.count - 1)]
                x += neighbour.x * weight
                y += neighbour.y * weight
            }
            smoothed[index] = CGPoint(x: x / kernelTotal, y: y / kernelTotal)
        }

        let ease = 0.15 * rate
        for click in clicks {
            let start = click.t * rate
            let end = (click.t + click.duration) * rate
            let from = max(Int(start - 3 * ease), 0)
            let to = min(Int(end + 3 * ease) + 1, raw.count - 1)
            guard from <= to else { continue }

            for index in from...to {
                let position = Double(index)
                let distance = position < start ? start - position : max(position - end, 0)
                let weight = exp(-0.5 * pow(distance / ease, 2))
                smoothed[index] = mix(smoothed[index], raw[index], weight)
            }
        }
        return smoothed
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ fraction: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }
}
