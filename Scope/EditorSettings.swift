//
//  EditorSettings.swift
//  Scope
//

import Foundation

/// How a project looks. Every change rebuilds the frame renderer.
nonisolated struct EditorSettings: Equatable, Sendable {
    /// 0 follows the recorded path exactly, 1 is the smoothest.
    var cursorSmoothing = 0.5
    /// Multiple of the cursor's real size.
    var cursorSize = 1.5
    /// Show a ripple where each click happened.
    var showClicks = true
}
