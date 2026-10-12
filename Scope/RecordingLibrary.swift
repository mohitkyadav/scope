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

    /// "Today at 18:54", "Yesterday at 22:01", or "9 October at 18:54".
    var title: String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today at \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday at \(time)" }
        return "\(date.formatted(.dateTime.day().month(.wide))) at \(time)"
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

    func showInFinder(_ urls: some Collection<URL>) {
        NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
    }
}
