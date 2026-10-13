//
//  CursorShapeRecorder.swift
//  Scope
//

import AppKit
import CryptoKit

/// Notes which cursor is showing 20 times a second while recording, e.g. the arrow, a pointing hand
/// or a text cursor, whichever app set it. AppKit only hands out the cursor on the main thread.
final class CursorShapeRecorder {
    struct Result {
        var shapes: [CursorTrack.Shape]
        var changes: [CursorTrack.ShapeChange]
        /// Each shape's image as a PNG, by `CursorTrack.Shape.id`.
        var images: [String: Data]
    }

    private var timer: Timer?
    private var shapes: [String: CursorTrack.Shape] = [:]
    private var images: [String: Data] = [:]
    /// Times are `systemUptime` values until `stop` shifts them.
    private var changes: [CursorTrack.ShapeChange] = []

    func start() {
        sample()
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        // Keep sampling while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops sampling and returns what was seen, with times measured from `videoStart`
    /// (a `ProcessInfo.systemUptime` value).
    func stop(videoStart: TimeInterval) -> Result {
        timer?.invalidate()
        timer = nil

        var shifted = changes
            .filter { $0.t >= videoStart }
            .map { CursorTrack.ShapeChange(t: $0.t - videoStart, shape: $0.shape) }
        // The shape before the video started is the one it starts with.
        if let before = changes.last(where: { $0.t < videoStart }), shifted.first?.t != 0 {
            shifted.insert(CursorTrack.ShapeChange(t: 0, shape: before.shape), at: 0)
        }
        let used = Set(shifted.map(\.shape))
        return Result(
            shapes: shapes.values.filter { used.contains($0.id) }.sorted { $0.id < $1.id },
            changes: shifted,
            images: images.filter { used.contains($0.key) }
        )
    }

    private func sample() {
        guard let cursor = NSCursor.currentSystem, let id = Self.identifier(of: cursor) else { return }
        if shapes[id] == nil {
            guard let png = CursorSprite.bitmap(of: cursor.image)?.representation(using: .png, properties: [:]) else { return }
            images[id] = png
            shapes[id] = CursorTrack.Shape(
                id: id,
                width: cursor.image.size.width,
                height: cursor.image.size.height,
                hotX: cursor.hotSpot.x,
                hotY: cursor.hotSpot.y
            )
        }
        if changes.last?.shape != id {
            changes.append(CursorTrack.ShapeChange(t: ProcessInfo.processInfo.systemUptime, shape: id))
        }
    }

    /// Tells cursors apart cheaply: a hash of the click point and the smallest of the cursor's images.
    private static func identifier(of cursor: NSCursor) -> String? {
        let bitmaps = cursor.image.representations.compactMap { $0 as? NSBitmapImageRep }
        guard let smallest = bitmaps.min(by: { $0.pixelsWide < $1.pixelsWide }), let pixels = smallest.bitmapData else { return nil }
        var hash = SHA256()
        hash.update(data: Data(bytes: pixels, count: smallest.bytesPerRow * smallest.pixelsHigh))
        hash.update(data: Data("\(cursor.hotSpot.x),\(cursor.hotSpot.y)".utf8))
        return hash.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
