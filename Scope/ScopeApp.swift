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

        WindowGroup("Editor", id: EditorView.windowID, for: URL.self) { $projectURL in
            if let projectURL {
                EditorView(project: ScopeProject(url: projectURL))
            }
        }
        .defaultSize(width: 1100, height: 720)

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
