//
//  FrameRenderer.swift
//  Scope
//

import CoreImage
import CoreImage.CIFilterBuiltins

/// Draws one finished frame of a project: the recorded video with Scope's cursor on top, zoomed
/// in where there are zoom segments, and optionally placed on a background with padding, rounded
/// corners and a shadow.
///
/// The same renderer feeds the editor's preview and, later, export, so both always match.
/// It's an immutable value that's safe to use from Core Image's rendering threads; the editor
/// builds a new one whenever a setting changes.
nonisolated struct FrameRenderer: @unchecked Sendable {
    let videoSize: CGSize
    let cursorPath: CursorPath?
    let sprite: CursorSprite?
    /// Video pixels per screen point at recording time, e.g. 2 on a Retina display.
    let pixelsPerPoint: CGFloat
    let settings: EditorSettings
    let zoomSegments: [ZoomSegment]
    /// The smoothed cursor path the zoomed-in view follows.
    let cameraPath: CursorPath?
    /// Shown before the recording's first video frame arrives, instead of a black frame.
    let firstFrame: CIImage?

    /// How long a click ripple lasts.
    private static let rippleDuration = 0.5

    var canvasSize: CGSize { videoSize }

    func render(source: CIImage, time: Double) -> CIImage {
        let videoRect = CGRect(origin: .zero, size: videoSize)
        // Before the first video frame there's no source image, only an infinite empty one.
        let source = source.extent.isInfinite ? (firstFrame ?? source) : source
        var frame = source.cropped(to: videoRect)

        if settings.showClicks {
            for ripple in rippleLayers(at: time) {
                frame = ripple.composited(over: frame)
            }
        }
        if let cursor = cursorLayer(at: time) {
            frame = cursor.composited(over: frame)
        }
        return placeOnBackground(zoom(frame.cropped(to: videoRect), at: time))
    }

    /// Scales the frame up around the camera's focus point. The focus is kept far enough from the
    /// edges that the zoomed view never shows past the edge of the recording.
    private func zoom(_ frame: CIImage, at time: Double) -> CIImage {
        guard settings.autoZoom, settings.zoomLevel > 1 else { return frame }
        let amount = AutoZoom.amount(at: time, segments: zoomSegments, transition: settings.zoomTransition)
        guard amount > 0.001 else { return frame }

        let scale = 1 + (settings.zoomLevel - 1) * amount
        let visible = CGSize(width: videoSize.width / scale, height: videoSize.height / scale)
        let focus = cameraPath?.position(at: time) ?? CGPoint(x: 0.5, y: 0.5)
        let center = CGPoint(
            x: min(max(focus.x * videoSize.width, visible.width / 2), videoSize.width - visible.width / 2),
            y: min(max((1 - focus.y) * videoSize.height, visible.height / 2), videoSize.height - visible.height / 2)
        )

        let transform = CGAffineTransform(
            translationX: -(center.x - visible.width / 2),
            y: -(center.y - visible.height / 2)
        )
        .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        return frame.transformed(by: transform).cropped(to: CGRect(origin: .zero, size: videoSize))
    }

    /// Shrinks the video into the padded area of the canvas, rounds its corners and puts it
    /// on the background with a soft shadow.
    private func placeOnBackground(_ video: CIImage) -> CIImage {
        guard let (topLeft, bottomRight) = settings.background.colors else { return video }

        let canvas = CGRect(origin: .zero, size: canvasSize)
        let shorterSide = min(canvas.width, canvas.height)
        let inset = settings.padding * shorterSide
        let scale = min(
            (canvas.width - 2 * inset) / videoSize.width,
            (canvas.height - 2 * inset) / videoSize.height
        )
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        let frame = CGRect(
            x: (canvas.width - size.width) / 2,
            y: (canvas.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        let radius = settings.cornerRadius * pixelsPerPoint * scale

        let placed = video.transformed(by: CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: frame.minX, y: frame.minY)))
        let rounded = placed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: roundedRectangle(frame, radius: radius, color: .white),
        ])

        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: canvas.minX, y: canvas.maxY)
        gradient.point1 = CGPoint(x: canvas.maxX, y: canvas.minY)
        gradient.color0 = CIColor(topLeft)
        gradient.color1 = CIColor(bottomRight)
        var result = (gradient.outputImage ?? CIImage(color: CIColor(topLeft))).cropped(to: canvas)

        if settings.shadow {
            let shadow = roundedRectangle(
                frame.offsetBy(dx: 0, dy: -shorterSide * 0.01),
                radius: radius,
                color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.45)
            )
            .applyingGaussianBlur(sigma: shorterSide * 0.02)
            result = shadow.composited(over: result)
        }

        return rounded.composited(over: result).cropped(to: canvas)
    }

    private func roundedRectangle(_ rect: CGRect, radius: CGFloat, color: CIColor) -> CIImage {
        let generator = CIFilter.roundedRectangleGenerator()
        generator.extent = rect
        generator.radius = Float(radius)
        generator.color = color
        return generator.outputImage ?? .empty()
    }

    private func cursorLayer(at time: Double) -> CIImage? {
        guard let cursorPath, let sprite, let position = cursorPath.position(at: time) else { return nil }

        // Cursor positions use a top-left origin; Core Image uses bottom-left.
        let point = CGPoint(x: position.x * videoSize.width, y: (1 - position.y) * videoSize.height)
        var scale = pixelsPerPoint * settings.cursorSize / sprite.pixelsPerPoint
        if cursorPath.isPressed(at: time) {
            scale *= 0.85
        }

        let hotSpot = CGPoint(
            x: sprite.hotSpot.x * sprite.pixelsPerPoint,
            y: sprite.image.extent.height - sprite.hotSpot.y * sprite.pixelsPerPoint
        )
        let transform = CGAffineTransform(translationX: -hotSpot.x, y: -hotSpot.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: point.x, y: point.y))

        let cursor = sprite.image.transformed(by: transform)
        let shadow = sprite.shadow.transformed(by: transform.concatenating(
            CGAffineTransform(translationX: 0, y: -pixelsPerPoint)
        ))
        return cursor.composited(over: shadow)
    }

    /// An expanding, fading ring for each click in the last half second.
    private func rippleLayers(at time: Double) -> [CIImage] {
        guard let cursorPath else { return [] }

        return cursorPath.clicks.compactMap { click in
            let age = time - click.t
            guard age >= 0, age <= Self.rippleDuration else { return nil }

            let progress = age / Self.rippleDuration
            let eased = 1 - pow(1 - progress, 3)
            let outer = (6 + 26 * eased) * pixelsPerPoint * settings.cursorSize
            let inner = outer * 0.7
            let center = CIVector(x: click.x * videoSize.width, y: (1 - click.y) * videoSize.height)
            let color = CIColor(red: 0.25, green: 0.55, blue: 1, alpha: 0.55 * (1 - progress))

            let disc = CIFilter.radialGradient()
            disc.center = center.cgPointValue
            disc.radius0 = Float(outer * 0.9)
            disc.radius1 = Float(outer)
            disc.color0 = color
            disc.color1 = .clear

            let hole = CIFilter.radialGradient()
            hole.center = center.cgPointValue
            hole.radius0 = Float(inner * 0.85)
            hole.radius1 = Float(inner)
            hole.color0 = .white
            hole.color1 = .clear

            guard let discImage = disc.outputImage, let holeImage = hole.outputImage else { return nil }
            let bounds = CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)
            return discImage
                .applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: holeImage])
                .cropped(to: bounds)
        }
    }
}

private extension CIColor {
    nonisolated convenience init(_ rgb: RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
