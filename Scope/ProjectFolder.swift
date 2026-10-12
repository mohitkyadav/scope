//
//  ProjectFolder.swift
//  Scope
//

import AppKit
import Observation

/// Where new projects and exports are saved: Downloads, or a folder picked in Settings.
/// The sandbox only lets Scope into a picked folder through a security-scoped bookmark,
/// which is kept in the user defaults so the folder stays usable after relaunching.
@Observable
final class ProjectFolder {
    static let shared = ProjectFolder()
    private static let bookmarkKey = "projectFolderBookmark"
    private static let pathKey = "projectFolderPath"

    /// Inside the sandbox the Downloads folder is a link to the real one, so resolve it.
    static var downloads: URL {
        URL.downloadsDirectory.resolvingSymlinksInPath()
    }

    /// The folder in use.
    private(set) var url = ProjectFolder.downloads
    /// The folder picked in Settings, or `nil` for Downloads.
    private(set) var chosen: URL?
    /// The picked folder can't be found, e.g. it was deleted or its drive is unplugged, so Downloads is used.
    private(set) var isMissing = false

    private init() {
        resolve()
    }

    /// Looks for a missing folder again, e.g. after its drive is plugged back in.
    func refresh() {
        if isMissing {
            resolve()
        }
    }

    /// Asks for a folder and uses it. Picking Downloads goes back to it.
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.message = "Choose where Scope saves new recordings and exports."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let picked = panel.url?.resolvingSymlinksInPath() else { return }

        if picked == Self.downloads {
            useDownloads()
            return
        }
        guard let bookmark = try? picked.bookmarkData(options: .withSecurityScope) else { return }
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        UserDefaults.standard.set(picked.path, forKey: Self.pathKey)
        resolve()
    }

    func useDownloads() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Self.pathKey)
        resolve()
    }

    // Access to a previous folder is never given up, because an open editor or a running
    // recording may still be writing there. The sandbox takes it back when Scope quits.
    private func resolve() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            chosen = nil
            isMissing = false
            url = Self.downloads
            return
        }

        var isStale = false
        if let folder = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
           folder.startAccessingSecurityScopedResource() {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue {
                // The folder was moved or renamed, so save a fresh bookmark for it.
                if isStale, let fresh = try? folder.bookmarkData(options: .withSecurityScope) {
                    UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
                    UserDefaults.standard.set(folder.path, forKey: Self.pathKey)
                }
                chosen = folder
                isMissing = false
                url = folder
                return
            }
            folder.stopAccessingSecurityScopedResource()
        }

        let path = UserDefaults.standard.string(forKey: Self.pathKey)
        chosen = path.map { URL(fileURLWithPath: $0, isDirectory: true) }
        isMissing = true
        url = Self.downloads
    }
}
