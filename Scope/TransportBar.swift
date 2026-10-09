//
//  TransportBar.swift
//  Scope
//

import SwiftUI

/// Play/pause, the current time and a scrubber.
struct TransportBar: View {
    let model: EditorModel
    @State private var scrubTime: TimeInterval?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.space, modifiers: [])
            .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")

            Text((scrubTime ?? model.currentTime).clockString)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { scrubTime ?? model.currentTime },
                    set: { time in
                        scrubTime = time
                        model.seek(to: time)
                    }
                ),
                in: 0...max(model.duration, 0.01)
            ) { isEditing in
                if !isEditing {
                    scrubTime = nil
                }
            }

            Text(model.duration.clockString)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
