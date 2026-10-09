//
//  CursorRecorder.swift
//  Scope
//

import AppKit

/// The part of the screen being recorded, so cursor positions can be stored relative to it.
nonisolated enum CaptureArea: Sendable {
    case display(CGDirectDisplayID)
    case window(CGWindowID)

    /// Current bounds in global screen points with a top-left origin, or `nil` if it's gone.
    var bounds: CGRect? {
        switch self {
        case .display(let displayID):
            return CGDisplayBounds(displayID)
        case .window(let windowID):
            guard let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
                  let bounds = info.first?[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
    }
}

/// Samples the cursor position and mouse buttons 120 times a second while recording.
///
/// Polling needs no extra permission, unlike a global event monitor. All state lives on
/// `queue`, so the timer never waits on the main thread.
nonisolated final class CursorRecorder: @unchecked Sendable {
    private let area: CaptureArea
    private let queue = DispatchQueue(label: "Scope.CursorRecorder", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    private var startBounds: CGRect?
    private var bounds: CGRect?
    private var boundsCheckedAt: TimeInterval = 0
    private var samples: [CursorTrack.Sample] = []
    private var clicks: [CursorTrack.Click] = []
    private var pressedButtons = 0
    private var presses: [Int: CursorTrack.Click] = [:]

    init(area: CaptureArea) {
        self.area = area
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / 120), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        queue.sync { self.timer = timer }
    }

    /// Stops sampling and returns the track, with times measured from `videoStart`
    /// (a `ProcessInfo.systemUptime` value).
    func stop(videoStart: TimeInterval) -> CursorTrack {
        queue.sync {
            timer?.cancel()
            timer = nil

            // Buttons still held when recording stopped count as released now.
            let now = ProcessInfo.processInfo.systemUptime
            for var click in presses.values {
                click.duration = now - click.t
                clicks.append(click)
            }
            presses = [:]

            return CursorTrack(
                areaWidth: startBounds.map { Double($0.width) } ?? 0,
                areaHeight: startBounds.map { Double($0.height) } ?? 0,
                samples: Self.shift(samples, to: videoStart),
                clicks: clicks
                    .filter { $0.t >= videoStart }
                    .map { CursorTrack.Click(t: $0.t - videoStart, duration: $0.duration, x: $0.x, y: $0.y, button: $0.button) }
                    .sorted { $0.t < $1.t }
            )
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime

        // Windows can move, so look their bounds up again ten times a second.
        if bounds == nil || now - boundsCheckedAt > 0.1 {
            bounds = area.bounds ?? bounds
            boundsCheckedAt = now
            if startBounds == nil {
                startBounds = bounds
            }
        }
        guard let bounds, bounds.width > 0, bounds.height > 0,
              let location = CGEvent(source: nil)?.location
        else { return }

        let x = (location.x - bounds.minX) / bounds.width
        let y = (location.y - bounds.minY) / bounds.height

        if samples.last.map({ $0.x != x || $0.y != y }) ?? true {
            samples.append(CursorTrack.Sample(t: now, x: x, y: y))
        }

        let buttons = NSEvent.pressedMouseButtons
        let changed = buttons ^ pressedButtons
        for index in 0..<5 where changed & (1 << index) != 0 {
            if buttons & (1 << index) != 0 {
                presses[index] = CursorTrack.Click(t: now, duration: 0, x: x, y: y, button: Self.button(index))
            } else if var click = presses.removeValue(forKey: index) {
                click.duration = now - click.t
                clicks.append(click)
            }
        }
        pressedButtons = buttons
    }

    /// Moves sample times so the video's first frame is 0. The last position before the video
    /// started is kept at 0, so the cursor's starting point is known.
    private static func shift(_ samples: [CursorTrack.Sample], to videoStart: TimeInterval) -> [CursorTrack.Sample] {
        var shifted = samples
            .filter { $0.t >= videoStart }
            .map { CursorTrack.Sample(t: $0.t - videoStart, x: $0.x, y: $0.y) }

        if let before = samples.last(where: { $0.t < videoStart }), shifted.first?.t != 0 {
            shifted.insert(CursorTrack.Sample(t: 0, x: before.x, y: before.y), at: 0)
        }
        return shifted
    }

    private static func button(_ index: Int) -> CursorTrack.Button {
        switch index {
        case 0: .left
        case 1: .right
        default: .other
        }
    }
}
