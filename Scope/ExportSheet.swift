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
    /// The video's shorter side in pixels: its height, or its width for a tall video.
    @State private var resolution = 0
    @State private var frameRate = 60
    @State private var quality = ExportQuality.high
    @State private var gifStart = 0.0
    @State private var gifEnd = 0.0
    @State private var gifWidth = 640
    @State private var gifFrameRate = 15
    @State private var loopsCursor = true
    @AppStorage("gifSpeed") private var gifSpeed = 1.0
    /// How many times it plays, or 0 for forever.
    @AppStorage("gifPlays") private var gifPlays = 0
    @AppStorage("gifBoomerang") private var gifBoomerang = false
    @AppStorage("gifHold") private var gifHold = 0.0
    /// The most the GIF may weigh, in megabytes, or 0 for no limit.
    @AppStorage("gifSizeLimit") private var gifSizeLimit = 0
    @AppStorage("gifIncludesWebcam") private var gifIncludesWebcam = true
    @AppStorage("gifIncludesNotes") private var gifIncludesNotes = true
    @AppStorage("gifCopiesWhenDone") private var gifCopiesWhenDone = false
    /// How big one frame of the GIF comes out at 640 px wide, measured from a few frames.
    @State private var gifBytesPerFrame: Double?
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
            .frame(maxHeight: 540)
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
        .task(id: gifSample) {
            await measureGIFFrames()
        }
        .onChange(of: controller.state) {
            if case .finished(let url) = controller.state, url.pathExtension == "gif", gifCopiesWhenDone {
                Self.copy(url)
            }
        }
    }

    // MARK: - Settings

    @ViewBuilder
    private var movieSettings: some View {
        Picker("Resolution", selection: $resolution) {
            ForEach(resolutions, id: \.self) { resolution in
                let size = Exporter.size(forShorterSide: resolution, canvas: canvas)
                Text(resolution == resolutions.first ? "Original (\(Int(size.width)) × \(Int(size.height)))" : "\(resolution)p (\(Int(size.width)) × \(Int(size.height)))")
                    .tag(resolution)
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
        Section("Range") {
            LabeledSlider("Start", value: $gifStart, in: 0...max(duration, 0.1)) { $0.timecodeString }
                .onChange(of: gifStart) {
                    gifEnd = max(gifEnd, min(gifStart + 0.2, duration))
                }
            LabeledSlider("End", value: $gifEnd, in: 0...max(duration, 0.1)) { $0.timecodeString }
                .onChange(of: gifEnd) {
                    gifStart = min(gifStart, max(gifEnd - 0.2, 0))
                }
            LabeledContent("Use") {
                HStack {
                    Button("Selected Clip", action: useSelectedClip)
                        .disabled(model.selectedClip == nil)
                        .help("The clip selected on the timeline")
                    Button("From Playhead", action: useFromPlayhead)
                        .help("Five seconds from the playhead")
                }
            }
        }

        Section("Playback") {
            Picker("Speed", selection: $gifSpeed) {
                ForEach([1.0, 1.5, 2, 3], id: \.self) { speed in
                    Text(String(format: "%g×", speed)).tag(speed)
                }
            }
            Picker("Plays", selection: $gifPlays) {
                Text("Forever").tag(0)
                Text("Once").tag(1)
                ForEach([2, 3, 5], id: \.self) { plays in
                    Text("\(plays) times").tag(plays)
                }
            }
            Toggle("Boomerang", isOn: $gifBoomerang)
                .help("Play forwards, then backwards back to the start")
            Picker("Pause at end", selection: $gifHold) {
                Text("None").tag(0.0)
                ForEach([1.0, 2, 3], id: \.self) { seconds in
                    Text(String(format: "%g s", seconds)).tag(seconds)
                }
            }
            .help(gifBoomerang ? "Stays on the last frame before playing back" : "Stays on the last frame before playing again")
            if !gifBoomerang {
                Toggle("Loop cursor", isOn: $loopsCursor)
                    .help("Ease the cursor back to where it started, so the loop doesn't jump")
            }
        }

        Section("Size") {
            Picker("Size limit", selection: $gifSizeLimit) {
                Text("None").tag(0)
                Text("25 MB").tag(25)
                Text("10 MB (GitHub)").tag(10)
                Text("5 MB").tag(5)
            }
            Group {
                Picker("Width", selection: gifSizeLimit > 0 ? .constant(gifStep.width) : $gifWidth) {
                    ForEach([480, 640, 800, 1080], id: \.self) { width in
                        Text("\(width) px").tag(width)
                    }
                }
                Picker("Frame rate", selection: gifSizeLimit > 0 ? .constant(gifStep.frameRate) : $gifFrameRate) {
                    ForEach([10, 15, 20, 24], id: \.self) { rate in
                        Text("\(rate) fps").tag(rate)
                    }
                }
            }
            .disabled(gifSizeLimit > 0)
            .help(gifSizeLimit > 0 ? "Picked to fit the size limit" : "")
            LabeledContent("Length", value: String(format: "%.1f s, %d frames", gifOptions.playingTime, gifOptions.times.count))
            LabeledContent("Estimated size", value: estimatedGIFSize)
        }

        Section("Content") {
            if model.hasWebcam {
                Toggle("Include camera", isOn: $gifIncludesWebcam)
            }
            if !model.edits.notes.isEmpty {
                Toggle("Include notes", isOn: $gifIncludesNotes)
            }
            Toggle("Copy to clipboard when done", isOn: $gifCopiesWhenDone)
                .help("Ready to paste into Slack, GitHub or a message")
        }
    }

    /// The GIF's settings, with the width and frame rate picked to fit the size limit if there is one.
    private var gifOptions: GIFOptions {
        GIFOptions(
            start: gifStart,
            end: gifEnd,
            width: gifStep.width,
            frameRate: gifStep.frameRate,
            speed: gifSpeed,
            plays: gifPlays,
            boomerang: gifBoomerang,
            hold: gifHold,
            loopsCursor: loopsCursor,
            includesWebcam: gifIncludesWebcam,
            includesNotes: gifIncludesNotes
        )
    }

    /// The chosen width and frame rate, or with a size limit the best ones that fit.
    private var gifStep: GIFOptions.Step {
        guard gifSizeLimit > 0, gifBytesPerFrame != nil else { return GIFOptions.Step(width: gifWidth, frameRate: gifFrameRate) }
        let limit = Double(gifSizeLimit) * 1_000_000 * 0.9
        return GIFOptions.fittingSteps.first { (estimatedBytes(for: $0) ?? .infinity) <= limit } ?? GIFOptions.fittingSteps[GIFOptions.fittingSteps.count - 1]
    }

    /// Frames take up about as much room as they have pixels, so one measurement covers every width.
    private func estimatedBytes(for step: GIFOptions.Step) -> Double? {
        guard let gifBytesPerFrame else { return nil }
        let area = pow(Double(step.width) / 640, 2)
        return gifBytesPerFrame * area * Double(gifOptions(step).times.count)
    }

    private func gifOptions(_ step: GIFOptions.Step) -> GIFOptions {
        GIFOptions(start: gifStart, end: gifEnd, width: step.width, frameRate: step.frameRate, speed: gifSpeed, boomerang: gifBoomerang)
    }

    private var estimatedGIFSize: String {
        guard let bytes = estimatedBytes(for: gifStep) else { return "Working it out…" }
        return "About " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// What a frame looks like, so the size is measured again when it changes, but not for the
    /// width or frame rate, which are worked out from the measurement.
    private var gifSample: [Double] {
        guard format == .gif else { return [] }
        return [gifStart, gifEnd, gifIncludesWebcam ? 1 : 0, gifIncludesNotes ? 1 : 0]
    }

    private func measureGIFFrames() async {
        guard format == .gif, gifEnd > gifStart else { return }
        // Wait for sliders to settle.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, let job = await model.exportJob() else { return }
        var options = gifOptions
        options.width = 640
        options.speed = 1
        options.boomerang = false
        guard let bytes = await Exporter.estimateGIFSize(job, options: options), !Task.isCancelled else { return }
        gifBytesPerFrame = Double(bytes) / Double(max(options.times.count, 1))
    }

    private func useSelectedClip() {
        guard let clip = model.selectedClip, let index = model.edits.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let start = model.timeMap.outputStarts[index]
        gifStart = start
        gifEnd = min(start + clip.duration, duration)
    }

    private func useFromPlayhead() {
        gifStart = min(model.currentTime, max(duration - 0.2, 0))
        gifEnd = min(gifStart + 5, duration)
    }

    /// Puts an exported file on the clipboard, both as the file and, for a GIF, as the image itself.
    private static func copy(_ url: URL) {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if url.pathExtension == "gif", let data = try? Data(contentsOf: url) {
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    /// The video's own size, then common smaller ones, measured along the shorter side like "1080p".
    private var resolutions: [Int] {
        let original = Int(min(canvas.width, canvas.height))
        return [original] + [2160, 1440, 1080, 720].filter { $0 < original }
    }

    private var estimatedMovieSize: String {
        let options = MovieOptions(size: Exporter.size(forShorterSide: resolution, canvas: canvas), frameRate: frameRate, quality: quality)
        let bytes = (Double(options.bitRate) + 192_000) * duration / 8
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func setDefaults() {
        fileName = model.project.name
        resolution = Int(min(canvas.width, canvas.height))
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
                Button("Copy") { Self.copy(url) }
                    .help("Copy the file, ready to paste")
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
                let options = MovieOptions(size: Exporter.size(forShorterSide: resolution, canvas: canvas), frameRate: frameRate, quality: quality)
                let url = Exporter.availableURL(in: folder, name: name, fileExtension: "mp4")
                controller.start({ progress in
                    try await Exporter.exportMovie(job, options: options, to: url, progress: progress)
                }, writingTo: url)

            case .gif:
                let options = gifOptions
                let limit = gifSizeLimit * 1_000_000
                let url = Exporter.availableURL(in: folder, name: name, fileExtension: "gif")
                controller.start({ progress in
                    try await Exporter.exportGIF(job, options: options, to: url, progress: progress)
                    guard limit > 0 else { return }
                    // The size was only an estimate. If it came out too big, go down a step until it fits.
                    var options = options
                    let steps = GIFOptions.fittingSteps
                    var next = (steps.firstIndex { $0 == GIFOptions.Step(width: options.width, frameRate: options.frameRate) } ?? 0) + 1
                    while let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit, next < steps.count {
                        options.width = steps[next].width
                        options.frameRate = steps[next].frameRate
                        next += 1
                        try await Exporter.exportGIF(job, options: options, to: url, progress: progress)
                    }
                }, writingTo: url)
            }
        }
    }
}
