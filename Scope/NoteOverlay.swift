//
//  NoteOverlay.swift
//  Scope
//

import AVFoundation
import SwiftUI

/// An outline around the selected note in the preview, which can be dragged to move the note.
struct NoteOverlay: View {
    let model: EditorModel
    let note: Note
    let undoManager: UndoManager?

    @State private var dragStart: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let canvas = model.canvasSize
            let video = AVMakeRect(aspectRatio: canvas, insideRect: CGRect(origin: .zero, size: geometry.size))
            let scale = video.width / max(canvas.width, 1)
            let size = model.noteSize(note)
            let center = FrameRenderer.noteCenter(note, size: size, canvas: canvas)

            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: size.width * scale + 8, height: size.height * scale + 8)
                .contentShape(Rectangle())
                .position(x: video.minX + center.x * scale, y: video.minY + center.y * scale)
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { drag in
                            let start = dragStart ?? CGPoint(x: center.x / canvas.width, y: center.y / canvas.height)
                            dragStart = start
                            model.updateNote(note.id) { note in
                                note.x = min(max(start.x + drag.translation.width / video.width, 0), 1)
                                note.y = min(max(start.y + drag.translation.height / video.height, 0), 1)
                            }
                        }
                        .onEnded { _ in
                            dragStart = nil
                            model.endGesture("Move Note", undoManager: undoManager)
                        }
                )
                .help("Drag to move the note")
                .accessibilityLabel("Note: \(note.text)")
                .accessibilityHint("Drag to move it")
        }
    }
}
