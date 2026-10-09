//
//  NoteImage.swift
//  Scope
//

import AppKit
import CoreImage

/// Draws a note as white text on a dark rounded pill, sized for a frame of `canvasSize`.
enum NoteImage {
    static func make(text: String, canvasSize: CGSize) -> CIImage? {
        let fontSize = max(canvasSize.height * 0.035, 12)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text.isEmpty ? " " : text, attributes: attributes)
        let textSize = string.boundingRect(with: CGSize(width: canvasSize.width * 0.8, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).size
        let padding = CGSize(width: fontSize * 0.9, height: fontSize * 0.5)
        let size = CGSize(width: ceil(textSize.width + padding.width * 2), height: ceil(textSize.height + padding.height * 2))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(white: 0, alpha: 0.75).setFill()
        NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: size.height * 0.3, yRadius: size.height * 0.3).fill()
        string.draw(with: CGRect(x: padding.width, y: padding.height, width: textSize.width, height: textSize.height), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.cgImage.map { CIImage(cgImage: $0) }
    }
}
