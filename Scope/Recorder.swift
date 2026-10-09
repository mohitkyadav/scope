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
    private(set) var lastProject: ScopeProject?
    var errorMessage: String?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var project: ScopeProject?
    private var timerTask: Task<Void, Never>?
    private var countdownTask: Task<Bool, Never>?
    private var stopHotKey: GlobalHotKey?
    private var cursorRecorder: CursorRecorder?
    /// `systemUptime` when capture started, and when the first video frame was written.
    private var captureStartTime: TimeInterval = 0
    private var videoStartTime: TimeInterval?

    var isRecording: Bool { state == .recording }

    /// `microphoneID` is the capture device to record alongside the screen, or `nil` for no microphone.
    /// `systemAudio` records the sound the computer plays (from every app for a display, or from the
    /// window's app for a window), but never Scope's own.
    /// Cursor movement and clicks inside `area` are saved into the project too.
    func start(
        filter: SCContentFilter,
        area: CaptureArea,
        microphoneID: String?,
        systemAudio: Bool,
        project: ScopeProject,
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
        outputConfiguration.outputURL = project.videoURL
        outputConfiguration.outputFileType = .mp4
        outputConfiguration.videoCodecType = .h264

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let recordingOutput = SCRecordingOutput(configuration: outputConfiguration, delegate: self)

        // Start following the cursor first, so its position is known when the first frame arrives.
        let cursorRecorder = CursorRecorder(area: area)
        cursorRecorder.start()
        captureStartTime = ProcessInfo.processInfo.systemUptime
        videoStartTime = nil

        do {
            try project.createFolder()
            try stream.addRecordingOutput(recordingOutput)
            try await stream.startCapture()
        } catch {
            _ = cursorRecorder.stop(videoStart: captureStartTime)
            try? FileManager.default.removeItem(at: project.url)
            errorMessage = error.localizedDescription
            state = .idle
            return
        }

        self.cursorRecorder = cursorRecorder
        self.stream = stream
        self.recordingOutput = recordingOutput
        self.project = project
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

        if let cursorRecorder, let project {
            let track = cursorRecorder.stop(videoStart: videoStartTime ?? captureStartTime)
            do {
                try track.write(to: project.cursorURL)
            } catch {
                errorMessage = "The cursor data couldn't be saved: \(error.localizedDescription)"
            }
        }
        cursorRecorder = nil
        lastProject = project

        timerTask?.cancel()
        timerTask = nil
        stopHotKey?.unregister()
        stopHotKey = nil
        stream = nil
        recordingOutput = nil
        project = nil
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
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        // Read the clock here rather than after hopping to the main actor, so cursor times line up with the video.
        let now = ProcessInfo.processInfo.systemUptime
        Task { @MainActor in
            if videoStartTime == nil {
                videoStartTime = now
            }
        }
    }

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
