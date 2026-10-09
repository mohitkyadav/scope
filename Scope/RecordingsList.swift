//
//  RecordingsList.swift
//  Scope
//

import AVFoundation
import SwiftUI

struct RecordingsList: View {
    let library: RecordingLibrary
    @State private var selection = Set<Recording.ID>()
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
            }
        } primaryAction: { urls in
            openEditors(urls)
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
