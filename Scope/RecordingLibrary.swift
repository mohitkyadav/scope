//
//  RecordingLibrary.swift
//  Scope
//

import Foundation

enum RecordingLibrary {
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
}
