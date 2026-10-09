//
//  Recorder.swift
//  Scope
//

import Foundation
import Observation
import ScreenCaptureKit

@Observable
final class Recorder: NSObject {
    enum State {
        case idle
        case countingDown
        case recording
        case stopping
    }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastRecordingURL: URL?
    var errorMessage: String?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var timerTask: Task<Void, Never>?

    var isRecording: Bool { state == .recording }

    func start(filter: SCContentFilter, outputURL: URL) async {
        guard state == .idle else { return }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 6
        configuration.showsCursor = true

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = outputURL
        outputConfiguration.outputFileType = .mp4
        outputConfiguration.videoCodecType = .h264

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let recordingOutput = SCRecordingOutput(configuration: outputConfiguration, delegate: self)

        do {
            try stream.addRecordingOutput(recordingOutput)
            try await stream.startCapture()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        self.stream = stream
        self.recordingOutput = recordingOutput
        self.outputURL = outputURL
        state = .recording
        startTimer()
    }

    func stop() async {
        guard state == .recording, let stream else { return }
        state = .stopping

        do {
            try await stream.stopCapture()
        } catch {
            finish(error: error)
        }
        // The file is finalised once the recording output calls `recordingOutputDidFinishRecording`.
    }

    private func startTimer() {
        let start = Date.now
        elapsed = 0
        timerTask = Task {
            while !Task.isCancelled {
                elapsed = Date.now.timeIntervalSince(start)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func finish(error: Error? = nil) {
        guard stream != nil else { return }

        if let error {
            errorMessage = error.localizedDescription
        }
        lastRecordingURL = outputURL

        timerTask?.cancel()
        timerTask = nil
        stream = nil
        recordingOutput = nil
        outputURL = nil
        state = .idle
    }
}

extension Recorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            // Stopping from the system's screen sharing menu isn't a failure.
            let userStopped = (error as? SCStreamError)?.code == .userStopped
            finish(error: userStopped ? nil : error)
        }
    }
}

extension Recorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            finish(error: error)
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            finish()
        }
    }
}
