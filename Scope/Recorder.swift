//
//  Recorder.swift
//  Scope
//

import AppKit
import Carbon.HIToolbox
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

    /// Stops a recording from any app. Only registered while recording.
    static let stopShortcut = "⌘⇧2"

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastRecordingURL: URL?
    var errorMessage: String?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var timerTask: Task<Void, Never>?
    private var countdownTask: Task<Bool, Never>?
    private var stopHotKey: GlobalHotKey?

    var isRecording: Bool { state == .recording }

    /// `microphoneID` is the capture device to record alongside the screen, or `nil` for no microphone.
    /// `systemAudio` records the sound the computer plays (from every app for a display, or from the
    /// window's app for a window), but never Scope's own.
    func start(
        filter: SCContentFilter,
        microphoneID: String?,
        systemAudio: Bool,
        outputURL: URL,
        countdownScreen: NSScreen?
    ) async {
        guard state == .idle else { return }

        if let countdownScreen {
            state = .countingDown
            let countdownTask = Task { await Countdown.run(on: countdownScreen) }
            self.countdownTask = countdownTask
            let finished = await countdownTask.value
            self.countdownTask = nil
            guard finished else {
                state = .idle
                return
            }
        }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 6
        // Scope draws its own cursor from the recorded cursor data, so leave the real one out.
        configuration.showsCursor = false

        if systemAudio {
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
        }

        if let microphoneID {
            configuration.captureMicrophone = true
            configuration.microphoneCaptureDeviceID = microphoneID
        }

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
            state = .idle
            return
        }

        self.stream = stream
        self.recordingOutput = recordingOutput
        self.outputURL = outputURL
        state = .recording
        startTimer()
        stopHotKey = GlobalHotKey(keyCode: kVK_ANSI_2, modifiers: cmdKey | shiftKey) { [weak self] in
            Task { await self?.stop() }
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
    }

    func stop() async {
        guard state == .recording, let stream else { return }
        state = .stopping

        do {
            try await stream.stopCapture()
        } catch {
            finish(error: error)
            return
        }

        // The file is finalised once the recording output calls `recordingOutputDidFinishRecording`.
        // If that never arrives, don't leave the app stuck in the stopping state.
        try? await Task.sleep(for: .seconds(5))
        if state == .stopping, self.stream === stream {
            finish()
        }
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
        stopHotKey?.unregister()
        stopHotKey = nil
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
