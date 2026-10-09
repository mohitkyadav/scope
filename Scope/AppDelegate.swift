//
//  AppDelegate.swift
//  Scope
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Double-clicking a `.scope` project in Finder plays its video until Scope has its own editor.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension == ScopeProject.fileExtension {
            NSWorkspace.shared.open(ScopeProject(url: url).videoURL)
        }
    }
}
