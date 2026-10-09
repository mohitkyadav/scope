//
//  AppDelegate.swift
//  Scope
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Double-clicking a `.scope` project in Finder opens it in the editor.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension == ScopeProject.fileExtension {
            ProjectOpener.shared.request(ScopeProject(url: url))
        }
    }
}
