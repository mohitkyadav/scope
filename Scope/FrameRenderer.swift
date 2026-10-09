//
//  FrameRenderer.swift
//  Scope
//

import CoreImage

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

    var canvasSize: CGSize { videoSize }

    func render(source: CIImage, time: Double) -> CIImage {
        let videoRect = CGRect(origin: .zero, size: videoSize)
        var frame = source.cropped(to: videoRect)

        if let cursor = cursorLayer(at: time) {
            frame = cursor.composited(over: frame).cropped(to: videoRect)
        }
        return frame
    }

    private func cursorLayer(at time: Double) -> CIImage? {
        guard let cursorPath, let sprite, let position = cursorPath.position(at: time) else { return nil }

        // Cursor positions use a top-left origin; Core Image uses bottom-left.
        let point = CGPoint(x: position.x * videoSize.width, y: (1 - position.y) * videoSize.height)
        var scale = pixelsPerPoint / sprite.pixelsPerPoint
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
}
