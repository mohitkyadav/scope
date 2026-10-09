//
//  RecordingLibrary.swift
//  Scope
//

import AppKit
import AVFoundation
import Observation

struct Recording: Identifiable, Hashable {
    let url: URL
    let date: Date
    let duration: TimeInterval?

    var id: URL { url }
}

@Observable
final class RecordingLibrary {
    private(set) var recordings: [Recording] = []

    /// `~/Movies/Scope`. Inside the sandbox the Movies folder is a link to the real one, so resolve it.
    static var folder: URL {
        URL.moviesDirectory
            .resolvingSymlinksInPath()
            .appending(path: "Scope", directoryHint: .isDirectory)
    }

    static func newRecordingURL() throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let timestamp = Date.now.formatted(
            .verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) at \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
                      timeZone: .current, calendar: .current)
        )
        return folder.appending(path: "Scope \(timestamp).mp4")
    }

    func reload() async {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.folder,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )) ?? []

        var loaded: [Recording] = []
        for url in urls where url.pathExtension == "mp4" {
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let duration = try? await AVURLAsset(url: url).load(.duration).seconds
            loaded.append(Recording(url: url, date: date, duration: duration))
        }
        recordings = loaded.sorted { $0.date > $1.date }
    }

    func open(_ urls: some Collection<URL>) {
        for url in urls {
            NSWorkspace.shared.open(url)
        }
    }

    func showInFinder(_ urls: some Collection<URL>) {
        NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
    }
}
