//
//  RecordButton.swift
//  Scope
//

import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let elapsed: TimeInterval
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isRecording {
                    Label("Stop  \(elapsed.clockString)", systemImage: "stop.circle.fill")
                        .monospacedDigit()
                } else {
                    Label("Record", systemImage: "record.circle.fill")
                }
            }
            .font(.title2.weight(.semibold))
            .frame(maxWidth: 240)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(isRecording ? .gray : .red)
    }
}

#Preview {
    VStack {
        RecordButton(isRecording: false, elapsed: 0) {}
        RecordButton(isRecording: true, elapsed: 75) {}
    }
    .padding()
}
