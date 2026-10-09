//
//  WebcamRecorder.swift
//  Scope
//

import AVFoundation
import os

enum WebcamError: LocalizedError {
    case cameraNotFound
    case cameraUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraNotFound: "The camera isn't connected."
        case .cameraUnavailable: "The camera is in use or can't be recorded."
        }
    }
}

/// Records a camera to its own movie file while the screen is being recorded.
///
/// The camera takes a moment to start, so `prepare()` turns it on during the countdown and
/// `start(to:)` then only has to begin writing the file.
nonisolated final class WebcamRecorder: NSObject, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "Scope.WebcamRecorder")
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var startTime: TimeInterval?
        var started: CheckedContinuation<Void, Error>?
        var finished: CheckedContinuation<Void, Never>?
    }

    init(deviceID: String) throws {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else { throw WebcamError.cameraNotFound }
        let input = try AVCaptureDeviceInput(device: device)
        super.init()

        session.beginConfiguration()
        session.sessionPreset = .high
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw WebcamError.cameraUnavailable
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
    }

    /// When the first webcam frame was written, as a `ProcessInfo.systemUptime` value.
    var startTime: TimeInterval? {
        state.withLock { $0.startTime }
    }

    /// Turns the camera on. Blocks for up to a second or so, so it runs on its own queue.
    func prepare() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.session.startRunning()
                continuation.resume()
            }
        }
    }

    /// Starts writing to `url` and returns once the first frame has been written.
    func start(to url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            state.withLock { $0.started = continuation }
            queue.async {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                self.output.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    /// Finishes the file and turns the camera off.
    func stop() async {
        if output.isRecording {
            await withCheckedContinuation { continuation in
                state.withLock { $0.finished = continuation }
                queue.async { self.output.stopRecording() }
            }
        }
        await withCheckedContinuation { continuation in
            queue.async {
                self.session.stopRunning()
                continuation.resume()
            }
        }
    }

    private func recordingStarted(at time: TimeInterval) {
        let continuation = state.withLock { state in
            state.startTime = time
            defer { state.started = nil }
            return state.started
        }
        continuation?.resume()
    }
}

extension WebcamRecorder: AVCaptureFileOutputRecordingDelegate {
    /// Used before macOS 15.2: the time this is called is close to when the first frame was written.
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        recordingStarted(at: ProcessInfo.processInfo.systemUptime)
    }

    /// Used from macOS 15.2, with the first frame's exact timestamp. It's on the session's clock,
    /// so convert it to the host clock that `systemUptime` also uses.
    @available(macOS 15.2, *)
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, startPTS: CMTime, from connections: [AVCaptureConnection]) {
        let hostTime = session.synchronizationClock.map {
            CMSyncConvertTime(startPTS, from: $0, to: CMClockGetHostTimeClock())
        } ?? startPTS
        recordingStarted(at: hostTime.seconds)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let (started, finished) = state.withLock { state in
            defer {
                state.started = nil
                state.finished = nil
            }
            return (state.started, state.finished)
        }
        // Only still waiting to start if no frame was ever written.
        started?.resume(throwing: error ?? WebcamError.cameraUnavailable)
        finished?.resume()
    }
}
