//
//  CursorTrack.swift
//  Scope
//

import Foundation

/// Cursor movement and clicks during a recording, saved next to the video as JSON.
///
/// Times are seconds from the start of the video. Positions are fractions of the recorded
/// area, from (0, 0) at the top left to (1, 1) at the bottom right, and fall outside 0...1
/// when the cursor leaves the area.
nonisolated struct CursorTrack: Codable, Sendable {
    nonisolated struct Sample: Codable, Sendable {
        var t: Double
        var x: Double
        var y: Double
    }

    nonisolated enum Button: String, Codable, Sendable {
        case left, right, other
    }

    nonisolated struct Click: Codable, Sendable {
        /// When the button went down.
        var t: Double
        /// How long the button was held.
        var duration: Double
        var x: Double
        var y: Double
        var button: Button
    }

    /// A look the cursor had, like the arrow, a pointing hand or a text cursor. Its image is saved
    /// in the project's `cursors` folder as `<id>.png`.
    nonisolated struct Shape: Codable, Sendable {
        var id: String
        /// Size of the cursor in points.
        var width: Double
        var height: Double
        /// The click point, in points from the top left.
        var hotX: Double
        var hotY: Double
    }

    /// When the cursor took on a shape.
    nonisolated struct ShapeChange: Codable, Sendable {
        var t: Double
        var shape: String
    }

    var version = 1
    /// Size of the recorded area in points when recording started.
    var areaWidth: Double
    var areaHeight: Double
    /// One sample each time the cursor moved.
    var samples: [Sample]
    var clicks: [Click]
    /// The cursor's shapes and when it changed between them. `nil` in projects recorded before
    /// Scope followed the cursor's shape, which show the arrow throughout.
    var shapes: [Shape]?
    var shapeChanges: [ShapeChange]?

    static func read(from url: URL) throws -> CursorTrack {
        try JSONDecoder().decode(CursorTrack.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
