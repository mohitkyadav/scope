//
//  ProjectCommands.swift
//  Scope
//

import SwiftUI

/// File › Open Project… and Open Recent.
struct ProjectCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    private let recents = RecentProjects.shared

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Project…") {
                if let url = RecentProjects.chooseProject() {
                    openWindow(id: EditorView.windowID, value: url)
                }
            }
            .keyboardShortcut("o")

            Menu("Open Recent") {
                ForEach(recents.existing, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) {
                        openWindow(id: EditorView.windowID, value: url)
                    }
                }
                Divider()
                Button("Clear Menu", action: recents.clear)
                    .disabled(recents.urls.isEmpty)
            }
        }
    }
}
