//
//  EditorView.swift
//  Scope
//

import SwiftUI

struct EditorView: View {
    static let windowID = "editor"

    @State private var model: EditorModel
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

                        Divider()

                        EditorTimeline(model: model)
                    }

                    Divider()

                    EditorInspector(
                        settings: $model.settings,
                        zoomCount: model.edits.zooms.count,
                        hasWebcam: model.hasWebcam,
                        suggestZooms: { model.suggestZooms(undoManager: undoManager) }
                    )
                        .frame(width: 300)
                }
            }
        }
        .frame(minWidth: 960, minHeight: 680)
        .navigationTitle(model.project.name)
        .task {
            await model.load()
        }
        .onDisappear {
            model.close()
        }
    }
}
