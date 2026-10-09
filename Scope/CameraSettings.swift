//
//  CameraSettings.swift
//  Scope
//

import AppKit
import AVFoundation
import Observation

struct Camera: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Whether to record a camera, and which one. Choices are remembered between launches.
@Observable
final class CameraSettings {
    var cameraEnabled: Bool {
        didSet { UserDefaults.standard.set(cameraEnabled, forKey: Keys.cameraEnabled) }
    }
    var selectedCameraID: String? {
        didSet { UserDefaults.standard.set(selectedCameraID, forKey: Keys.cameraID) }
    }

    private(set) var cameras: [Camera] = []
    private(set) var cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)

    init() {
        let defaults = UserDefaults.standard
        cameraEnabled = defaults.bool(forKey: Keys.cameraEnabled)
        selectedCameraID = defaults.string(forKey: Keys.cameraID)
    }

    var selectedCamera: Camera? { cameras.first { $0.id == selectedCameraID } }

    /// The camera to record, or `nil` if it's off, not allowed, or unplugged.
    var cameraToRecord: Camera? {
        guard cameraEnabled, cameraAccess == .authorized else { return nil }
        return selectedCamera
    }

    func loadCameras() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        cameras = discovery.devices.map { Camera(id: $0.uniqueID, name: $0.localizedName) }

        // Keep the saved choice if it's connected, otherwise use the system's default camera.
        if selectedCamera == nil {
            selectedCameraID = AVCaptureDevice.default(for: .video)?.uniqueID ?? cameras.first?.id
        }
    }

    /// Shows the system prompt the first time. After that macOS only lets the user change it in System Settings.
    func requestCameraAccess() async {
        if cameraAccess == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func openCameraSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
        NSWorkspace.shared.open(url)
    }

    private enum Keys {
        static let cameraEnabled = "cameraEnabled"
        static let cameraID = "cameraID"
    }
}
