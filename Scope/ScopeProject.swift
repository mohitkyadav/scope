//
//  ScopeProject.swift
//  Scope
//

import Foundation

/// A recording saved as a `.scope` package: a folder that Finder shows as a single file,
/// holding the video, audio and cursor data together.
struct ScopeProject: Hashable {
    static let fileExtension = "scope"

    let url: URL

    /// Screen video, with system audio and microphone as separate audio tracks.
    var videoURL: URL { url.appending(path: "screen.mp4") }
    var cursorURL: URL { url.appending(path: "cursor.json") }

    var name: String { url.deletingPathExtension().lastPathComponent }

    func createFolder() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }
}
