//
//  AudioSettings.swift
//  Scope
//

import AppKit
import AVFoundation
import Observation

struct Microphone: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Which audio to record. Choices are remembered between launches.
@Observable
final class AudioSettings {
    var microphoneEnabled: Bool {
        didSet { UserDefaults.standard.set(microphoneEnabled, forKey: Keys.microphoneEnabled) }
    }
    var selectedMicrophoneID: String? {
        didSet { UserDefaults.standard.set(selectedMicrophoneID, forKey: Keys.microphoneID) }
    }

    private(set) var microphones: [Microphone] = []
    private(set) var microphoneAccess = AVCaptureDevice.authorizationStatus(for: .audio)

    init() {
        let defaults = UserDefaults.standard
        microphoneEnabled = defaults.bool(forKey: Keys.microphoneEnabled)
        selectedMicrophoneID = defaults.string(forKey: Keys.microphoneID)
    }

    var selectedMicrophone: Microphone? { microphones.first { $0.id == selectedMicrophoneID } }

    /// The microphone to record, or `nil` if it's off, not allowed, or unplugged.
    var microphoneToRecord: Microphone? {
        guard microphoneEnabled, microphoneAccess == .authorized else { return nil }
        return selectedMicrophone
    }

    func loadMicrophones() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        microphones = discovery.devices.map { Microphone(id: $0.uniqueID, name: $0.localizedName) }

        // Keep the saved choice if it's plugged in, otherwise use the system's default input.
        if selectedMicrophone == nil {
            selectedMicrophoneID = AVCaptureDevice.default(for: .audio)?.uniqueID ?? microphones.first?.id
        }
    }

    /// Shows the system prompt the first time. After that macOS only lets the user change it in System Settings.
    func requestMicrophoneAccess() async {
        if microphoneAccess == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        microphoneAccess = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    private enum Keys {
        static let microphoneEnabled = "microphoneEnabled"
        static let microphoneID = "microphoneID"
    }
}
