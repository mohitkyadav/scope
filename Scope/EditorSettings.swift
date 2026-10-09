//
//  EditorSettings.swift
//  Scope
//

import CoreGraphics
import Foundation

/// How a project looks. Every change rebuilds the frame renderer, and settings are saved in the
/// project's `project.json`.
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

    /// Show the webcam bubble, if the project has a webcam video.
    var webcamVisible = true
    /// Centre of the bubble as fractions of the frame, from the top left.
    var webcamX = 0.88
    var webcamY = 0.82
    /// Width of the bubble as a fraction of the frame's shorter side.
    var webcamSize = 0.22
    var webcamShape = BubbleShape.circle
    var webcamShadow = true
    /// Flip the webcam like a mirror, which is how people expect to see themselves.
    var webcamMirrored = true

    /// What the recording sits on. With `.none` the video fills the frame and the settings below do nothing.
    var background = Background.none
    /// Space around the recording, as a fraction of the frame's shorter side.
    var padding = 0.08
    /// Corner radius of the recording, in screen points.
    var cornerRadius = 12.0
    var shadow = true
    /// How much the background zooms along with the recording, from 0 (stays still) to 1 (as much
    /// as the recording). Less than the recording gives a sense of depth.
    var parallax = 0.3

    /// The bubble's width in pixels on a frame of `canvas` size.
    func webcamDiameter(in canvas: CGSize) -> CGFloat {
        webcamSize * min(canvas.width, canvas.height)
    }

    /// The bubble's centre in pixels from the top left of a frame of `canvas` size, kept far enough
    /// from the edges that the whole bubble stays in the frame.
    func webcamCenter(in canvas: CGSize) -> CGPoint {
        let radius = webcamDiameter(in: canvas) / 2
        let margin = min(canvas.width, canvas.height) * 0.02
        return CGPoint(
            x: min(max(webcamX * canvas.width, radius + margin), canvas.width - radius - margin),
            y: min(max(webcamY * canvas.height, radius + margin), canvas.height - radius - margin)
        )
    }
}

extension EditorSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case cursorSmoothing, cursorSize, showClicks
        case autoZoom, zoomLevel, zoomTransition
        case webcamVisible, webcamX, webcamY, webcamSize, webcamShape, webcamShadow, webcamMirrored
        case background, padding, cornerRadius, shadow, parallax
    }

    /// Any setting missing from the file keeps its default, so projects saved by older versions still open.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func read<Value: Decodable>(_ key: CodingKeys, into value: inout Value) {
            if let decoded = try? container.decodeIfPresent(Value.self, forKey: key) {
                value = decoded
            }
        }
        read(.cursorSmoothing, into: &cursorSmoothing)
        read(.cursorSize, into: &cursorSize)
        read(.showClicks, into: &showClicks)
        read(.autoZoom, into: &autoZoom)
        read(.zoomLevel, into: &zoomLevel)
        read(.zoomTransition, into: &zoomTransition)
        read(.webcamVisible, into: &webcamVisible)
        read(.webcamX, into: &webcamX)
        read(.webcamY, into: &webcamY)
        read(.webcamSize, into: &webcamSize)
        read(.webcamShape, into: &webcamShape)
        read(.webcamShadow, into: &webcamShadow)
        read(.webcamMirrored, into: &webcamMirrored)
        read(.background, into: &background)
        read(.padding, into: &padding)
        read(.cornerRadius, into: &cornerRadius)
        read(.shadow, into: &shadow)
        read(.parallax, into: &parallax)
    }
}

nonisolated struct RGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

nonisolated enum Background: String, CaseIterable, Identifiable, Codable, Sendable {
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

nonisolated enum BubbleShape: String, CaseIterable, Identifiable, Codable, Sendable {
    case circle, roundedSquare

    var id: Self { self }

    var name: String {
        switch self {
        case .circle: "Circle"
        case .roundedSquare: "Rounded"
        }
    }
}
