//
//  EditorView.swift
//  Scope
//

import SwiftUI

struct EditorView: View {
    static let windowID = "editor"

    @State private var model: EditorModel

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

                        Divider()

                        TransportBar(model: model)
                    }

                    Divider()

                    EditorInspector(settings: $model.settings)
                        .frame(width: 300)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 520)
        .navigationTitle(model.project.name)
        .task {
            await model.load()
        }
        .onDisappear {
            model.close()
        }
    }
}
