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
    /// How much the picture grows when fully zoomed in, e.g. 1.5 makes everything half as big again.
    var zoomLevel = 1.5
    /// Seconds a zoom in or out takes to settle.
    var zoomTransition = 1.1
    /// Blur things while they move, like a camera's shutter does, so zooms, pans and the cursor look smooth.
    var motionBlur = true

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
    /// The image in the project used when `background` is `.image`.
    var backgroundImageFileName: String?
    /// How much to blur an image background, from 0 (sharp) to 1 (very soft).
    var backgroundBlur = 0.0
    /// Space around the recording, as a fraction of the frame's shorter side.
    var padding = 0.08
    /// Corner radius of the recording, in screen points.
    var cornerRadius = 12.0
    var shadow = true
    /// How much the background zooms along with the recording, from 0 (stays still) to 1 (as much
    /// as the recording). Less than the recording gives a sense of depth.
    var parallax = 0.0

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
        case autoZoom, zoomLevel, zoomTransition, motionBlur
        case webcamVisible, webcamX, webcamY, webcamSize, webcamShape, webcamShadow, webcamMirrored
        case background, backgroundImageFileName, backgroundBlur, padding, cornerRadius, shadow, parallax
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
        read(.motionBlur, into: &motionBlur)
        read(.webcamVisible, into: &webcamVisible)
        read(.webcamX, into: &webcamX)
        read(.webcamY, into: &webcamY)
        read(.webcamSize, into: &webcamSize)
        read(.webcamShape, into: &webcamShape)
        read(.webcamShadow, into: &webcamShadow)
        read(.webcamMirrored, into: &webcamMirrored)
        read(.background, into: &background)
        read(.backgroundImageFileName, into: &backgroundImageFileName)
        read(.backgroundBlur, into: &backgroundBlur)
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

nonisolated enum Background: String, CaseIterable, Identifiable, Sendable {
    case none, aurora, sunrise, lagoon, orchid, image

    var id: Self { self }
    /// Every background but an image, in the order they're offered.
    static let gradients = allCases.filter { $0 != .image }

    var name: String {
        switch self {
        case .none: "None"
        case .aurora: "Aurora"
        case .sunrise: "Sunrise"
        case .lagoon: "Lagoon"
        case .orchid: "Orchid"
        case .image: "Image"
        }
    }

    /// Top-left and bottom-right colours of the gradient. An image uses Aurora until it has an image.
    var colors: (RGB, RGB)? {
        switch self {
        case .none: nil
        case .aurora, .image: (RGB(red: 0.29, green: 0.22, blue: 0.78), RGB(red: 0.08, green: 0.71, blue: 0.74))
        case .sunrise: (RGB(red: 0.98, green: 0.42, blue: 0.42), RGB(red: 0.99, green: 0.75, blue: 0.36))
        case .lagoon: (RGB(red: 0.27, green: 0.58, blue: 0.98), RGB(red: 0.38, green: 0.89, blue: 0.74))
        case .orchid: (RGB(red: 0.87, green: 0.31, blue: 0.72), RGB(red: 0.44, green: 0.31, blue: 0.95))
        }
    }
}

extension Background: Codable {
    /// Backgrounds from earlier versions that no longer exist become the closest one that does,
    /// so older projects keep a background.
    nonisolated init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let background = Background(rawValue: raw) {
            self = background
            return
        }
        switch raw {
        case "sunset": self = .sunrise
        case "ocean": self = .lagoon
        case "lavender": self = .orchid
        default: self = .aurora
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
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
