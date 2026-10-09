//
//  RecordingsList.swift
//  Scope
//

import SwiftUI

struct RecordingsList: View {
    let library: RecordingLibrary
    @State private var selection = Set<Recording.ID>()

    var body: some View {
        List(library.recordings, selection: $selection) { recording in
            RecordingRow(recording: recording) {
                library.showInFinder([recording.url])
            }
        }
        .contextMenu(forSelectionType: Recording.ID.self) { urls in
            if !urls.isEmpty {
                Button("Open") { library.open(urls) }
                Button("Show in Finder") { library.showInFinder(urls) }
            }
        } primaryAction: { urls in
            library.open(urls)
        }
    }
}

private struct RecordingRow: View {
    let recording: Recording
    let showInFinder: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                Text(recording.duration?.clockString ?? "–")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button(action: showInFinder) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
        .padding(.vertical, 4)
    }
}
