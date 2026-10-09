//
//  ProjectOpener.swift
//  Scope
//

import Foundation
import Observation

/// Projects waiting to be opened in an editor window.
///
/// The app delegate receives projects opened from Finder but can't open SwiftUI windows itself,
/// so it queues them here and the main window opens them.
@Observable
final class ProjectOpener {
    static let shared = ProjectOpener()

    private(set) var pending: [ScopeProject] = []

    func request(_ project: ScopeProject) {
        pending.append(project)
    }

    func takePending() -> [ScopeProject] {
        defer { pending = [] }
        return pending
    }
}
