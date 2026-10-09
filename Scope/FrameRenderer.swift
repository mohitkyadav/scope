//
//  FrameRenderer.swift
//  Scope
//

import CoreImage
import CoreImage.CIFilterBuiltins

/// Draws one finished frame of a project: the recorded video with Scope's cursor on top.
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

    /// How long a click ripple lasts.
    private static let rippleDuration = 0.5

    var canvasSize: CGSize { videoSize }

    func render(source: CIImage, time: Double) -> CIImage {
        let videoRect = CGRect(origin: .zero, size: videoSize)
        var frame = source.cropped(to: videoRect)

        if settings.showClicks {
            for ripple in rippleLayers(at: time) {
                frame = ripple.composited(over: frame)
            }
        }
        if let cursor = cursorLayer(at: time) {
            frame = cursor.composited(over: frame)
        }
        return frame.cropped(to: videoRect)
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
