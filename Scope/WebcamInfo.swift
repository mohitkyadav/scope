//
//  WebcamInfo.swift
//  Scope
//

import Foundation

/// How a project's webcam video lines up with its screen video, saved as `webcam.json`.
nonisolated struct WebcamInfo: Codable, Sendable {
    var version = 1
    /// Seconds into the screen video at which the webcam video starts. Negative if the webcam started first.
    var offset: Double

    static func read(from url: URL) throws -> WebcamInfo {
        try JSONDecoder().decode(WebcamInfo.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
