//
//  RecordingsList.swift
//  Scope
//

import AVFoundation
import SwiftUI

struct RecordingsList: View {
    let library: RecordingLibrary
    @State private var selection = Set<Recording.ID>()
    /// Projects waiting for the user to confirm moving them to the Trash.
    @State private var projectsToTrash: Set<URL> = []
    @State private var trashError: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List(library.recordings, selection: $selection) { recording in
            RecordingRow(recording: recording) {
                library.showInFinder([recording.project.url])
            }
        }
        .contextMenu(forSelectionType: Recording.ID.self) { urls in
            if !urls.isEmpty {
                Button("Open in Editor") { openEditors(urls) }
                Button("Play Video") { library.playVideo(urls) }
                Divider()
                Button("Show in Finder") { library.showInFinder(urls) }
                Divider()
                Button("Move to Trash…", role: .destructive) { projectsToTrash = urls }
            }
        } primaryAction: { urls in
            openEditors(urls)
        }
        .onDeleteCommand {
            projectsToTrash = selection
        }
        .confirmationDialog(
            trashTitle,
            isPresented: Binding(get: { !projectsToTrash.isEmpty }, set: { if !$0 { projectsToTrash = [] } })
        ) {
            Button("Move to Trash", role: .destructive) {
                let urls = projectsToTrash
                projectsToTrash = []
                selection.subtract(urls)
                Task {
                    do {
                        try await library.moveToTrash(urls)
                    } catch {
                        trashError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("You can put it back from the Trash in Finder.")
        }
        .alert("Couldn't Move to Trash", isPresented: Binding(get: { trashError != nil }, set: { if !$0 { trashError = nil } })) {
            Button("OK") {}
        } message: {
            Text(trashError ?? "")
        }
    }

    private var trashTitle: String {
        guard projectsToTrash.count == 1, let url = projectsToTrash.first else {
            return "Move \(projectsToTrash.count) projects to the Trash?"
        }
        let recording = library.recordings.first { $0.id == url }
        let name = recording.map { $0.date.formatted(date: .abbreviated, time: .shortened) } ?? url.deletingPathExtension().lastPathComponent
        return "Move the recording from \(name) to the Trash?"
    }
}

extension RecordingsList {
    private func openEditors(_ projectURLs: Set<URL>) {
        for url in projectURLs {
            openWindow(id: EditorView.windowID, value: url)
        }
    }
}

private struct RecordingRow: View {
    let recording: Recording
    let showInFinder: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 45)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                HStack(spacing: 4) {
                    Text(recording.duration?.clockString ?? "–")
                        .monospacedDigit()
                    if recording.lastEdited > recording.date.addingTimeInterval(60) {
                        Text("·")
                        Text("Edited \(recording.lastEdited, format: .relative(presentation: .named))")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: showInFinder) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
        .padding(.vertical, 4)
        .task(id: recording.id) {
            thumbnail = await Self.thumbnail(of: recording.project.videoURL)
        }
    }

    /// A small frame from early in the recording.
    private nonisolated static func thumbnail(of url: URL) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.maximumSize = CGSize(width: 240, height: 135)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
}
