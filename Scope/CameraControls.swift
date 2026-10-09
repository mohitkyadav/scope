//
//  CameraControls.swift
//  Scope
//

import AVFoundation
import SwiftUI

struct CameraControls: View {
    @Bindable var settings: CameraSettings

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $settings.cameraEnabled) {
                Label("Camera", systemImage: "video")
            }
            .onChange(of: settings.cameraEnabled) {
                if settings.cameraEnabled {
                    Task { await settings.requestCameraAccess() }
                }
            }

            if settings.cameraEnabled {
                switch settings.cameraAccess {
                case .denied, .restricted:
                    Button("Allow in System Settings…", action: settings.openCameraSettings)
                        .buttonStyle(.link)
                default:
                    Picker("Camera", selection: $settings.selectedCameraID) {
                        if settings.cameras.isEmpty {
                            Text("No cameras").tag(String?.none)
                        }
                        ForEach(settings.cameras) { camera in
                            Text(camera.name).tag(Optional(camera.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
            }
        }
    }
}
