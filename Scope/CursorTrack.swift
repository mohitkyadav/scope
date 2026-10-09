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

    var version = 1
    /// Size of the recorded area in points when recording started.
    var areaWidth: Double
    var areaHeight: Double
    /// One sample each time the cursor moved.
    var samples: [Sample]
    var clicks: [Click]

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
