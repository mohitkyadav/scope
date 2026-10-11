//
//  BackgroundLibrary.swift
//  Scope
//

import AppKit
import CryptoKit
import ImageIO
import Observation

/// Every image that's been used as a background, kept in Application Support so any project can
/// pick it again. Projects still get their own copy, so they keep opening if an image is removed here.
@Observable
final class BackgroundLibrary {
    static let shared = BackgroundLibrary()

    nonisolated struct Item: Identifiable {
        /// A hash of the image's contents, so the same image is only kept once.
        let id: String
        let url: URL
        let thumbnail: NSImage
        let added: Date
    }

    /// Newest first.
    private(set) var items: [Item] = []

    private nonisolated static let folder = URL.applicationSupportDirectory.appending(path: "Backgrounds", directoryHint: .isDirectory)
    private var loading: Task<Void, Never>?

    /// Reads the library, then adds the images of projects made before it existed. Only runs once.
    func load() async {
        if loading == nil {
            loading = Task {
                let files = await Task.detached(operation: { Self.readFolder() }).value
                items = files.sorted { $0.added > $1.added }
                let projects = RecordingLibrary.folder
                for url in await Task.detached(operation: { Self.imagesInPastProjects(in: projects) }).value {
                    _ = await add(from: url)
                }
            }
        }
        await loading?.value
    }

    /// Copies an image into the library, or finds it if it's already there. `nil` if it isn't an image.
    func add(from url: URL) async -> Item? {
        guard let item = await Task.detached(operation: { Self.copyIn(url) }).value else { return nil }
        if let existing = items.first(where: { $0.id == item.id }) {
            return existing
        }
        items.insert(item, at: 0)
        return item
    }

    /// Takes an image out of the library. Projects using it keep their own copy.
    func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: item.url)
        items.removeAll { $0.id == item.id }
    }

    // MARK: - Files

    nonisolated static func identifier(of data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func readFolder() -> [Item] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        return urls.compactMap { url in
            guard let thumbnail = thumbnail(of: url) else { return nil }
            let added = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return Item(id: url.deletingPathExtension().lastPathComponent, url: url, thumbnail: thumbnail, added: added)
        }
    }

    private nonisolated static func copyIn(_ url: URL) -> Item? {
        guard let data = try? Data(contentsOf: url), let thumbnail = thumbnail(of: url) else { return nil }
        let id = identifier(of: data)
        let destination = folder.appending(path: "\(id).\(url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased())")
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard (try? data.write(to: destination)) != nil else { return nil }
        }
        return Item(id: id, url: destination, thumbnail: thumbnail, added: .now)
    }

    private nonisolated static func thumbnail(of url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 160,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// The image backgrounds of the projects in a folder, oldest project first.
    private nonisolated static func imagesInPastProjects(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        return urls
            .filter { $0.pathExtension == ScopeProject.fileExtension }
            .sorted { url, other in
                let date = { (url: URL) in (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast }
                return date(url) < date(other)
            }
            .compactMap { url in
                let project = ScopeProject(url: url)
                guard let file = try? ProjectFile.read(from: project.projectFileURL),
                      let fileName = file.settings.backgroundImageFileName
                else { return nil }
                return project.fileURL(fileName)
            }
    }
}
