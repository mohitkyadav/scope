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
    private var cursorShapeRecorder: CursorShapeRecorder?
    private var webcam: WebcamRecorder?
    /// `systemUptime` when capture started, and when the first video frame was written.
    private var captureStartTime: TimeInterval = 0
    private var videoStartTime: TimeInterval?

    var isRecording: Bool { state == .recording }

    /// `microphoneID` is the capture device to record alongside the screen, or `nil` for no microphone.
    /// `systemAudio` records the sound the computer plays (from every app for a display, or from the
    /// window's app for a window), but never Scope's own.
    /// Cursor movement and clicks inside `area` are saved into the project too, and so is
    /// the camera `cameraID`, if given, as a separate video.
    func start(
        filter: SCContentFilter,
        area: CaptureArea,
        microphoneID: String?,
        systemAudio: Bool,
        cameraID: String?,
        project: ScopeProject,
        countdownScreen: NSScreen?
    ) async {
        guard state == .idle else { return }
        state = .countingDown

        // Turn the camera on now, so it's ready by the time the countdown ends.
        var webcam: WebcamRecorder?
        var webcamPreparation: Task<Void, Never>?
        if let cameraID {
            do {
                let recorder = try WebcamRecorder(deviceID: cameraID)
                webcam = recorder
                webcamPreparation = Task.detached { await recorder.prepare() }
            } catch {
                errorMessage = "The camera couldn't be recorded: \(error.localizedDescription)"
            }
        }

        let countdown = RecordingPreferences.countdown
        if let countdownScreen, countdown > 0 {
            let countdownTask = Task { await Countdown.run(on: countdownScreen, seconds: countdown) }
            self.countdownTask = countdownTask
            let finished = await countdownTask.value
            self.countdownTask = nil
            guard finished else {
                if let webcam {
                    Task.detached { await webcam.stop() }
                }
                state = .idle
                return
            }
        }
        await webcamPreparation?.value

        let configuration = SCStreamConfiguration()
        // Capture at the area's real pixel size, measured now so a window moved or resized during the
        // countdown still fills the video. (The filter's own `contentRect` can be far too small for a
        // single window, which gave blurry, letterboxed window recordings.)
        let size = area.pixelSize ?? CGSize(
            width: filter.contentRect.width * CGFloat(filter.pointPixelScale),
            height: filter.contentRect.height * CGFloat(filter.pointPixelScale)
        )
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(RecordingPreferences.frameRate))
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
        let cursorShapeRecorder = CursorShapeRecorder()
        cursorShapeRecorder.start()
        captureStartTime = ProcessInfo.processInfo.systemUptime
        videoStartTime = nil

        do {
            try project.createFolder()
            try stream.addRecordingOutput(recordingOutput)
            try await stream.startCapture()
        } catch {
            _ = cursorRecorder.stop(videoStart: captureStartTime)
            _ = cursorShapeRecorder.stop(videoStart: captureStartTime)
            if let webcam {
                Task.detached { await webcam.stop() }
            }
            try? FileManager.default.removeItem(at: project.url)
            errorMessage = error.localizedDescription
            state = .idle
            return
        }

        self.cursorRecorder = cursorRecorder
        self.cursorShapeRecorder = cursorShapeRecorder
        self.stream = stream
        self.recordingOutput = recordingOutput
        self.project = project
        state = .recording
        startTimer()
        stopHotKey = GlobalHotKey(keyCode: kVK_ANSI_2, modifiers: cmdKey | shiftKey) { [weak self] in
            Task { await self?.stop() }
        }

        // The screen keeps recording even if the camera fails; the project just has no webcam.
        if let webcam {
            self.webcam = webcam
            do {
                try await webcam.start(to: project.webcamURL)
            } catch {
                errorMessage = "The camera couldn't be recorded: \(error.localizedDescription)"
            }
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

        let videoStart = videoStartTime ?? captureStartTime
        if let cursorRecorder, let project {
            var track = cursorRecorder.stop(videoStart: videoStart)
            if let shapes = cursorShapeRecorder?.stop(videoStart: videoStart) {
                track.shapes = shapes.shapes
                track.shapeChanges = shapes.changes
                do {
                    try FileManager.default.createDirectory(at: project.cursorsFolderURL, withIntermediateDirectories: true)
                    for (id, png) in shapes.images {
                        try png.write(to: project.cursorsFolderURL.appending(path: "\(id).png"))
                    }
                } catch {
                    // Without its images the cursor is drawn as the arrow, which is how it used to be.
                    track.shapes = nil
                    track.shapeChanges = nil
                }
            }
            do {
                try track.write(to: project.cursorURL)
            } catch {
                errorMessage = "The cursor data couldn't be saved: \(error.localizedDescription)"
            }
        }
        cursorRecorder = nil
        cursorShapeRecorder = nil

        timerTask?.cancel()
        timerTask = nil
        stopHotKey?.unregister()
        stopHotKey = nil
        stream = nil
        recordingOutput = nil
        state = .stopping

        let project = project
        let webcam = webcam
        self.project = nil
        self.webcam = nil

        // The webcam file needs a moment to be finished; the project is ready once it is.
        Task {
            if let webcam, let project {
                await webcam.stop()
                if let webcamStart = webcam.startTime {
                    do {
                        try WebcamInfo(offset: webcamStart - videoStart).write(to: project.webcamInfoURL)
                    } catch {
                        errorMessage = "The camera timing couldn't be saved: \(error.localizedDescription)"
                    }
                }
            }
            lastProject = project
            state = .idle
        }
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
