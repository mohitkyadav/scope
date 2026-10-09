//
//  ScopeProject.swift
//  Scope
//

import Foundation

/// A recording saved as a `.scope` package: a folder that Finder shows as a single file,
/// holding the video, audio and cursor data together.
nonisolated struct ScopeProject: Hashable, Sendable {
    static let fileExtension = "scope"

    let url: URL

    /// Screen video, with system audio and microphone as separate audio tracks.
    var videoURL: URL { url.appending(path: "screen.mp4") }
    var cursorURL: URL { url.appending(path: "cursor.json") }
    /// Camera video, if a camera was recorded, and how it lines up with the screen video.
    var webcamURL: URL { url.appending(path: "webcam.mov") }
    var webcamInfoURL: URL { url.appending(path: "webcam.json") }
    /// Edits made in the editor.
    var projectFileURL: URL { url.appending(path: "project.json") }
    /// Imported audio files.
    var audioFolderURL: URL { url.appending(path: "audio", directoryHint: .isDirectory) }

    var name: String { url.deletingPathExtension().lastPathComponent }

    func createFolder() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }
}
