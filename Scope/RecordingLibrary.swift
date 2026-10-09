//
//  RecordingLibrary.swift
//  Scope
//

import AppKit
import AVFoundation
import Observation

struct Recording: Identifiable, Hashable {
    let project: ScopeProject
    let date: Date
    let duration: TimeInterval?

    var id: URL { project.url }
}

@Observable
final class RecordingLibrary {
    private(set) var recordings: [Recording] = []

    /// Projects are saved straight into `~/Downloads`. Inside the sandbox the Downloads folder
    /// is a link to the real one, so resolve it.
    static var folder: URL {
        URL.downloadsDirectory.resolvingSymlinksInPath()
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
            loaded.append(Recording(project: project, date: values?.creationDate ?? .distantPast, duration: duration))
        }
        recordings = loaded.sorted { $0.date > $1.date }
    }

    /// Opens each project's video in the default player until Scope has its own editor.
    func open(_ projectURLs: some Collection<URL>) {
        for url in projectURLs {
            NSWorkspace.shared.open(ScopeProject(url: url).videoURL)
        }
    }

    func showInFinder(_ urls: some Collection<URL>) {
        NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
    }
}
