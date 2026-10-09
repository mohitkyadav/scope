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

            VStack(spacing: 2) {
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

                ZoomMarkers(segments: model.zoomSegments, duration: model.duration)
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

/// A thin strip under the scrubber showing where the preview zooms in.
private struct ZoomMarkers: View {
    let segments: [ZoomSegment]
    let duration: TimeInterval

    /// Roughly where the slider's track starts and ends inside its frame.
    private let inset: CGFloat = 9

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - inset * 2, 0)
            ForEach(segments) { segment in
                Capsule()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: max(width * (segment.end - segment.start) / max(duration, 0.01), 3), height: 4)
                    .offset(x: inset + width * segment.start / max(duration, 0.01))
            }
        }
        .frame(height: 4)
        .help("Zoomed in")
        .accessibilityLabel("\(segments.count) zoom segments")
    }
}
