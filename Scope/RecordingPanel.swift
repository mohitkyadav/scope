//
//  RecordingPanel.swift
//  Scope
//

import SwiftUI

/// The floating card at the bottom of the main window: what to record, the audio and camera chips,
/// the record button, and the size and frame rate of the recording.
struct RecordingPanel: View {
    @Bindable var sources: CaptureSources
    @Bindable var audio: AudioSettings
    @Bindable var camera: CameraSettings
    let microphoneLevel: Float
    let systemAudioLevel: Float
    let recorder: Recorder
    let canRecord: Bool
    let toggleRecording: () -> Void

    @AppStorage(RecordingPreferences.frameRateKey) private var frameRate = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SourcePicker(sources: sources)
                    .disabled(recorder.state != .idle)
                Spacer(minLength: 12)
                RecordButton(state: recorder.state, elapsed: recorder.elapsed, action: toggleRecording)
                    .disabled(!canRecord)
            }

            HStack(spacing: 12) {
                RecordingOptions(audio: audio, camera: camera, microphoneLevel: microphoneLevel, systemAudioLevel: systemAudioLevel)
                    .disabled(recorder.state != .idle)
                Spacer(minLength: 12)
                Text(recorder.isRecording ? "Press \(Recorder.stopShortcut) to stop from any app" : outputDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.scopeCard))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.scopeStroke))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    /// The recording's size and frame rate, e.g. "3840 × 2160 · 60 fps".
    private var outputDescription: String {
        guard let size = sources.selectedArea?.pixelSize else { return "\(frameRate) fps" }
        return "\(Int(size.width)) × \(Int(size.height)) · \(frameRate) fps"
    }
}
