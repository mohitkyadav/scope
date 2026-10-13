//
//  RecentProjects.swift
//  Scope
//

import AppKit
import Observation
import UniformTypeIdentifiers

/// Projects opened in the editor, most recent first, for File › Open Recent.
@Observable
final class RecentProjects {
    static let shared = RecentProjects()
    private static let limit = 10
    private static let key = "recentProjects"

    private(set) var urls: [URL]

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        urls = paths.map { URL(fileURLWithPath: $0) }
    }

    /// Recent projects that still exist.
    var existing: [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ url: URL) {
        urls.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        urls.insert(url, at: 0)
        urls = Array(urls.prefix(Self.limit))
        save()
    }

    /// Keeps a renamed project in its place in the list.
    func replace(_ old: URL, with new: URL) {
        guard let index = urls.firstIndex(where: { $0.standardizedFileURL == old.standardizedFileURL }) else { return }
        urls[index] = new
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        save()
    }

    func clear() {
        urls = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(urls.map(\.path), forKey: Self.key)
    }

    /// Asks for a `.scope` project anywhere on disk.
    static func chooseProject() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ScopeProject.fileExtension) ?? .package]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = RecordingLibrary.folder
        panel.prompt = "Open"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
