//
//  EditorView.swift
//  Scope
//

import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    static let windowID = "editor"

    @State private var model: EditorModel
    @State private var tab = InspectorTab.style
    @State private var isExporting = false
    @State private var isChoosingBackground = false
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var renameError: String?
    @Environment(\.undoManager) private var undoManager
    /// Called with the project's new place when it's renamed, so the window keeps track of it.
    private let onMove: (URL) -> Void

    init(project: ScopeProject, onMove: @escaping (URL) -> Void = { _ in }) {
        _model = State(initialValue: EditorModel(project: project))
        self.onMove = onMove
    }

    var body: some View {
        Group {
            if let errorMessage = model.errorMessage {
                ContentUnavailableView(
                    "Can't Open Recording",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                VStack(spacing: 0) {
                    preview
                    EditorTimeline(model: model)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 640)
        .inspector(isPresented: .constant(model.errorMessage == nil)) {
            inspector
                // A fixed width, so the panel doesn't grow wider the first time something changes in it.
                .inspectorColumnWidth(330)
                .toolbar {
                    // Keeps the tabs and Export against the right edge.
                    TrailingSpace()
                    ToolbarItem {
                        Picker("Settings", selection: $tab) {
                            ForEach(InspectorTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    ToolbarItem {
                        Button {
                            isExporting = true
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("e")
                        .help("Export as a video or GIF (⌘E)")
                        .disabled(model.scene == nil)
                    }
                }
        }
        .toolbar {
            EditorTitleToolbarItem(title: title, subtitle: subtitle) {
                newName = model.project.name
                isRenaming = true
            }
            TrailingSpace()
            ToolbarItem(placement: .primaryAction) {
                UndoRedoButtons(undoManager: undoManager)
            }
        }
        .toolbar(removing: .title)
        .navigationTitle(model.project.name)
        .onChange(of: model.selection) {
            // Selecting a zoom brings up its settings.
            if case .zoom = model.selection {
                tab = .zoom
            }
        }
        .onChange(of: model.project.url) {
            onMove(model.project.url)
        }
        .alert("Rename Project", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") {
                do {
                    try model.rename(to: newName)
                } catch {
                    renameError = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The project is renamed in Finder too.")
        }
        .alert("Couldn't Rename the Project", isPresented: Binding(get: { renameError != nil }, set: { if !$0 { renameError = nil } })) {
            Button("OK") {}
        } message: {
            Text(renameError ?? "")
        }
        .sheet(isPresented: $isExporting) {
            ExportSheet(model: model)
        }
        .fileImporter(isPresented: $isChoosingBackground, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                Task { await model.chooseBackgroundImage(from: url) }
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

    /// The video, framed on a darker stage, with handles for the camera bubble and the selected note.
    private var preview: some View {
        ZStack {
            Color.scopeStage
            PlayerView(player: model.player)
                .aspectRatio(model.canvasSize.width > 0 ? model.canvasSize : CGSize(width: 16, height: 9), contentMode: .fit)
                .overlay {
                    if model.hasWebcam, model.settings.webcamVisible, model.isWebcamShowing {
                        BubbleOverlay(settings: $model.settings, canvasSize: model.canvasSize)
                    }
                }
                .overlay {
                    if let note = model.selectedNote, model.isShowing(note) {
                        NoteOverlay(model: model, note: note, undoManager: undoManager)
                    }
                }
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                .padding(28)
        }
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.scopeStroke))
        .padding([.horizontal, .top], 16)
        .padding(.bottom, 8)
    }

    private var inspector: some View {
        EditorInspector(
            tab: tab,
            settings: $model.settings,
            zoomCount: model.edits.zooms.count,
            hasWebcam: model.hasWebcam,
            suggestZooms: { model.suggestZooms(undoManager: undoManager) },
            selectedZoom: model.selectedZoom,
            onZoomChange: { zoom, isDragging, actionName in
                model.updateZoom(zoom.id, actionName: actionName, undoManager: undoManager, isDragging: isDragging) { segment in
                    segment.level = zoom.level
                    segment.transition = zoom.transition
                    segment.followsCursor = zoom.followsCursor
                }
            },
            onZoomSliderReleased: { actionName in
                model.endGesture(actionName, undoManager: undoManager)
            },
            backgroundImageID: model.backgroundImageID,
            chooseBackgroundImage: { isChoosingBackground = true },
            useBackgroundImage: { model.useBackgroundImage($0) },
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
            },
            onHexEditingChanged: { model.isEditingText = $0 }
        )
    }

    /// The project's name, or "Today at 18:42" if it hasn't been given one, like the main window's list.
    private var title: String {
        guard model.project.hasRecordedName, let date = model.recordingDate else { return model.project.name }
        return date.recordingTitle
    }

    /// "0:07 · 3840 × 2160 · Edited", after when it was recorded if the title is a name.
    private var subtitle: String {
        var parts = [model.duration.clockString]
        if !model.project.hasRecordedName, let date = model.recordingDate {
            parts.insert(date.recordingTitle, at: 0)
        }
        if model.canvasSize.width > 0 {
            parts.append("\(Int(model.canvasSize.width)) × \(Int(model.canvasSize.height))")
        }
        parts.append(model.hasSavedEdits ? "Edited" : "Not edited")
        return parts.joined(separator: " · ")
    }
}

/// The project's title and details at the top left of the editor.
private struct EditorTitleToolbarItem: ToolbarContent {
    let title: String
    let subtitle: String
    let rename: () -> Void

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) { label }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { label }
        }
    }

    private var label: some View {
        Button(action: rename) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.leading, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Rename the project")
    }
}

/// Undo and Redo in one pill, kept up to date as the undo history changes.
private struct UndoRedoButtons: View {
    let undoManager: UndoManager?
    @State private var canUndo = false
    @State private var canRedo = false

    var body: some View {
        ControlGroup {
            Button {
                undoManager?.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndo)
            .help(canUndo ? "Undo \(undoManager?.undoActionName ?? "") (⌘Z)" : "Nothing to undo")

            Button {
                undoManager?.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!canRedo)
            .help(canRedo ? "Redo \(undoManager?.redoActionName ?? "") (⇧⌘Z)" : "Nothing to redo")
        }
        .task(id: undoManager.map(ObjectIdentifier.init)) {
            refresh()
            // The undo manager posts a checkpoint whenever its history may have changed.
            for await _ in NotificationCenter.default.notifications(named: .NSUndoManagerCheckpoint, object: undoManager) {
                refresh()
            }
        }
    }

    private func refresh() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }
}
