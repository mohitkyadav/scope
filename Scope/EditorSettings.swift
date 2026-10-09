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

    /// Zoom in on the zoom segments.
    var autoZoom = true
    /// How far to zoom in, e.g. 2 shows a quarter of the screen.
    var zoomLevel = 2.0
    /// Seconds spent zooming in or out.
    var zoomTransition = 0.7

    /// What the recording sits on. With `.none` the video fills the frame and the settings below do nothing.
    var background = Background.none
    /// Space around the recording, as a fraction of the frame's shorter side.
    var padding = 0.08
    /// Corner radius of the recording, in screen points.
    var cornerRadius = 12.0
    var shadow = true
}

nonisolated struct RGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

nonisolated enum Background: String, CaseIterable, Identifiable, Sendable {
    case none, sunset, ocean, forest, lavender, graphite, white, black

    var id: Self { self }

    var name: String {
        switch self {
        case .none: "None"
        case .sunset: "Sunset"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .lavender: "Lavender"
        case .graphite: "Graphite"
        case .white: "White"
        case .black: "Black"
        }
    }

    /// Top-left and bottom-right colours of the gradient. Solid colours use the same colour twice.
    var colors: (RGB, RGB)? {
        switch self {
        case .none: nil
        case .sunset: (RGB(red: 1, green: 0.55, blue: 0.35), RGB(red: 0.93, green: 0.29, blue: 0.55))
        case .ocean: (RGB(red: 0.15, green: 0.55, blue: 0.95), RGB(red: 0.1, green: 0.8, blue: 0.75))
        case .forest: (RGB(red: 0.2, green: 0.65, blue: 0.4), RGB(red: 0.05, green: 0.35, blue: 0.3))
        case .lavender: (RGB(red: 0.7, green: 0.6, blue: 1), RGB(red: 0.45, green: 0.35, blue: 0.85))
        case .graphite: (RGB(red: 0.3, green: 0.32, blue: 0.36), RGB(red: 0.12, green: 0.13, blue: 0.15))
        case .white: (RGB(red: 0.96, green: 0.96, blue: 0.97), RGB(red: 0.96, green: 0.96, blue: 0.97))
        case .black: (RGB(red: 0.05, green: 0.05, blue: 0.06), RGB(red: 0.05, green: 0.05, blue: 0.06))
        }
    }
}
