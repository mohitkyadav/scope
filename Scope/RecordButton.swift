//
//  RecordButton.swift
//  Scope
//

import SwiftUI

struct RecordButton: View {
    let state: Recorder.State
    let elapsed: TimeInterval
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                switch state {
                case .idle:
                    Label("Record", systemImage: "record.circle.fill")
                case .countingDown:
                    Label("Cancel", systemImage: "xmark.circle.fill")
                case .recording, .stopping:
                    Label("Stop  \(elapsed.clockString)", systemImage: "stop.circle.fill")
                        .monospacedDigit()
                }
            }
            .font(.title2.weight(.semibold))
            .frame(maxWidth: 240)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(state == .idle ? .red : .gray)
    }
}

#Preview {
    VStack {
        RecordButton(state: .idle, elapsed: 0) {}
        RecordButton(state: .countingDown, elapsed: 0) {}
        RecordButton(state: .recording, elapsed: 75) {}
    }
    .padding()
}
