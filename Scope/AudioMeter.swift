//
//  AudioMeter.swift
//  Scope
//

import AVFoundation
import Observation
import os
import ScreenCaptureKit

/// A live input level from 0 (silent) to 1 (loud), for the microphone or for system audio.
@Observable
final class AudioMeter {
    private(set) var level: Float = 0

    /// Measures a microphone until the calling task is cancelled.
    func runMicrophone(deviceID: String) async {
        guard let device = AVCaptureDevice(uniqueID: deviceID),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }

        let tap = AudioLevelTap()
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
        ]
        output.setSampleBufferDelegate(tap, queue: tap.queue)

        let session = AVCaptureSession()
        guard session.canAddInput(input), session.canAddOutput(output) else { return }
        session.addInput(input)
        session.addOutput(output)

        let runner = SessionRunner(session: session)
        await runner.start()
        await follow(tap)
        await runner.stop()
    }

    /// Measures the sound the computer plays for `filter` until the calling task is cancelled.
    func runSystemAudio(filter: SCContentFilter) async {
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        // Video is required but unused here, so keep it tiny.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let tap = AudioLevelTap()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        do {
            try stream.addStreamOutput(tap, type: .audio, sampleHandlerQueue: tap.queue)
            try stream.addStreamOutput(tap, type: .screen, sampleHandlerQueue: tap.queue)
            try await stream.startCapture()
        } catch {
            return
        }

        await follow(tap)
        try? await stream.stopCapture()
    }

    private func follow(_ tap: AudioLevelTap) async {
        while !Task.isCancelled {
            // Map -50 dB...0 dB onto 0...1, and let the bar fall back gently instead of flickering.
            let decibels = 20 * log10(max(tap.takePeak(), 0.000_01))
            let target = min(max((decibels + 50) / 50, 0), 1)
            level = max(target, level * 0.8)
            try? await Task.sleep(for: .milliseconds(50))
        }
        level = 0
    }
}

/// Starts and stops a capture session off the main thread, since both calls block.
private nonisolated final class SessionRunner: @unchecked Sendable {
    private let session: AVCaptureSession
    private let queue = DispatchQueue(label: "Scope.AudioMeter.session")

    init(session: AVCaptureSession) {
        self.session = session
    }

    func start() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.session.startRunning()
                continuation.resume()
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.session.stopRunning()
                continuation.resume()
            }
        }
    }
}

/// Keeps the loudest sample seen in audio buffers that arrive on a background queue.
private nonisolated final class AudioLevelTap: NSObject, @unchecked Sendable {
    let queue = DispatchQueue(label: "Scope.AudioMeter.samples")
    private let peak = OSAllocatedUnfairLock<Float>(initialState: 0)

    /// The loudest sample since the last call, from 0 to 1.
    func takePeak() -> Float {
        peak.withLock { peak in
            defer { peak = 0 }
            return peak
        }
    }

    func add(_ sampleBuffer: CMSampleBuffer) {
        guard let format = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32
        else { return }

        var loudest: Float = 0
        try? sampleBuffer.withAudioBufferList { buffers, _ in
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let samples = UnsafeBufferPointer(
                    start: data.assumingMemoryBound(to: Float.self),
                    count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                )
                for sample in samples {
                    loudest = max(loudest, abs(sample))
                }
            }
        }
        let bufferPeak = loudest
        peak.withLock { $0 = max($0, bufferPeak) }
    }
}

extension AudioLevelTap: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        add(sampleBuffer)
    }
}

extension AudioLevelTap: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        add(sampleBuffer)
    }
}
