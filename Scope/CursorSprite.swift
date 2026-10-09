//
//  CursorSprite.swift
//  Scope
//

import AppKit
import CoreImage

/// The system arrow cursor as a Core Image image, rendered at 4× so it stays sharp when scaled up.
nonisolated struct CursorSprite: @unchecked Sendable {
    let image: CIImage
    /// A soft drop shadow in the same coordinates as `image`.
    let shadow: CIImage
    /// Image pixels per cursor point.
    let pixelsPerPoint: CGFloat
    /// The click point, in cursor points from the top left.
    let hotSpot: CGPoint

    @MainActor
    static func arrow() -> CursorSprite? {
        let cursor = NSCursor.arrow
        let size = cursor.image.size
        let scale: CGFloat = 4

        guard size.width > 0, size.height > 0,
              let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        cursor.image.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = bitmap.cgImage else { return nil }
        let image = CIImage(cgImage: cgImage)

        let shadow = image
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.35),
            ])
            .applyingGaussianBlur(sigma: 1.5 * scale)

        return CursorSprite(image: image, shadow: shadow, pixelsPerPoint: scale, hotSpot: cursor.hotSpot)
    }
}
