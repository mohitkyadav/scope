//
//  ScopeApp.swift
//  Scope
//

import SwiftUI

@main
struct ScopeApp: App {
    @State private var recorder = Recorder()

    var body: some Scene {
        WindowGroup("Scope") {
            ContentView()
                .environment(recorder)
        }
    }
}
