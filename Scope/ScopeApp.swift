//
//  ScopeApp.swift
//  Scope
//

import SwiftUI

@main
struct ScopeApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var recorder = Recorder()

    var body: some Scene {
        WindowGroup("Scope") {
            ContentView()
                .environment(recorder)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
        }

        WindowGroup("Editor", id: EditorView.windowID, for: URL.self) { $projectURL in
            if let projectURL {
                EditorView(project: ScopeProject(url: projectURL)) { $projectURL.wrappedValue = $0 }
            }
        }
        .defaultSize(width: 1200, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            ProjectCommands()
        }

        // Only in the menu bar while a recording is running.
        MenuBarExtra(isInserted: .constant(recorder.isRecording || recorder.state == .stopping)) {
            Button("Stop Recording") {
                Task { await recorder.stop() }
            }
            .keyboardShortcut("2", modifiers: [.command, .shift])
        } label: {
            Label(recorder.elapsed.clockString, systemImage: "record.circle")
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
        }
    }
}
