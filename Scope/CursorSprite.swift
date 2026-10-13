//
//  CursorSprite.swift
//  Scope
//

import AppKit
import CoreImage

/// A cursor as a Core Image image, rendered at 4× so it stays sharp when scaled up.
nonisolated struct CursorSprite: @unchecked Sendable {
    let image: CIImage
    /// A soft drop shadow in the same coordinates as `image`.
    let shadow: CIImage
    /// Image pixels per cursor point.
    let pixelsPerPoint: CGFloat
    /// The click point, in cursor points from the top left.
    let hotSpot: CGPoint

    /// How many pixels per point cursor images are drawn at.
    static let scale: CGFloat = 4

    init(image: CIImage, pixelsPerPoint: CGFloat, hotSpot: CGPoint) {
        self.image = image
        self.pixelsPerPoint = pixelsPerPoint
        self.hotSpot = hotSpot
        shadow = image
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.35),
            ])
            .applyingGaussianBlur(sigma: 1.5 * pixelsPerPoint)
    }

    /// The system arrow.
    @MainActor
    static func arrow() -> CursorSprite? {
        let cursor = NSCursor.arrow
        guard let bitmap = bitmap(of: cursor.image), let cgImage = bitmap.cgImage else { return nil }
        return CursorSprite(image: CIImage(cgImage: cgImage), pixelsPerPoint: scale, hotSpot: cursor.hotSpot)
    }

    /// A shape saved while recording, or `nil` if its image can't be read.
    static func load(_ shape: CursorTrack.Shape, from folder: URL) -> CursorSprite? {
        guard shape.width > 0, let image = CIImage(contentsOf: folder.appending(path: "\(shape.id).png")) else { return nil }
        return CursorSprite(image: image, pixelsPerPoint: image.extent.width / shape.width, hotSpot: CGPoint(x: shape.hotX, y: shape.hotY))
    }

    /// A cursor image drawn at 4×. System cursors come with images up to 10×, so it stays sharp.
    @MainActor
    static func bitmap(of image: NSImage) -> NSBitmapImageRep? {
        let size = image.size
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
        image.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}

/// The cursor's look through a recording: the shapes it took, or the arrow throughout.
nonisolated struct CursorSprites: Sendable {
    let arrow: CursorSprite
    let shapes: [String: CursorSprite]
    /// In time order.
    let changes: [CursorTrack.ShapeChange]

    init(arrow: CursorSprite, shapes: [String: CursorSprite] = [:], changes: [CursorTrack.ShapeChange] = []) {
        self.arrow = arrow
        self.shapes = shapes
        self.changes = changes.sorted { $0.t < $1.t }
    }

    /// The shape the cursor had at `time` in the recording, or the arrow for shapes that weren't saved.
    func sprite(at time: Double) -> CursorSprite {
        // The last change at or before `time`.
        var low = 0
        var high = changes.count
        while low < high {
            let middle = (low + high) / 2
            if changes[middle].t <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low > 0 else { return changes.first.flatMap { shapes[$0.shape] } ?? arrow }
        return shapes[changes[low - 1].shape] ?? arrow
    }
}
