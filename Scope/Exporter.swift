//
//  Exporter.swift
//  Scope
//

import AVFoundation
import ImageIO
import os
import UniformTypeIdentifiers

/// What an export draws: the project's timeline, the renderer that draws its frames, and the volume
/// of each audio track. Exports use the same renderer as the preview, so they look the same.
nonisolated struct ExportJob: @unchecked Sendable {
    let scene: ProjectComposition
    let renderer: FrameRenderer
    let audioMix: AVAudioMix
    let name: String

    var canvasSize: CGSize { renderer.canvasSize }
    var duration: Double { scene.timeMap.duration }
}

nonisolated enum ExportQuality: String, CaseIterable, Identifiable, Sendable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: Self { self }

    /// Bits per pixel per frame for the video encoder.
    fileprivate var bitsPerPixel: Double {
        switch self {
        case .high: 0.12
        case .medium: 0.07
        case .low: 0.035
        }
    }
}

nonisolated struct MovieOptions: Sendable {
    var size: CGSize
    var frameRate = 60
    var quality = ExportQuality.high

    var bitRate: Int {
        Int(size.width * size.height * Double(frameRate) * quality.bitsPerPixel)
    }

    /// H.264 plays almost everywhere but tops out around 4K; bigger frames use HEVC.
    var codec: AVVideoCodecType {
        size.width > 4096 || size.height > 2304 ? .hevc : .h264
    }
}

nonisolated struct GIFOptions: Equatable, Sendable {
    /// The section to export, in seconds of the final video.
    var start: Double
    var end: Double
    var width = 640
    var frameRate = 15
    /// How much faster than the video the GIF plays.
    var speed = 1.0
    /// How many times it plays, or 0 for forever.
    var plays = 0
    /// Play forwards, then backwards back to the start.
    var boomerang = false
    /// Seconds to stay on the last frame before playing again.
    var hold = 0.0
    /// Ease the cursor back to where it started, so the loop doesn't jump. Not needed for a boomerang,
    /// which comes back by itself.
    var loopsCursor = true
    var includesWebcam = true
    var includesNotes = true

    /// A width and frame rate tried to fit a GIF into a size limit.
    struct Step: Equatable, Sendable {
        var width: Int
        var frameRate: Int
    }

    /// Tried in this order, best first.
    static let fittingSteps = [
        Step(width: 1080, frameRate: 24), Step(width: 1080, frameRate: 20), Step(width: 800, frameRate: 24),
        Step(width: 800, frameRate: 20), Step(width: 800, frameRate: 15), Step(width: 640, frameRate: 20),
        Step(width: 640, frameRate: 15), Step(width: 480, frameRate: 15), Step(width: 480, frameRate: 10),
    ]

    /// When each frame is taken from the video, in seconds of the final video, in the order they play.
    var times: [Double] {
        let forwards = Array(stride(from: start, to: end, by: speed / Double(frameRate)))
        guard boomerang, forwards.count > 2 else { return forwards }
        // Back again without showing either end twice.
        return forwards + forwards.dropFirst().dropLast().reversed()
    }

    /// How long the GIF plays once through, in seconds.
    var playingTime: Double {
        Double(times.count) / Double(frameRate) + hold
    }
}

nonisolated enum ExportError: LocalizedError {
    case cannotWrite
    case failed(Error?)

    var errorDescription: String? {
        switch self {
        case .cannotWrite: "The file couldn't be created."
        case .failed(let error): error?.localizedDescription ?? "The export failed."
        }
    }
}

/// Writes a project's timeline to an MP4 or a looping GIF.
nonisolated enum Exporter {
    /// A size with the canvas's shape and the given height, rounded to even numbers as encoders need.
    static func size(forHeight height: Int, canvas: CGSize) -> CGSize {
        let height = Double(height - height % 2)
        let width = (height * canvas.width / max(canvas.height, 1) / 2).rounded() * 2
        return CGSize(width: width, height: height)
    }

    /// The size of a `canvas`-shaped video whose shorter side is `shorterSide`, e.g. 1080 × 1920 for 1080p 9:16.
    static func size(forShorterSide shorterSide: Int, canvas: CGSize) -> CGSize {
        guard canvas.height > canvas.width else { return size(forHeight: shorterSide, canvas: canvas) }
        let width = Double(shorterSide - shorterSide % 2)
        let height = (width * canvas.height / max(canvas.width, 1) / 2).rounded() * 2
        return CGSize(width: width, height: height)
    }

    /// `name.ext` in `folder`, or `name 2.ext`, `name 3.ext`… if it's taken.
    static func availableURL(in folder: URL, name: String, fileExtension: String) -> URL {
        var url = folder.appending(path: "\(name).\(fileExtension)")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(name) \(number).\(fileExtension)")
            number += 1
        }
        return url
    }

    // MARK: - MP4

    /// Reads the timeline through the compositor and encodes it. `progress` gets 0...1.
    static func exportMovie(_ job: ExportJob, options: MovieOptions, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let composition = job.scene.composition
        let reader = try AVAssetReader(asset: composition)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: composition.tracks(withMediaType: .video),
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = job.scene.videoComposition(renderer: job.renderer, renderSize: options.size, frameRate: options.frameRate)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw ExportError.cannotWrite }
        reader.add(videoOutput)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: options.codec,
            AVVideoWidthKey: Int(options.size.width),
            AVVideoHeightKey: Int(options.size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: options.bitRate,
                AVVideoExpectedSourceFrameRateKey: options.frameRate,
                AVVideoMaxKeyFrameIntervalKey: options.frameRate * 2,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw ExportError.cannotWrite }
        writer.add(videoInput)

        // Audio: every track mixed at its volume, with voices kept at their pitch in sped-up clips.
        var audio: (output: AVAssetReaderAudioMixOutput, input: AVAssetWriterInput)?
        let audioTracks = composition.tracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
            ])
            output.audioMix = job.audioMix
            output.audioTimePitchAlgorithm = .timeDomain
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audio = (output, input)
            }
        }

        guard reader.startReading(), writer.startWriting() else {
            throw ExportError.failed(reader.error ?? writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        let cancelled = OSAllocatedUnfairLock(initialState: false)
        let duration = max(job.duration, 0.001)
        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await pump(videoOutput, into: videoInput, label: "video", cancelled: cancelled) { buffer in
                        progress(min(buffer.presentationTimeStamp.seconds / duration, 1))
                    }
                }
                if let audio {
                    group.addTask {
                        await pump(audio.output, into: audio.input, label: "audio", cancelled: cancelled) { _ in }
                    }
                }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
        }

        if cancelled.withLock({ $0 }) {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw ExportError.failed(reader.error)
        }
        await writer.finishWriting()
        if writer.status != .completed {
            try? FileManager.default.removeItem(at: url)
            throw ExportError.failed(writer.error)
        }
        progress(1)
    }

    /// Moves samples from `output` to `input` until the output runs dry or the export is cancelled.
    private static func pump(
        _ output: AVAssetReaderOutput,
        into input: AVAssetWriterInput,
        label: String,
        cancelled: OSAllocatedUnfairLock<Bool>,
        onSample: @escaping @Sendable (CMSampleBuffer) -> Void
    ) async {
        let queue = DispatchQueue(label: "Scope.Exporter.\(label)")
        let pumping = Pumping(output: output, input: input)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let finished = OSAllocatedUnfairLock(initialState: false)
            func finish() {
                let alreadyFinished = finished.withLock { done in
                    defer { done = true }
                    return done
                }
                guard !alreadyFinished else { return }
                pumping.input.markAsFinished()
                continuation.resume()
            }
            pumping.input.requestMediaDataWhenReady(on: queue) {
                while pumping.input.isReadyForMoreMediaData {
                    guard !cancelled.withLock({ $0 }), let buffer = pumping.output.copyNextSampleBuffer() else {
                        finish()
                        return
                    }
                    onSample(buffer)
                    if !pumping.input.append(buffer) {
                        finish()
                        return
                    }
                }
            }
        }
    }

    /// The reader output and writer input of one track, handed to the writer's queue.
    private final class Pumping: @unchecked Sendable {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput

        init(output: AVAssetReaderOutput, input: AVAssetWriterInput) {
            self.output = output
            self.input = input
        }
    }

    // MARK: - GIF

    /// Renders a section of the timeline as frames and saves them as a GIF that loops forever.
    static func exportGIF(_ job: ExportJob, options: GIFOptions, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let frameDuration = 1 / Double(options.frameRate)
        let times = options.times
        guard !times.isEmpty,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, times.count, nil)
        else { throw ExportError.cannotWrite }

        // Without a loop count the GIF plays once. ImageIO turns "plays" into the GIF's own repeat count.
        if options.plays != 1 {
            CGImageDestinationSetProperties(destination, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: options.plays],
            ] as CFDictionary)
        }
        // The last frame before the GIF turns around or starts again stays up for the hold.
        let lastForwards = times.firstIndex(of: times.max() ?? 0) ?? times.count - 1

        var written = 0
        for await result in gifFrames(job, options: options, at: times) {
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: url)
                throw CancellationError()
            }
            let delay = written == lastForwards ? frameDuration + options.hold : frameDuration
            CGImageDestinationAddImage(destination, try result.image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay],
            ] as CFDictionary)
            written += 1
            progress(Double(written) / Double(times.count))
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw ExportError.cannotWrite
        }
    }

    /// Roughly how big the GIF will be, in bytes, from a few of its frames encoded at its width.
    /// Each frame is stored whole, so the size grows with the number of frames.
    static func estimateGIFSize(_ job: ExportJob, options: GIFOptions) async -> Int? {
        let times = options.times
        guard !times.isEmpty else { return nil }
        let samples = (0..<4).map { times[min(times.count - 1, $0 * times.count / 4)] }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, samples.count, nil) else { return nil }
        var encoded = 0
        for await result in gifFrames(job, options: options, at: samples) {
            guard let image = try? result.image else { continue }
            CGImageDestinationAddImage(destination, image, nil)
            encoded += 1
        }
        guard encoded > 0, CGImageDestinationFinalize(destination) else { return nil }
        return data.length * times.count / encoded
    }

    /// The finished frames at `times`, at the GIF's size, with what it leaves out left out.
    private static func gifFrames(_ job: ExportJob, options: GIFOptions, at times: [Double]) -> AVAssetImageGenerator.Images {
        var renderer = job.renderer
        if !options.includesWebcam {
            renderer.settings.webcamVisible = false
        }
        if !options.includesNotes {
            renderer.notes = []
        }
        if options.loopsCursor, !options.boomerang {
            // Finish easing back on the last frame, so the first frame follows it without a jump.
            renderer.cursorLoop = CursorLoop(start: options.start, end: options.end - options.speed / Double(options.frameRate))
        }

        let size = Self.size(forHeight: Int((Double(options.width) * job.canvasSize.height / max(job.canvasSize.width, 1)).rounded()), canvas: job.canvasSize)
        let generator = AVAssetImageGenerator(asset: job.scene.composition)
        generator.videoComposition = job.scene.videoComposition(renderer: renderer, renderSize: size, frameRate: 60)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return generator.images(for: times.map { CMTime(seconds: $0, preferredTimescale: 60_000) })
    }
}
