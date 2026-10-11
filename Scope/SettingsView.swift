//
//  SettingsView.swift
//  Scope
//

import AppKit
import SwiftUI

/// Scope › Settings.
struct SettingsView: View {
    @AppStorage(RecordingPreferences.countdownKey) private var countdown = 3
    @AppStorage(RecordingPreferences.frameRateKey) private var frameRate = 60

    var body: some View {
        Form {
            Section("Recording") {
                Picker("Countdown", selection: $countdown) {
                    Text("Off").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                }
                Picker("Frame rate", selection: $frameRate) {
                    Text("60 fps").tag(60)
                    Text("30 fps").tag(30)
                }
                LabeledContent("Stop recording", value: "\(Recorder.stopShortcut) from any app")
            }

            Section("Saving") {
                LabeledContent("Recordings and exports") {
                    HStack {
                        Text("Downloads")
                        Button("Show in Finder") {
                            NSWorkspace.shared.open(RecordingLibrary.folder)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }
}

#Preview {
    SettingsView()
}
