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
    /// Files copied into the project, like an image background.
    func fileURL(_ fileName: String) -> URL { url.appending(path: fileName) }
    /// Imported audio files.
    var audioFolderURL: URL { url.appending(path: "audio", directoryHint: .isDirectory) }

    var name: String { url.deletingPathExtension().lastPathComponent }

    /// Whether it still has the name it was recorded with, e.g. `Scope 2026-10-09 at 20.45.12`,
    /// rather than one it was given.
    var hasRecordedName: Bool {
        name.wholeMatch(of: /Scope \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}/) != nil
    }

    /// A typed name made safe for a file name: trimmed, with no slashes or colons, and no leading
    /// dot that would hide the file. `nil` if nothing's left.
    static func fileName(from typed: String) -> String? {
        var name = typed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") {
            name.removeFirst()
        }
        return name.isEmpty ? nil : name
    }

    func createFolder() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }
}
