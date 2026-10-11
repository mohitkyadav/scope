//
//  RecordingOptions.swift
//  Scope
//

import AVFoundation
import SwiftUI

/// The Microphone, System Audio and Camera chips under the source picker.
struct RecordingOptions: View {
    @Bindable var audio: AudioSettings
    @Bindable var camera: CameraSettings
    let microphoneLevel: Float
    let systemAudioLevel: Float

    var body: some View {
        HStack(spacing: 10) {
            OptionChip(
                title: "Microphone",
                icon: "mic",
                detail: microphoneDetail,
                isOn: audio.microphoneEnabled,
                level: audio.microphoneToRecord != nil ? microphoneLevel : nil,
                action: {
                    if isDenied(audio.microphoneAccess) {
                        audio.openMicrophoneSettings()
                    } else {
                        audio.microphoneEnabled.toggle()
                        if audio.microphoneEnabled {
                            Task { await audio.requestMicrophoneAccess() }
                        }
                    }
                },
                choices: audio.microphones.map { ($0.id, $0.name) },
                selectedChoice: audio.selectedMicrophoneID,
                choose: { audio.selectedMicrophoneID = $0 }
            )

            OptionChip(
                title: "System Audio",
                icon: "speaker.wave.2",
                detail: nil,
                isOn: audio.systemAudioEnabled,
                level: audio.systemAudioEnabled ? systemAudioLevel : nil,
                action: { audio.systemAudioEnabled.toggle() }
            )

            OptionChip(
                title: "Camera",
                icon: "video",
                detail: cameraDetail,
                isOn: camera.cameraEnabled,
                level: nil,
                action: {
                    if isDenied(camera.cameraAccess) {
                        camera.openCameraSettings()
                    } else {
                        camera.cameraEnabled.toggle()
                        if camera.cameraEnabled {
                            Task { await camera.requestCameraAccess() }
                        }
                    }
                },
                choices: camera.cameras.map { ($0.id, $0.name) },
                selectedChoice: camera.selectedCameraID,
                choose: { camera.selectedCameraID = $0 }
            )
        }
    }

    private var microphoneDetail: String? {
        guard audio.microphoneEnabled else { return nil }
        if isDenied(audio.microphoneAccess) { return "Allow access…" }
        return audio.selectedMicrophone?.name ?? "No microphone"
    }

    private var cameraDetail: String? {
        guard camera.cameraEnabled else { return nil }
        if isDenied(camera.cameraAccess) { return "Allow access…" }
        return camera.selectedCamera?.name ?? "No camera"
    }

    private func isDenied(_ status: AVAuthorizationStatus) -> Bool {
        status == .denied || status == .restricted
    }
}

/// A rounded chip that turns something on or off. When on it's tinted blue and can show a detail
/// (like the device in use) and a small level meter. With `choices`, a chevron picks the device.
private struct OptionChip: View {
    let title: String
    let icon: String
    let detail: String?
    let isOn: Bool
    let level: Float?
    let action: () -> Void
    var choices: [(String, String)] = []
    var selectedChoice: String?
    var choose: (String) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: isOn ? "\(icon).fill" : icon)
                        .font(.body)
                        .frame(width: 18)
                    Text(title)
                        .font(.body.weight(.medium))
                    if let detail {
                        Text(detail)
                            .foregroundStyle(isOn ? Color.accentColor.opacity(0.9) : .secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 160, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if let level {
                        LevelMeter(level: level)
                            .frame(width: 28)
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, choices.isEmpty ? 14 : 6)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOn ? "On" : "Off")
            .help(isOn ? "Turn \(title.lowercased()) off" : "Turn \(title.lowercased()) on")

            if !choices.isEmpty {
                Menu {
                    ForEach(choices, id: \.0) { id, name in
                        Button {
                            choose(id)
                        } label: {
                            if id == selectedChoice {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 12)
                        .padding(.leading, 4)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose the \(title.lowercased())")
            }
        }
        .foregroundStyle(isOn ? Color.primary : Color.secondary)
        .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.18) : Color.scopePill))
        .overlay(Capsule().strokeBorder(isOn ? Color.accentColor.opacity(0.6) : Color.scopeStroke))
        .fixedSize()
    }
}
