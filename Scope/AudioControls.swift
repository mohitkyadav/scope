//
//  AudioControls.swift
//  Scope
//

import AVFoundation
import SwiftUI

struct AudioControls: View {
    @Bindable var settings: AudioSettings
    let microphoneLevel: Float
    let systemAudioLevel: Float

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $settings.microphoneEnabled) {
                Label("Microphone", systemImage: "mic")
            }
            .onChange(of: settings.microphoneEnabled) {
                if settings.microphoneEnabled {
                    Task { await settings.requestMicrophoneAccess() }
                }
            }

            if settings.microphoneEnabled {
                switch settings.microphoneAccess {
                case .denied, .restricted:
                    Button("Allow in System Settings…", action: settings.openMicrophoneSettings)
                        .buttonStyle(.link)
                default:
                    Picker("Microphone", selection: $settings.selectedMicrophoneID) {
                        if settings.microphones.isEmpty {
                            Text("No microphones").tag(String?.none)
                        }
                        ForEach(settings.microphones) { microphone in
                            Text(microphone.name).tag(Optional(microphone.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)

                    LevelMeter(level: microphoneLevel)
                }
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            Toggle(isOn: $settings.systemAudioEnabled) {
                Label("System audio", systemImage: "speaker.wave.2")
            }

            if settings.systemAudioEnabled {
                LevelMeter(level: systemAudioLevel)
            }
        }
    }
}
