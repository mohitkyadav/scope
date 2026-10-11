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
        List(selection: $selection) {
            ForEach(Self.groups(library.recordings), id: \.title) { group in
                Section {
                    ForEach(group.recordings) { recording in
                        RecordingRow(
                            recording: recording,
                            showInFinder: { library.showInFinder([recording.project.url]) },
                            open: { openEditors([recording.id]) },
                            playVideo: { library.playVideo([recording.id]) },
                            moveToTrash: { projectsToTrash = [recording.id] }
                        )
                        .tag(recording.id)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.disabled)
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
        let name = recording?.title ?? url.deletingPathExtension().lastPathComponent
        return "Move the recording from \(name) to the Trash?"
    }

    /// Recordings grouped by the day they were made: Today, Yesterday, then Earlier, newest first.
    private static func groups(_ recordings: [Recording]) -> [(title: String, recordings: [Recording])] {
        let calendar = Calendar.current
        let sorted = recordings.sorted { $0.date > $1.date }
        let today = sorted.filter { calendar.isDateInToday($0.date) }
        let yesterday = sorted.filter { calendar.isDateInYesterday($0.date) }
        let earlier = sorted.filter { !calendar.isDateInToday($0.date) && !calendar.isDateInYesterday($0.date) }
        return [("Today", today), ("Yesterday", yesterday), ("Earlier", earlier)].filter { !$0.1.isEmpty }
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
    let open: () -> Void
    let playVideo: () -> Void
    let moveToTrash: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 14) {
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
            .frame(width: 96, height: 56)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if let duration = recording.duration {
                    Text(duration.clockString)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.6)))
                        .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(recording.title)
                    .font(.body.weight(.semibold))
                Text(recording.isEdited ? "Edited \(recording.lastEdited.formatted(.relative(presentation: .named)))" : "Not edited yet")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: showInFinder) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")

            Menu {
                Button("Open in Editor", action: open)
                Button("Play Video", action: playVideo)
                Divider()
                Button("Show in Finder", action: showInFinder)
                Divider()
                Button("Move to Trash…", role: .destructive, action: moveToTrash)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
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
