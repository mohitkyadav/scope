//
//  RecordingLibrary.swift
//  Scope
//

import AppKit
import AVFoundation
import Observation

struct Recording: Identifiable, Hashable {
    let project: ScopeProject
    /// When it was recorded.
    let date: Date
    /// When it was recorded or last edited, whichever is later.
    let lastEdited: Date
    let duration: TimeInterval?

    var id: URL { project.url }

    /// Whether it's been changed in the editor since it was recorded.
    var isEdited: Bool { lastEdited > date.addingTimeInterval(60) }

    /// The name it was given, or else when it was recorded, e.g. "Today at 18:54".
    var title: String {
        project.hasRecordedName ? date.recordingTitle : project.name
    }
}

extension Notification.Name {
    /// Posted with the project's URL as the object just before it's renamed, so an open editor can save first.
    static let projectWillRename = Notification.Name("ScopeProjectWillRename")
    /// Posted with the old URL as the object and the new one under `"url"` once a project is renamed.
    static let projectDidRename = Notification.Name("ScopeProjectDidRename")
}

enum RenameError: LocalizedError {
    case emptyName
    case nameTaken(String)

    var errorDescription: String? {
        switch self {
        case .emptyName: "Type a name for the project."
        case .nameTaken(let name): "There's already a project called “\(name)” in that folder."
        }
    }
}

@Observable
final class RecordingLibrary {
    private(set) var recordings: [Recording] = []

    /// Where projects are saved: Downloads, or the folder picked in Settings.
    static var folder: URL {
        ProjectFolder.shared.url
    }

    /// A new, not yet created project named after the current time, e.g. `Scope 2026-10-09 at 20.45.12.scope`.
    static func newProject() -> ScopeProject {
        let timestamp = Date.now.formatted(
            .verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) at \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
                      timeZone: .current, calendar: .current)
        )
        return ScopeProject(url: folder.appending(path: "Scope \(timestamp).\(ScopeProject.fileExtension)", directoryHint: .isDirectory))
    }

    func reload() async {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.folder,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []

        var loaded: [Recording] = []
        for url in urls where url.pathExtension == ScopeProject.fileExtension {
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            let project = ScopeProject(url: url)
            let duration = try? await AVURLAsset(url: project.videoURL).load(.duration).seconds
            let created = values?.creationDate ?? .distantPast
            let edited = (try? project.projectFileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            loaded.append(Recording(project: project, date: created, lastEdited: max(created, edited ?? created), duration: duration))
        }
        // Most recently worked on first.
        recordings = loaded.sorted { $0.lastEdited > $1.lastEdited }
    }

    /// Plays each project's raw video in the default player, e.g. QuickTime.
    func playVideo(_ projectURLs: some Collection<URL>) {
        for url in projectURLs {
            NSWorkspace.shared.open(ScopeProject(url: url).videoURL)
        }
    }

    /// Moves projects to the Trash, where they can still be restored, and refreshes the list.
    func moveToTrash(_ projectURLs: some Collection<URL>) async throws {
        for url in projectURLs {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            RecentProjects.shared.remove(url)
        }
        await reload()
    }

    /// Renames a project's package on disk, telling any editor that has it open, and returns it
    /// at its new place.
    static func rename(_ project: ScopeProject, to typed: String) throws -> ScopeProject {
        guard let name = ScopeProject.fileName(from: typed) else { throw RenameError.emptyName }
        let url = project.url.deletingLastPathComponent().appending(path: "\(name).\(ScopeProject.fileExtension)", directoryHint: .isDirectory)
        guard url.lastPathComponent != project.url.lastPathComponent else { return project }

        // Only a change of case can find itself here: the disk ignores case, so it's the same file.
        let isSameFile = url.path.lowercased() == project.url.path.lowercased()
        if !isSameFile, FileManager.default.fileExists(atPath: url.path) {
            throw RenameError.nameTaken(name)
        }

        NotificationCenter.default.post(name: .projectWillRename, object: project.url)
        if isSameFile {
            // A change of case only: go through another name, or the move does nothing.
            let step = url.deletingLastPathComponent().appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.moveItem(at: project.url, to: step)
            do {
                try FileManager.default.moveItem(at: step, to: url)
            } catch {
                try? FileManager.default.moveItem(at: step, to: project.url)
                throw error
            }
        } else {
            try FileManager.default.moveItem(at: project.url, to: url)
        }
        RecentProjects.shared.replace(project.url, with: url)
        NotificationCenter.default.post(name: .projectDidRename, object: project.url, userInfo: ["url": url])
        return ScopeProject(url: url)
    }

    func showInFinder(_ urls: some Collection<URL>) {
        NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
    }
}
