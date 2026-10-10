//
//  EditorView.swift
//  Scope
//

import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    static let windowID = "editor"

    @State private var model: EditorModel
    @State private var isExporting = false
    @State private var isChoosingBackground = false
    @Environment(\.undoManager) private var undoManager

    init(project: ScopeProject) {
        _model = State(initialValue: EditorModel(project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = model.errorMessage {
                ContentUnavailableView(
                    "Can't Open Recording",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        PlayerView(player: model.player)
                            .background(.black)
                            .overlay {
                                if model.hasWebcam, model.settings.webcamVisible {
                                    BubbleOverlay(settings: $model.settings, canvasSize: model.canvasSize)
                                }
                            }
                            .overlay {
                                if let note = model.selectedNote, model.isShowing(note) {
                                    NoteOverlay(model: model, note: note, undoManager: undoManager)
                                }
                            }

                        Divider()

                        EditorTimeline(model: model)
                    }

                    Divider()

                    EditorInspector(
                        settings: $model.settings,
                        zoomCount: model.edits.zooms.count,
                        hasWebcam: model.hasWebcam,
                        suggestZooms: { model.suggestZooms(undoManager: undoManager) },
                        backgroundThumbnail: model.backgroundThumbnail,
                        chooseBackgroundImage: { isChoosingBackground = true },
                        noteText: model.selectedNote.map { note in
                            Binding(
                                get: { model.selectedNote?.text ?? note.text },
                                set: { text in model.updateNote(note.id) { $0.text = text } }
                            )
                        },
                        onNoteEditingChanged: { isEditing in
                            model.isEditingText = isEditing
                            if !isEditing {
                                model.endGesture("Edit Note", undoManager: undoManager)
                            }
                        }
                    )
                        .frame(width: 300)
                }
            }
        }
        .frame(minWidth: 960, minHeight: 680)
        .navigationTitle(model.project.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isExporting = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e")
                .help("Export as a video or GIF (⌘E)")
                .disabled(model.scene == nil)
            }
        }
        .sheet(isPresented: $isExporting) {
            ExportSheet(model: model)
        }
        .fileImporter(isPresented: $isChoosingBackground, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                model.chooseBackgroundImage(from: url)
            }
        }
        .task {
            RecentProjects.shared.add(model.project.url)
            await model.load()
        }
        .onDisappear {
            model.close()
            // The project is closed, so its edits can't be undone any more.
            undoManager?.removeAllActions(withTarget: model)
        }
    }
}
