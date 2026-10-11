import AppKit
import CoreText

// Prints an SVG path for a word in SF Pro Rounded Heavy, centred on (0, 0), y pointing down.
// Used for the LOCAL label in make_icon.py: `xcrun swift Design/text_path.swift LOCAL 84 6`.
let text = CommandLine.arguments[1]
let size = CGFloat(Double(CommandLine.arguments[2])!)
let tracking = CGFloat(Double(CommandLine.arguments[3])!)
let base = NSFont.systemFont(ofSize: size, weight: .heavy)
let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: size)! as CTFont

var path = CGMutablePath()
var x: CGFloat = 0
let chars = Array(text.utf16)
var glyphs = [CGGlyph](repeating: 0, count: chars.count)
CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
var advances = [CGSize](repeating: .zero, count: glyphs.count)
CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
for (i, glyph) in glyphs.enumerated() {
    if let g = CTFontCreatePathForGlyph(font, glyph, nil) {
        path.addPath(g, transform: CGAffineTransform(translationX: x, y: 0))
    }
    x += advances[i].width + (i < glyphs.count - 1 ? tracking : 0)
}
let box = path.boundingBoxOfPath
// Centre it, and flip so y points down like SVG.
let t = CGAffineTransform(translationX: -box.midX, y: box.midY).scaledBy(x: 1, y: -1)
let placed = path.copy(using: [t])!
var d = ""
func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
placed.applyWithBlock { e in
    let p = e.pointee.points
    switch e.pointee.type {
    case .moveToPoint: d += "M\(f(p[0].x)) \(f(p[0].y))"
    case .addLineToPoint: d += "L\(f(p[0].x)) \(f(p[0].y))"
    case .addQuadCurveToPoint: d += "Q\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y))"
    case .addCurveToPoint: d += "C\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) \(f(p[2].x)) \(f(p[2].y))"
    case .closeSubpath: d += "Z"
    @unknown default: break
    }
}
FileHandle.standardError.write("width \(f(box.width)) height \(f(box.height))\n".data(using: .utf8)!)
print(d)
