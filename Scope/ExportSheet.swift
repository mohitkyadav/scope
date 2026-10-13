//
//  ExportSheet.swift
//  Scope
//

import AppKit
import AVFoundation
import Observation
import SwiftUI

/// Runs one export at a time and reports how it's going.
@Observable
final class ExportController {
    enum State: Equatable {
        case ready
        case exporting(progress: Double)
        case finished(URL)
        case failed(String)
    }

    private(set) var state = State.ready
    private var task: Task<Void, Never>?

    var isExporting: Bool {
        if case .exporting = state { return true }
        return false
    }

    func start(_ export: @escaping @Sendable (_ progress: @escaping @Sendable (Double) -> Void) async throws -> Void, writingTo url: URL) {
        state = .exporting(progress: 0)
        task = Task {
            do {
                try await export { progress in
                    Task { @MainActor in
                        if case .exporting = self.state {
                            self.state = .exporting(progress: progress)
                        }
                    }
                }
                state = .finished(url)
            } catch is CancellationError {
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }
}

/// Export settings and progress, shown as a sheet on the editor.
struct ExportSheet: View {
    enum Format: Hashable {
        case movie, gif
    }

    let model: EditorModel
    @Environment(\.dismiss) private var dismiss

    @State private var format = Format.movie
    /// The exported file's name, without its extension. Starts as the project's name.
    @State private var fileName = ""
    @State private var height = 0
    @State private var frameRate = 60
    @State private var quality = ExportQuality.high
    @State private var gifStart = 0.0
    @State private var gifEnd = 0.0
    @State private var gifWidth = 640
    @State private var gifFrameRate = 15
    @State private var loopsCursor = true
    @State private var controller = ExportController()

    private var canvas: CGSize { model.canvasSize }
    private var duration: Double { model.duration }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export")
                .font(.title2.weight(.semibold))

            Picker("Format", selection: $format) {
                Text("MP4 Video").tag(Format.movie)
                Text("GIF").tag(Format.gif)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Form {
                TextField("Name", text: $fileName, prompt: Text(model.project.name))
                switch format {
                case .movie: movieSettings
                case .gif: gifSettings
                }
            }
            .formStyle(.grouped)
            .disabled(controller.isExporting)

            status

            HStack {
                Spacer()
                if controller.isExporting {
                    Button("Cancel Export", role: .cancel, action: controller.cancel)
                } else {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Export") { startExport() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(format == .gif && gifEnd - gifStart < 0.2)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: setDefaults)
    }

    // MARK: - Settings

    @ViewBuilder
    private var movieSettings: some View {
        Picker("Resolution", selection: $height) {
            ForEach(heights, id: \.self) { height in
                let size = Exporter.size(forHeight: height, canvas: canvas)
                Text(height == heights.first ? "Original (\(Int(size.width)) × \(Int(size.height)))" : "\(height)p (\(Int(size.width)) × \(Int(size.height)))")
                    .tag(height)
            }
        }
        Picker("Frame rate", selection: $frameRate) {
            Text("60 fps").tag(60)
            Text("30 fps").tag(30)
        }
        Picker("Quality", selection: $quality) {
            ForEach(ExportQuality.allCases) { quality in
                Text(quality.rawValue).tag(quality)
            }
        }
        LabeledContent("Length", value: duration.clockString)
        LabeledContent("Estimated size", value: estimatedMovieSize)
    }

    @ViewBuilder
    private var gifSettings: some View {
        LabeledSlider("Start", value: $gifStart, in: 0...max(duration, 0.1)) { $0.timecodeString }
            .onChange(of: gifStart) {
                gifEnd = max(gifEnd, min(gifStart + 0.2, duration))
            }
        LabeledSlider("End", value: $gifEnd, in: 0...max(duration, 0.1)) { $0.timecodeString }
            .onChange(of: gifEnd) {
                gifStart = min(gifStart, max(gifEnd - 0.2, 0))
            }
        Picker("Width", selection: $gifWidth) {
            ForEach([480, 640, 800, 1080], id: \.self) { width in
                Text("\(width) px").tag(width)
            }
        }
        Picker("Frame rate", selection: $gifFrameRate) {
            ForEach([10, 15, 20, 24], id: \.self) { rate in
                Text("\(rate) fps").tag(rate)
            }
        }
        Toggle("Loop cursor", isOn: $loopsCursor)
            .help("Ease the cursor back to where it started, so the loop doesn't jump")
        LabeledContent("Frames") {
            let frames = Int(((gifEnd - gifStart) * Double(gifFrameRate)).rounded(.up))
            Text(gifEnd - gifStart > 15 ? "\(frames) — long GIFs get large" : "\(frames)")
        }
    }

    /// The recording's own height, then common smaller ones.
    private var heights: [Int] {
        let original = Int(canvas.height)
        return [original] + [2160, 1440, 1080, 720].filter { $0 < original }
    }

    private var estimatedMovieSize: String {
        let options = MovieOptions(size: Exporter.size(forHeight: height, canvas: canvas), frameRate: frameRate, quality: quality)
        let bytes = (Double(options.bitRate) + 192_000) * duration / 8
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func setDefaults() {
        fileName = model.project.name
        height = Int(canvas.height)
        // A whole short video, or five seconds from the playhead of a longer one.
        if duration <= 10 {
            gifStart = 0
            gifEnd = duration
        } else {
            gifStart = min(model.currentTime, duration - 1)
            gifEnd = min(gifStart + 5, duration)
        }
    }

    // MARK: - Exporting

    @ViewBuilder
    private var status: some View {
        switch controller.state {
        case .ready:
            EmptyView()
        case .exporting(let progress):
            ProgressView(value: progress) {
                Text("Exporting… \(Int(progress * 100))%")
            }
        case .finished(let url):
            HStack {
                Label("Saved “\(url.lastPathComponent)” to \(FileManager.default.displayName(atPath: url.deletingLastPathComponent().path))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    /// The typed name as a file name, without an extension typed along with it, e.g. "Demo.mp4".
    private func exportName(fallback: String) -> String {
        var name = fileName.trimmingCharacters(in: .whitespaces)
        for fileExtension in [".mp4", ".gif"] where name.lowercased().hasSuffix(fileExtension) {
            name.removeLast(fileExtension.count)
        }
        return ScopeProject.fileName(from: name) ?? fallback
    }

    private func startExport() {
        Task {
            model.player.pause()
            guard let job = await model.exportJob() else { return }
            let folder = RecordingLibrary.folder
            let name = exportName(fallback: job.name)

            switch format {
            case .movie:
                let options = MovieOptions(size: Exporter.size(forHeight: height, canvas: canvas), frameRate: frameRate, quality: quality)
                let url = Exporter.availableURL(in: folder, name: name, fileExtension: "mp4")
                controller.start({ progress in
                    try await Exporter.exportMovie(job, options: options, to: url, progress: progress)
                }, writingTo: url)

            case .gif:
                let options = GIFOptions(start: gifStart, end: gifEnd, width: gifWidth, frameRate: gifFrameRate, loopsCursor: loopsCursor)
                let url = Exporter.availableURL(in: folder, name: name, fileExtension: "gif")
                controller.start({ progress in
                    try await Exporter.exportGIF(job, options: options, to: url, progress: progress)
                }, writingTo: url)
            }
        }
    }
}
