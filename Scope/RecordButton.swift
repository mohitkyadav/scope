//
//  RecordButton.swift
//  Scope
//

import SwiftUI

/// The big red record button: a white dot and "Record", or "Stop" with the time while recording.
struct RecordButton: View {
    let state: Recorder.State
    let elapsed: TimeInterval
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                Text(title)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.leading, 10)
            .padding(.trailing, 22)
            .padding(.vertical, 9)
            .background(Capsule().fill(fill))
            .shadow(color: state == .idle && isEnabled ? Color.scopeRecord.opacity(0.45) : .clear, radius: 14, y: 4)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .idle:
            Circle().fill(.white).frame(width: 22, height: 22)
        case .countingDown:
            Image(systemName: "xmark").font(.headline).frame(width: 22, height: 22)
        case .recording, .stopping:
            RoundedRectangle(cornerRadius: 4).fill(.white).frame(width: 16, height: 16).frame(width: 22, height: 22)
        }
    }

    private var title: String {
        switch state {
        case .idle: "Record"
        case .countingDown: "Cancel"
        case .recording, .stopping: "Stop  \(elapsed.clockString)"
        }
    }

    private var fill: Color {
        state == .countingDown ? Color.gray : Color.scopeRecord
    }
}

#Preview {
    VStack(spacing: 20) {
        RecordButton(state: .idle, elapsed: 0) {}
        RecordButton(state: .countingDown, elapsed: 0) {}
        RecordButton(state: .recording, elapsed: 75) {}
    }
    .padding(40)
}
