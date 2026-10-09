//
//  ProjectFile.swift
//  Scope
//

import Foundation

/// The editor's changes to a project, saved as `project.json` in the project package.
nonisolated struct ProjectFile: Codable, Sendable {
    var version = 1
    var settings = EditorSettings()
    /// `nil` until the timeline is first edited; the editor then starts from the untouched recording.
    var edits: TimelineEdits?

    static func read(from url: URL) throws -> ProjectFile {
        try JSONDecoder().decode(ProjectFile.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
