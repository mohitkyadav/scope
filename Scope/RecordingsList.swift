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
    /// The project being renamed, and the name being typed for it.
    @State private var projectToRename: ScopeProject?
    @State private var newName = ""
    @State private var renameError: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Newest recording first.
        List(library.recordings.sorted { $0.date > $1.date }, selection: $selection) { recording in
            RecordingRow(
                recording: recording,
                showInFinder: { library.showInFinder([recording.project.url]) },
                open: { openEditors([recording.id]) },
                playVideo: { library.playVideo([recording.id]) },
                rename: { startRenaming(recording.project) },
                moveToTrash: { projectsToTrash = [recording.id] }
            )
            .listRowSeparator(.hidden)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: Recording.ID.self) { urls in
            if !urls.isEmpty {
                Button("Open in Editor") { openEditors(urls) }
                Button("Play Video") { library.playVideo(urls) }
                Divider()
                if urls.count == 1, let url = urls.first {
                    Button("Rename…") { startRenaming(ScopeProject(url: url)) }
                }
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
        .alert("Rename Project", isPresented: Binding(get: { projectToRename != nil }, set: { if !$0 { projectToRename = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { rename() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The project is renamed in Finder too.")
        }
        .alert("Couldn't Rename the Project", isPresented: Binding(get: { renameError != nil }, set: { if !$0 { renameError = nil } })) {
            Button("OK") {}
        } message: {
            Text(renameError ?? "")
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
        let project = ScopeProject(url: url)
        guard project.hasRecordedName else { return "Move “\(project.name)” to the Trash?" }
        let recording = library.recordings.first { $0.id == url }
        return "Move the recording from \(recording?.title ?? project.name) to the Trash?"
    }

    private func startRenaming(_ project: ScopeProject) {
        newName = project.name
        projectToRename = project
    }

    private func rename() {
        guard let project = projectToRename else { return }
        projectToRename = nil
        do {
            let renamed = try RecordingLibrary.rename(project, to: newName)
            if selection.remove(project.url) != nil {
                selection.insert(renamed.url)
            }
            Task { await library.reload() }
        } catch {
            renameError = error.localizedDescription
        }
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
    let rename: () -> Void
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
                Text(details)
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
                Button("Rename…", action: rename)
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

    /// "Edited 5 minutes ago", after when it was recorded if the title is a name.
    private var details: String {
        let edited = recording.isEdited ? "Edited \(recording.lastEdited.formatted(.relative(presentation: .named)))" : "Not edited yet"
        return recording.project.hasRecordedName ? edited : "\(recording.date.recordingTitle) · \(edited)"
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
