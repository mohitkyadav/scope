//
//  EditorTimeline.swift
//  Scope
//

import SwiftUI

/// The rows of the timeline, top to bottom.
enum TimelineRow: Hashable {
    case video
    case zooms
    case notes
    case webcam
    case recordedAudio(Int)
    case importedAudio(UUID)

    var height: CGFloat {
        switch self {
        case .video: 48
        case .zooms, .notes, .webcam: 26
        case .recordedAudio, .importedAudio: 30
        }
    }
}

/// The timeline under the preview: a toolbar, a ruler with the playhead, and one row per track.
/// Times on it are times in the final video.
struct EditorTimeline: View {
    let model: EditorModel
    /// 1 fits the whole video in the visible width; higher values zoom in.
    @State private var magnification = 1.0
    @Environment(\.undoManager) private var undoManager

    static let headerWidth: CGFloat = 150
    static let rulerHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            TimelineToolbar(model: model, magnification: $magnification, undoManager: undoManager)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                TimelineHeaders(model: model, rows: rows)
                    .frame(width: Self.headerWidth)

                Divider()

                GeometryReader { geometry in
                    let fitted = (geometry.size.width - 24) / max(model.duration, 0.1)
                    let pointsPerSecond = fitted * magnification
                    ScrollView(.horizontal) {
                        TimelineTracks(model: model, rows: rows, pointsPerSecond: pointsPerSecond, undoManager: undoManager)
                            .frame(width: max(model.duration * pointsPerSecond + 24, geometry.size.width), alignment: .leading)
                    }
                    .scrollIndicators(magnification > 1 ? .visible : .hidden)
                }
            }
            .frame(height: Self.rulerHeight + rows.reduce(0) { $0 + $1.height } + 8)
        }
        .background(.background)
    }

    private var rows: [TimelineRow] {
        var rows: [TimelineRow] = [.video, .zooms, .notes]
        if model.hasWebcam {
            rows.append(.webcam)
        }
        rows += model.recordedAudioNames.indices.map { .recordedAudio($0) }
        rows += model.edits.importedAudio.map { .importedAudio($0.id) }
        return rows
    }
}

/// Play/pause, the time, and how far the timeline is zoomed in.
private struct TimelineToolbar: View {
    let model: EditorModel
    @Binding var magnification: Double
    let undoManager: UndoManager?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.space, modifiers: [])
            .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")

            Text("\(model.currentTime.timecodeString) / \(model.duration.timecodeString)")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Divider().frame(height: 18)

            Button {
                model.splitClip(at: model.currentTime, undoManager: undoManager)
            } label: {
                Label("Split", systemImage: "scissors")
            }
            .keyboardShortcut("b", modifiers: .command)
            .help("Split the clip at the playhead (⌘B)")

            Button(role: .destructive) {
                model.deleteSelection(undoManager: undoManager)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(!model.canDeleteSelection)
            .help("Delete the selected item (Delete)")

            Button {
                model.addZoom(undoManager: undoManager)
            } label: {
                Label("Add Zoom", systemImage: "plus.magnifyingglass")
            }
            .help("Add a zoom at the playhead")

            Spacer()

            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
            Slider(value: $magnification, in: 1...20)
                .frame(width: 120)
                .help("Zoom the timeline")
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Track names down the left side.
private struct TimelineHeaders: View {
    let model: EditorModel
    let rows: [TimelineRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: EditorTimeline.rulerHeight)
            ForEach(rows, id: \.self) { row in
                Label(title(for: row), systemImage: icon(for: row))
                    .font(.callout)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: row.height)
            }
        }
    }

    private func title(for row: TimelineRow) -> String {
        switch row {
        case .video: "Video"
        case .zooms: "Zoom"
        case .notes: "Notes"
        case .webcam: "Webcam"
        case .recordedAudio(let index): model.recordedAudioNames[safe: index] ?? "Audio"
        case .importedAudio(let id): model.edits.importedAudio.first { $0.id == id }?.name ?? "Audio"
        }
    }

    private func icon(for row: TimelineRow) -> String {
        switch row {
        case .video: "film"
        case .zooms: "plus.magnifyingglass"
        case .notes: "text.bubble"
        case .webcam: "video"
        case .recordedAudio(let index): model.recordedAudioNames[safe: index] == "Microphone" ? "mic" : "speaker.wave.2"
        case .importedAudio: "music.note"
        }
    }
}

/// The ruler, the items on each row, and the playhead.
private struct TimelineTracks: View {
    let model: EditorModel
    let rows: [TimelineRow]
    let pointsPerSecond: Double
    let undoManager: UndoManager?

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                TimelineRuler(duration: model.duration, pointsPerSecond: pointsPerSecond)
                    .frame(height: EditorTimeline.rulerHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { drag in
                            model.seek(to: drag.location.x / pointsPerSecond)
                        }
                    )

                ForEach(rows, id: \.self) { row in
                    ZStack(alignment: .leading) {
                        // Clicking empty space moves the playhead there and clears the selection.
                        Color.primary.opacity(0.03)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                model.selection = nil
                                model.seek(to: location.x / pointsPerSecond)
                            }
                        items(for: row)
                    }
                    .frame(height: row.height)
                    .overlay(alignment: .bottom) { Divider().opacity(0.5) }
                }
            }

            Rectangle()
                .fill(.red)
                .frame(width: 2)
                .offset(x: model.currentTime * pointsPerSecond - 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func items(for row: TimelineRow) -> some View {
        let map = model.timeMap
        switch row {
        case .video:
            ForEach(Array(model.edits.clips.enumerated()), id: \.element.id) { index, clip in
                EditableBlock(
                    title: clip.speed == 1 ? nil : String(format: "%g×", clip.speed),
                    color: .accentColor,
                    isSelected: model.selection == .clip(clip.id),
                    canMove: false,
                    onSelect: { model.selection = .clip(clip.id) },
                    onDrag: { edit, points in model.dragClip(clip.id, edit, by: points / pointsPerSecond) },
                    onDragEnd: { _ in model.endGesture("Trim Clip", undoManager: undoManager) }
                )
                .frame(width: max(clip.duration * pointsPerSecond, 2))
                .offset(x: map.outputStarts[index] * pointsPerSecond)
            }

        case .zooms:
            ForEach(model.edits.zooms) { zoom in
                let start = map.outputTime(at: zoom.start)
                let end = map.outputTime(at: zoom.end)
                EditableBlock(
                    title: nil,
                    color: .purple,
                    isSelected: model.selection == .zoom(zoom.id),
                    canMove: true,
                    onSelect: { model.selection = .zoom(zoom.id) },
                    onDrag: { edit, points in model.dragZoom(zoom.id, edit, by: points / pointsPerSecond) },
                    onDragEnd: { edit in model.endGesture(edit == .move ? "Move Zoom" : "Resize Zoom", undoManager: undoManager) }
                )
                .frame(width: max((end - start) * pointsPerSecond, 12))
                .offset(x: start * pointsPerSecond)
            }

        case .notes:
            ForEach(model.edits.notes) { note in
                let start = map.outputTime(at: note.start)
                let end = map.outputTime(at: note.end)
                TimelineBlock(title: note.text, color: .orange, isSelected: model.selection == .note(note.id))
                    .frame(width: max((end - start) * pointsPerSecond, 2))
                    .offset(x: start * pointsPerSecond)
            }

        case .webcam:
            if let range = model.scene?.webcamRange {
                let start = map.outputTime(at: range.lowerBound)
                let end = map.outputTime(at: range.upperBound)
                TimelineBlock(title: nil, color: .teal, isSelected: false)
                    .frame(width: max((end - start) * pointsPerSecond, 2))
                    .offset(x: start * pointsPerSecond)
            }

        case .recordedAudio:
            // The recording's audio follows its clips.
            ForEach(Array(model.edits.clips.enumerated()), id: \.element.id) { index, clip in
                TimelineBlock(title: nil, color: .green, isSelected: false)
                    .frame(width: max(clip.duration * pointsPerSecond, 2))
                    .offset(x: map.outputStarts[index] * pointsPerSecond)
            }

        case .importedAudio(let id):
            if let clip = model.edits.importedAudio.first(where: { $0.id == id }) {
                TimelineBlock(title: clip.name, color: .green, isSelected: model.selection == .audio(id))
                    .frame(width: max(min(clip.duration, model.duration - clip.offset) * pointsPerSecond, 2))
                    .offset(x: clip.offset * pointsPerSecond)
            }
        }
    }
}

/// A timeline item that can be selected, trimmed from either edge and, if `canMove`, dragged along.
/// Drags report how far they've gone in points since they began.
struct EditableBlock: View {
    let title: String?
    let color: Color
    let isSelected: Bool
    let canMove: Bool
    let onSelect: () -> Void
    let onDrag: (BlockEdit, Double) -> Void
    let onDragEnd: (BlockEdit) -> Void

    @State private var isHovering = false

    var body: some View {
        TimelineBlock(title: title, color: color, isSelected: isSelected)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .gesture(canMove ? drag(.move) : nil)
            .overlay(alignment: .leading) { handle(.trimStart) }
            .overlay(alignment: .trailing) { handle(.trimEnd) }
            .onHover { isHovering = $0 }
    }

    private func handle(_ edit: BlockEdit) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(isHovering || isSelected ? 0.9 : 0))
            .frame(width: 4)
            .padding(.vertical, 8)
            .frame(width: 10)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(drag(edit))
    }

    private func drag(_ edit: BlockEdit) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { drag in
                onSelect()
                onDrag(edit, drag.translation.width)
            }
            .onEnded { _ in onDragEnd(edit) }
    }
}

/// One item on a row: a rounded bar with an optional label.
struct TimelineBlock: View {
    let title: String?
    let color: Color
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color.opacity(isSelected ? 0.9 : 0.55))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : color, lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .leading) {
                if let title {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.vertical, 3)
    }
}

/// Seconds along the top of the timeline.
private struct TimelineRuler: View {
    let duration: Double
    let pointsPerSecond: Double

    var body: some View {
        Canvas { context, size in
            // Label every `step` seconds, choosing a step that leaves room for the labels.
            let steps = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
            let step = steps.first { $0 * pointsPerSecond >= 64 } ?? 600
            var time = 0.0
            while time <= duration + 0.001 {
                let x = time * pointsPerSecond
                context.fill(Path(CGRect(x: x, y: size.height - 8, width: 1, height: 8)), with: .color(.secondary))
                // Skip a label that would run off the end.
                if x + 44 <= size.width {
                    let label = step < 1 ? time.timecodeString : time.clockString
                    context.draw(Text(label).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: x + 3, y: 2), anchor: .topLeading)
                }
                // Small ticks in between.
                for minor in 1..<4 {
                    let minorX = x + Double(minor) * step / 4 * pointsPerSecond
                    if minorX < size.width {
                        context.fill(Path(CGRect(x: minorX, y: size.height - 4, width: 1, height: 4)), with: .color(.secondary.opacity(0.6)))
                    }
                }
                time += step
            }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
