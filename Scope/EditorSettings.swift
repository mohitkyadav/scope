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
    /// Change the cursor's shape as it did while recording, e.g. to a hand over links; otherwise
    /// it's the arrow throughout.
    var cursorShapes = true
    /// Ease the cursor across cuts, from where it was before the cut, instead of letting it jump.
    var cursorGlide = true

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
    /// Width of a square bubble as a fraction of the frame's shorter side. Other shapes have the same area.
    var webcamSize = 0.22
    var webcamShape = BubbleShape.circle
    var webcamBorder = BubbleBorder.white
    /// The border's colour when `webcamBorder` is `.custom`.
    var webcamBorderColor = RGB(red: 0.23, green: 0.51, blue: 0.96)
    /// Thickness of the border as a fraction of the bubble's shorter side.
    var webcamBorderWidth = 0.015
    var webcamShadow = true
    /// Flip the webcam like a mirror, which is how people expect to see themselves.
    var webcamMirrored = true
    /// How far the bubble zooms into the camera, from 1 (the whole picture fills it) to 3.
    var webcamZoom = 1.0
    /// Which part of the zoomed camera shows, from -1 (left or top edge) to 1 (right or bottom edge),
    /// as seen in the bubble, so mirroring doesn't swap left and right.
    var webcamFocusX = 0.0
    var webcamFocusY = 0.0

    /// The shape of the finished video, e.g. 9:16 for phones.
    var frameFormat = FrameFormat.original

    /// What the recording sits on. With `.none` the video fills the frame and the settings below do nothing.
    var background = Background.none
    /// The image in the project used when `background` is `.image`.
    var backgroundImageFileName: String?
    /// How much to blur an image background, from 0 (sharp) to 1 (very soft).
    var backgroundBlur = 0.0
    /// Space around the recording, as a fraction of the frame's shorter side.
    var padding = 0.08
    /// Corner radius of the recording, in screen points.
    var cornerRadius = 18.0
    /// How strong the recording's shadow is, from 0 (none) to 1. Half is a soft, natural shadow.
    var shadowStrength = 0.5
    /// How much the background zooms along with the recording, from 0 (stays still) to 1 (as much
    /// as the recording). Less than the recording gives a sense of depth.
    var parallax = 0.0

    /// The border's colour, or `nil` for no border.
    var webcamBorderRGB: RGB? {
        webcamBorder == .custom ? webcamBorderColor : webcamBorder.color
    }

    /// The bubble's size in pixels on a frame of `canvas` size.
    func webcamFrameSize(in canvas: CGSize) -> CGSize {
        let side = webcamSize * min(canvas.width, canvas.height)
        let stretch = webcamShape.aspectRatio.squareRoot()
        return CGSize(width: side * stretch, height: side / stretch)
    }

    /// The bubble's corner radius in pixels on a frame of `canvas` size.
    func webcamCornerRadius(in canvas: CGSize) -> CGFloat {
        let size = webcamFrameSize(in: canvas)
        return min(size.width, size.height) * webcamShape.cornerRadius
    }

    /// The bubble's centre in pixels from the top left of a frame of `canvas` size, kept far enough
    /// from the edges that the whole bubble stays in the frame.
    func webcamCenter(in canvas: CGSize) -> CGPoint {
        let size = webcamFrameSize(in: canvas)
        let margin = min(canvas.width, canvas.height) * 0.02
        return CGPoint(
            x: min(max(webcamX * canvas.width, size.width / 2 + margin), canvas.width - size.width / 2 - margin),
            y: min(max(webcamY * canvas.height, size.height / 2 + margin), canvas.height - size.height / 2 - margin)
        )
    }
}

extension EditorSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case cursorSmoothing, cursorSize, showClicks, cursorShapes, cursorGlide
        case autoZoom, zoomLevel, zoomTransition, motionBlur
        case webcamVisible, webcamX, webcamY, webcamSize, webcamShape, webcamBorder, webcamBorderColor, webcamBorderWidth, webcamShadow, webcamMirrored
        case webcamZoom, webcamFocusX, webcamFocusY
        case frameFormat
        case background, backgroundImageFileName, backgroundBlur, padding, cornerRadius, shadowStrength, parallax
    }

    /// Settings from older versions that are now stored differently.
    private enum OldKeys: String, CodingKey {
        /// On or off, before the shadow had a strength.
        case shadow
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
        read(.cursorShapes, into: &cursorShapes)
        read(.cursorGlide, into: &cursorGlide)
        read(.autoZoom, into: &autoZoom)
        read(.zoomLevel, into: &zoomLevel)
        read(.zoomTransition, into: &zoomTransition)
        read(.motionBlur, into: &motionBlur)
        read(.webcamVisible, into: &webcamVisible)
        read(.webcamX, into: &webcamX)
        read(.webcamY, into: &webcamY)
        read(.webcamSize, into: &webcamSize)
        read(.webcamShape, into: &webcamShape)
        read(.webcamBorder, into: &webcamBorder)
        read(.webcamBorderColor, into: &webcamBorderColor)
        read(.webcamBorderWidth, into: &webcamBorderWidth)
        read(.webcamShadow, into: &webcamShadow)
        read(.webcamMirrored, into: &webcamMirrored)
        read(.webcamZoom, into: &webcamZoom)
        read(.webcamFocusX, into: &webcamFocusX)
        read(.webcamFocusY, into: &webcamFocusY)
        read(.frameFormat, into: &frameFormat)
        read(.background, into: &background)
        read(.backgroundImageFileName, into: &backgroundImageFileName)
        read(.backgroundBlur, into: &backgroundBlur)
        read(.padding, into: &padding)
        read(.cornerRadius, into: &cornerRadius)
        if let strength = try? container.decodeIfPresent(Double.self, forKey: .shadowStrength) {
            shadowStrength = strength
        } else if let old = try? decoder.container(keyedBy: OldKeys.self), let shadow = try? old.decodeIfPresent(Bool.self, forKey: .shadow) {
            shadowStrength = shadow ? 0.5 : 0
        }
        read(.parallax, into: &parallax)
    }
}

nonisolated struct RGB: Equatable, Codable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

extension RGB {
    /// Reads "#3B82F6", "3b82f6" or the short "#38F".
    nonisolated init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// "#3B82F6".
    nonisolated var hex: String {
        func byte(_ component: Double) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

nonisolated enum Background: String, CaseIterable, Identifiable, Sendable {
    case none, aurora, sunrise, lagoon, orchid, sage, image

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
        case .sage: "Sage"
        case .image: "Image"
        }
    }

    /// The gradient's colours from the top left to the bottom right, evenly spaced. An image uses
    /// Aurora until it has an image.
    var colors: [RGB]? {
        switch self {
        case .none: nil
        case .aurora, .image: [RGB(red: 0.29, green: 0.22, blue: 0.78), RGB(red: 0.08, green: 0.71, blue: 0.74)]
        case .sunrise: [RGB(red: 0.98, green: 0.42, blue: 0.42), RGB(red: 0.99, green: 0.75, blue: 0.36)]
        case .lagoon: [RGB(red: 0.27, green: 0.58, blue: 0.98), RGB(red: 0.38, green: 0.89, blue: 0.74)]
        case .orchid: [RGB(red: 0.87, green: 0.31, blue: 0.72), RGB(red: 0.44, green: 0.31, blue: 0.95)]
        // #DEDEDC, #DFE9D9, #E0E2C4.
        case .sage: [RGB(red: 0.871, green: 0.871, blue: 0.863), RGB(red: 0.875, green: 0.914, blue: 0.851), RGB(red: 0.878, green: 0.886, blue: 0.769)]
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
    case circle, roundedSquare, square, portrait, landscape

    var id: Self { self }

    var name: String {
        switch self {
        case .circle: "Circle"
        case .roundedSquare: "Rounded"
        case .square: "Square"
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        }
    }

    var symbol: String {
        switch self {
        case .circle: "circle"
        case .roundedSquare: "app"
        case .square: "square"
        case .portrait: "rectangle.portrait"
        case .landscape: "rectangle"
        }
    }

    /// Width divided by height.
    var aspectRatio: Double {
        switch self {
        case .circle, .roundedSquare, .square: 1
        case .portrait: 9.0 / 16
        case .landscape: 16.0 / 9
        }
    }

    /// Corner radius as a fraction of the shorter side.
    var cornerRadius: Double {
        switch self {
        case .circle: 0.5
        case .roundedSquare, .portrait, .landscape: 0.18
        case .square: 0
        }
    }
}

nonisolated enum BubbleBorder: String, CaseIterable, Identifiable, Codable, Sendable {
    case none, white, black, red, custom

    var id: Self { self }
    /// The ready-made choices, offered as swatches.
    static let presets: [BubbleBorder] = [.none, .white, .black, .red]

    var name: String {
        switch self {
        case .none: "None"
        case .white: "White"
        case .black: "Black"
        case .red: "Red"
        case .custom: "Custom"
        }
    }

    /// `nil` for no border, and for a custom one, whose colour is in the settings.
    var color: RGB? {
        switch self {
        case .none, .custom: nil
        case .white: RGB(red: 1, green: 1, blue: 1)
        case .black: RGB(red: 0, green: 0, blue: 0)
        // Scope's accent.
        case .red: RGB(red: 0.91, green: 0.28, blue: 0.24)
        }
    }
}

/// The shape of the finished video.
nonisolated enum FrameFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case original, landscape, square, portrait, vertical

    var id: Self { self }

    var name: String {
        switch self {
        case .original: "Original"
        case .landscape: "16:9"
        case .square: "1:1"
        case .portrait: "4:5"
        case .vertical: "9:16"
        }
    }

    /// What it's for, e.g. "Instagram posts".
    var use: String {
        switch self {
        case .original: "The recording's own shape"
        case .landscape: "YouTube, slides and websites"
        case .square: "Posts that show the same everywhere"
        case .portrait: "Instagram and LinkedIn posts"
        case .vertical: "Shorts, Reels and TikTok"
        }
    }

    /// Width divided by height, or `nil` for the recording's own shape.
    var aspectRatio: Double? {
        switch self {
        case .original: nil
        case .landscape: 16.0 / 9
        case .square: 1
        case .portrait: 4.0 / 5
        case .vertical: 9.0 / 16
        }
    }

    /// The finished video's size for a recording of `videoSize`: its shorter side matches the
    /// recording's, so the recording keeps its detail. Even numbers, as video encoders need.
    func canvasSize(for videoSize: CGSize) -> CGSize {
        guard let ratio = aspectRatio, videoSize.width > 0, videoSize.height > 0 else { return videoSize }
        let shorterSide = min(videoSize.width, videoSize.height)
        func even(_ value: Double) -> CGFloat { CGFloat((value / 2).rounded() * 2) }
        return ratio >= 1
            ? CGSize(width: even(shorterSide * ratio), height: even(shorterSide))
            : CGSize(width: even(shorterSide), height: even(shorterSide / ratio))
    }
}
