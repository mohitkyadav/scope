//
//  EditorTimeline.swift
//  Scope
//

import SwiftUI
import UniformTypeIdentifiers

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

    static let headerWidth: CGFloat = 175
    static let rulerHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            TimelineToolbar(model: model, magnification: $magnification, undoManager: undoManager)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                TimelineHeaders(model: model, rows: rows, undoManager: undoManager)
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
    @State private var isImportingAudio = false
    @State private var isImportingWebcam = false

    var body: some View {
        // On narrower windows, drop the Zoom and Note labels first, then the timeline zoom slider,
        // rather than squashing anything.
        ViewThatFits(in: .horizontal) {
            row(labelled: true, showsZoomSlider: true)
            row(labelled: false, showsZoomSlider: true)
            row(labelled: false, showsZoomSlider: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Color.clear.fileImporter(isPresented: $isImportingAudio, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result {
                    Task { await model.importAudio(from: url, undoManager: undoManager) }
                }
            }
        }
        .background {
            Color.clear.fileImporter(isPresented: $isImportingWebcam, allowedContentTypes: [.movie]) { result in
                if case .success(let url) = result {
                    Task { await model.importWebcam(from: url, undoManager: undoManager) }
                }
            }
        }
    }

    private func row(labelled: Bool, showsZoomSlider: Bool) -> some View {
        HStack(spacing: 14) {
            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.scopePill))
                    .overlay(Circle().strokeBorder(Color.scopeStroke))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(model.isEditingText ? nil : KeyboardShortcut(.space, modifiers: []))
            .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

            HStack(spacing: 4) {
                Text(model.currentTime.timecodeString)
                    .fontWeight(.semibold)
                Text("/ \(model.duration.timecodeString)")
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()

            Spacer(minLength: 8)

            PillGroup {
                splitButton
                deleteButton
            }
            .labelStyle(.iconOnly)

            PillGroup {
                speedMenu
            }

            PillGroup {
                Group {
                    addZoomButton
                    addNoteButton
                }
                .labelStyle(labelled ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
                addAudioButton
                    .labelStyle(.iconOnly)
                webcamButton
                    .labelStyle(.iconOnly)
            }

            if showsZoomSlider {
                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Image(systemName: "minus.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Slider(value: $magnification, in: 1...20)
                        .frame(width: 90)
                        .help("Zoom the timeline")
                    Image(systemName: "plus.magnifyingglass")
                        .foregroundStyle(.secondary)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private var splitButton: some View {
        Button {
            model.splitClip(at: model.currentTime, undoManager: undoManager)
        } label: {
            Label("Split", systemImage: "scissors")
        }
        .keyboardShortcut("b", modifiers: .command)
        .help("Split the clip at the playhead (⌘B)")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            model.deleteSelection(undoManager: undoManager)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .keyboardShortcut(model.isEditingText ? nil : KeyboardShortcut(.delete, modifiers: []))
        .disabled(!model.canDeleteSelection)
        .help("Delete the selected item (Delete)")
    }

    private var speedMenu: some View {
        Menu {
            ForEach(EditorModel.speeds, id: \.self) { speed in
                Button {
                    if let clip = model.speedTarget {
                        model.setSpeed(speed, ofClip: clip.id, undoManager: undoManager)
                    }
                } label: {
                    if model.speedTarget?.speed == speed {
                        Label(String(format: "%g×", speed), systemImage: "checkmark")
                    } else {
                        Text(String(format: "%g×", speed))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                Text(model.speedTarget.map { String(format: "%g×", $0.speed) } ?? "1×")
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.speedTarget == nil)
        .help("Play the selected clip, or the clip at the playhead, faster or slower. Split first to change part of a clip.")
        .accessibilityLabel("Speed")
    }

    private var addZoomButton: some View {
        Button {
            model.addZoom(undoManager: undoManager)
        } label: {
            Label("Zoom", systemImage: "plus.magnifyingglass")
        }
        .help("Add a zoom at the playhead")
    }

    private var addNoteButton: some View {
        Button {
            model.addNote(undoManager: undoManager)
        } label: {
            Label("Note", systemImage: "text.bubble")
        }
        .help("Add a note at the playhead")
    }

    private var addAudioButton: some View {
        Button {
            isImportingAudio = true
        } label: {
            Label("Add Audio", systemImage: "music.note")
        }
        .help("Add music or a voice-over at the playhead")
    }

    private var webcamButton: some View {
        Button {
            isImportingWebcam = true
        } label: {
            Label("Webcam Video", systemImage: "video.badge.plus")
        }
        .help("Use another video for the webcam bubble, starting at the playhead")
    }
}

/// Track names down the left side.
private struct TimelineHeaders: View {
    let model: EditorModel
    let rows: [TimelineRow]
    let undoManager: UndoManager?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: EditorTimeline.rulerHeight)
            ForEach(rows, id: \.self) { row in
                Group {
                    if let mix = model.mix(for: row) {
                        AudioRowHeader(title: title(for: row), icon: icon(for: row), mix: mix) { mix, isDragging, actionName in
                            model.setMix(mix, for: row, actionName: actionName, undoManager: undoManager, isDragging: isDragging)
                        } onDragEnd: {
                            model.endGesture("Change Volume", undoManager: undoManager)
                        }
                    } else {
                        Label(title(for: row), systemImage: icon(for: row))
                            .font(.callout)
                            .lineLimit(1)
                    }
                }
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

/// An audio row's name with its mute button and volume slider.
private struct AudioRowHeader: View {
    let title: String
    let icon: String
    let mix: TrackMix
    let onChange: (TrackMix, _ isDragging: Bool, _ actionName: String) -> Void
    let onDragEnd: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                var mix = mix
                mix.muted.toggle()
                onChange(mix, false, mix.muted ? "Mute" : "Unmute")
            } label: {
                Image(systemName: mix.muted ? "speaker.slash.fill" : icon)
                    .foregroundStyle(mix.muted ? Color.secondary : Color.primary)
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help(mix.muted ? "Unmute \(title)" : "Mute \(title)")

            Text(title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(mix.muted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Slider(
                value: Binding(
                    get: { mix.volume },
                    set: { volume in
                        var mix = mix
                        mix.volume = volume
                        onChange(mix, true, "Change Volume")
                    }
                ),
                in: 0...2
            ) { isEditing in
                if !isEditing {
                    onDragEnd()
                }
            }
            .controlSize(.mini)
            .frame(width: 44)
            .disabled(mix.muted)
            .help("Volume: \(Int((mix.volume * 100).rounded()))%")
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
                        if row == .notes, model.edits.notes.isEmpty {
                            Text("Click Note to add one at the playhead")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 10)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(height: row.height)
                    .overlay(alignment: .bottom) { Divider().opacity(0.5) }
                }
            }

            VStack(spacing: 0) {
                Capsule()
                    .fill(.red)
                    .frame(width: 11, height: 18)
                Rectangle()
                    .fill(.red)
                    .frame(width: 2)
            }
            .offset(x: model.currentTime * pointsPerSecond - 5.5, y: 3)
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
                    color: .scopeClip,
                    isSelected: model.selection == .clip(clip.id),
                    canMove: false,
                    selectionColor: .scopeSelection,
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
                    title: String(format: "%.2g×", zoom.level ?? model.settings.zoomLevel),
                    color: .scopeZoom,
                    isSelected: model.selection == .zoom(zoom.id),
                    canMove: true,
                    icon: "magnifyingglass",
                    isCapsule: true,
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
                EditableBlock(
                    title: note.text,
                    color: .scopeNote,
                    isSelected: model.selection == .note(note.id),
                    canMove: true,
                    icon: "text.bubble",
                    isCapsule: true,
                    onSelect: { model.selection = .note(note.id) },
                    onDrag: { edit, points in model.dragNote(note.id, edit, by: points / pointsPerSecond) },
                    onDragEnd: { edit in model.endGesture(edit == .move ? "Move Note" : "Resize Note", undoManager: undoManager) }
                )
                .frame(width: max((end - start) * pointsPerSecond, 12))
                .offset(x: start * pointsPerSecond)
            }

        case .webcam:
            if let range = model.webcamRange {
                let start = map.outputTime(at: range.lowerBound)
                let end = map.outputTime(at: range.upperBound)
                EditableBlock(
                    title: nil,
                    color: .teal,
                    isSelected: false,
                    canMove: true,
                    canTrim: false,
                    onSelect: {},
                    onDrag: { _, points in model.dragWebcam(by: points / pointsPerSecond) },
                    onDragEnd: { _ in model.endGesture("Move Webcam", undoManager: undoManager) }
                )
                .frame(width: max((end - start) * pointsPerSecond, 12))
                .offset(x: start * pointsPerSecond)
                .help("Drag to line the webcam up with the recording")
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
                // Only the part inside the video plays.
                let start = max(clip.offset, 0)
                let end = min(clip.offset + clip.duration, model.duration)
                EditableBlock(
                    title: clip.name,
                    color: .green,
                    isSelected: model.selection == .audio(id),
                    canMove: true,
                    canTrim: false,
                    onSelect: { model.selection = .audio(id) },
                    onDrag: { _, points in model.dragAudio(id, by: points / pointsPerSecond) },
                    onDragEnd: { _ in model.endGesture("Move Audio", undoManager: undoManager) }
                )
                .frame(width: max((end - start) * pointsPerSecond, 12))
                .offset(x: start * pointsPerSecond)
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
    var canTrim = true
    var icon: String?
    var isCapsule = false
    var selectionColor = Color.white
    let onSelect: () -> Void
    let onDrag: (BlockEdit, Double) -> Void
    let onDragEnd: (BlockEdit) -> Void

    @State private var isHovering = false

    var body: some View {
        TimelineBlock(title: title, color: color, isSelected: isSelected, icon: icon, isCapsule: isCapsule, selectionColor: selectionColor)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .gesture(canMove ? drag(.move) : nil)
            .overlay(alignment: .leading) {
                if canTrim { handle(.trimStart) }
            }
            .overlay(alignment: .trailing) {
                if canTrim { handle(.trimEnd) }
            }
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
        // Measured in window coordinates: the block moves while it's dragged, so distances measured
        // on the block itself would shrink and it would fall behind the pointer.
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
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
    var icon: String?
    /// Zooms and notes are pills; clips and audio are rounded bars.
    var isCapsule = false
    var selectionColor = Color.white

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: isCapsule ? 100 : 7, style: .continuous)
        shape
            .fill(color.opacity(isSelected || isCapsule ? 0.95 : 0.75))
            .overlay {
                shape.strokeBorder(isSelected ? selectionColor : Color.white.opacity(0.12), lineWidth: isSelected ? 3 : 1)
            }
            .overlay(alignment: .leading) {
                if title != nil || icon != nil {
                    HStack(spacing: 4) {
                        if let icon {
                            Image(systemName: icon)
                                .font(.caption2.weight(.bold))
                        }
                        if let title {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                }
            }
            .padding(.vertical, isCapsule ? 4 : 3)
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
