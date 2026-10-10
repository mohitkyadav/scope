//
//  FrameRenderer.swift
//  Scope
//

import CoreImage
import CoreImage.CIFilterBuiltins

/// Draws one finished frame of a project: the recorded video with Scope's cursor on top, zoomed
/// in where there are zoom segments, optionally placed on a background with padding, rounded
/// corners and a shadow, and with the webcam bubble over it all.
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
    let camera: ZoomCamera?
    /// Shown before the recording's first video frame arrives, instead of a black frame.
    let firstFrame: CIImage?
    let notes: [Note]
    /// Each note drawn as a pill, by `Note.id`.
    let noteImages: [UUID: CIImage]
    /// Converts the final video's time to the recording's, which the cursor, clicks and zooms use.
    /// `nil` means the two are the same.
    let timeMap: TimeMap?
    /// For looping GIFs: ease the cursor back to where it was at the start of the loop.
    var cursorLoop: CursorLoop?

    /// How long a click ripple lasts.
    private static let rippleDuration = 0.5

    var canvasSize: CGSize { videoSize }

    /// `source` is the screen frame and `webcam` the camera frame at `time` in the final video, if there are any.
    func render(source: CIImage?, webcam: CIImage? = nil, time outputTime: Double) -> CIImage {
        let time = timeMap?.sourceTime(at: outputTime) ?? outputTime
        let videoRect = CGRect(origin: .zero, size: videoSize)
        // Before the first video frame there's no source image, or only an infinite empty one.
        let source = source.flatMap { $0.extent.isInfinite ? nil : $0 } ?? firstFrame ?? CIImage(color: .black)
        var frame = source.cropped(to: videoRect)

        if settings.showClicks {
            for ripple in rippleLayers(at: time) {
                frame = ripple.composited(over: frame)
            }
        }
        if let cursor = cursorLayer(at: time, outputTime: outputTime) {
            frame = cursor.composited(over: frame)
        }
        let video = frame.cropped(to: videoRect)
        var canvas = settings.background.colors == nil ? zoom(video, by: zoomScale(at: time), at: time) : placeOnBackground(video, at: time)
        if settings.webcamVisible, let webcam, let bubble = bubble(webcam) {
            canvas = bubble.composited(over: canvas)
        }
        for note in notes {
            if let layer = noteLayer(note, at: time) {
                canvas = layer.composited(over: canvas)
            }
        }
        return canvas.cropped(to: CGRect(origin: .zero, size: canvasSize))
    }

    /// How long notes take to fade in and out.
    private static let noteFade = 0.25

    /// A note at its place on the frame while it's showing, fading in and out at its ends.
    private func noteLayer(_ note: Note, at time: Double) -> CIImage? {
        guard time >= note.start, time <= note.end, let image = noteImages[note.id] else { return nil }
        let opacity = min(1, (time - note.start) / Self.noteFade, (note.end - time) / Self.noteFade)

        let center = Self.noteCenter(note, size: image.extent.size, canvas: canvasSize)
        let placed = image.transformed(by: CGAffineTransform(
            translationX: center.x - image.extent.width / 2,
            y: canvasSize.height - center.y - image.extent.height / 2
        ))
        return placed.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity),
        ])
    }

    /// A note's centre in pixels from the top left, kept far enough from the edges that it stays in the frame.
    static func noteCenter(_ note: Note, size: CGSize, canvas: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(note.x * canvas.width, size.width / 2), canvas.width - size.width / 2),
            y: min(max(note.y * canvas.height, size.height / 2), canvas.height - size.height / 2)
        )
    }

    /// The webcam as a round (or rounded square) bubble with a thin rim and a soft shadow. It sits on
    /// the finished frame, so it isn't zoomed and stays where it's placed.
    private func bubble(_ webcam: CIImage) -> CIImage? {
        let extent = webcam.extent
        guard !extent.isInfinite, extent.width > 0, extent.height > 0 else { return nil }

        let diameter = settings.webcamDiameter(in: canvasSize)
        // Settings measure from the top left; Core Image from the bottom left.
        let topLeftCenter = settings.webcamCenter(in: canvasSize)
        let center = CGPoint(x: topLeftCenter.x, y: canvasSize.height - topLeftCenter.y)
        let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        let radius = settings.webcamShape == .circle ? diameter / 2 : diameter * 0.18

        // Fill the bubble with the middle of the camera image, mirrored like a camera preview unless turned off.
        let scale = diameter / min(extent.width, extent.height)
        let camera = webcam.transformed(by: CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
            .concatenating(CGAffineTransform(scaleX: settings.webcamMirrored ? -scale : scale, y: scale))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
        let face = camera.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: roundedRectangle(rect, radius: radius, color: .white),
        ])

        let rimWidth = max(diameter * 0.015, 2)
        let rim = roundedRectangle(rect.insetBy(dx: -rimWidth, dy: -rimWidth), radius: radius + rimWidth, color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        let bubble = face.composited(over: rim)
        guard settings.webcamShadow else { return bubble }

        let shadow = roundedRectangle(rect.offsetBy(dx: 0, dy: -diameter * 0.03), radius: radius, color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.4))
            .applyingGaussianBlur(sigma: diameter * 0.05)
        return bubble.composited(over: shadow)
    }

    /// How far zoomed in the view is at `time`, from 0 to 1.
    private func zoomAmount(at time: Double) -> Double {
        guard settings.autoZoom, settings.zoomLevel > 1 else { return 0 }
        let amount = AutoZoom.amount(at: time, segments: zoomSegments, transition: settings.zoomTransition)
        return amount > 0.001 ? amount : 0
    }

    /// How much the recording is magnified at `time`: 1 when not zoomed, `zoomLevel` when fully zoomed.
    private func zoomScale(at time: Double) -> Double {
        1 + (settings.zoomLevel - 1) * zoomAmount(at: time)
    }

    /// Scales the frame up by `scale` around the camera's focus point. The focus is kept far enough
    /// from the edges that the zoomed view never shows past the edge of the recording.
    private func zoom(_ frame: CIImage, by scale: Double, at time: Double) -> CIImage {
        guard scale > 1.0001 else { return frame }

        let visible = CGSize(width: videoSize.width / scale, height: videoSize.height / scale)
        let focus = camera?.focus(at: time) ?? CGPoint(x: 0.5, y: 0.5)
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

    /// How far into the padding the window comes forward when fully zoomed, from 0 to 1.
    private static let windowZoomShare = 0.5

    /// Shrinks the video into the padded area of the canvas, rounds its corners and puts it on the
    /// background with a soft shadow, like a window.
    ///
    /// Zooming brings the window forward into part of the padding, and the rest of the magnification
    /// happens inside it, so the background always stays in view. The background zooms too, but only
    /// `parallax` as much as the window, which gives a sense of depth.
    private func placeOnBackground(_ video: CIImage, at time: Double) -> CIImage {
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

        // Split the zoom between the window coming forward and the recording zooming inside it.
        let amount = zoomAmount(at: time)
        let room = min(canvas.width / frame.width, canvas.height / frame.height)
        let windowScale = 1 + (room - 1) * Self.windowZoomShare * amount
        let video = zoom(video, by: zoomScale(at: time) / windowScale, at: time)

        let placed = video.transformed(by: CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: frame.minX, y: frame.minY)))
        let rounded = placed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: roundedRectangle(frame, radius: radius, color: .white),
        ])

        var window = rounded
        if settings.shadow {
            let shadow = roundedRectangle(
                frame.offsetBy(dx: 0, dy: -shorterSide * 0.01),
                radius: radius,
                color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.45)
            )
            .applyingGaussianBlur(sigma: shorterSide * 0.02)
            window = rounded.composited(over: shadow)
        }

        // The gradient isn't cropped until the end, so it still fills the frame once it's moved.
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: canvas.minX, y: canvas.maxY)
        gradient.point1 = CGPoint(x: canvas.maxX, y: canvas.minY)
        gradient.color0 = CIColor(topLeft)
        gradient.color1 = CIColor(bottomRight)
        var background = gradient.outputImage ?? CIImage(color: CIColor(topLeft))

        if windowScale > 1.0001 {
            // Grow the window around the point being zoomed in on, then nudge it back so it stays
            // whole inside the frame.
            let focusFraction = camera?.focus(at: time) ?? CGPoint(x: 0.5, y: 0.5)
            let focus = CGPoint(
                x: frame.minX + min(max(focusFraction.x, 0), 1) * frame.width,
                y: frame.minY + (1 - min(max(focusFraction.y, 0), 1)) * frame.height
            )
            let grown = CGRect(
                x: focus.x + (frame.minX - focus.x) * windowScale,
                y: focus.y + (frame.minY - focus.y) * windowScale,
                width: frame.width * windowScale,
                height: frame.height * windowScale
            )
            let shift = CGPoint(
                x: max(canvas.minX - grown.minX, 0) + min(canvas.maxX - grown.maxX, 0),
                y: max(canvas.minY - grown.minY, 0) + min(canvas.maxY - grown.maxY, 0)
            )
            let target = CGPoint(x: focus.x + shift.x, y: focus.y + shift.y)
            window = window.transformed(by: Self.zoom(around: focus, by: windowScale, to: target))

            let depth = settings.parallax
            let backgroundTarget = CGPoint(x: focus.x + shift.x * depth, y: focus.y + shift.y * depth)
            background = background.transformed(by: Self.zoom(around: focus, by: 1 + (windowScale - 1) * depth, to: backgroundTarget))
        }

        return window.composited(over: background).cropped(to: canvas)
    }

    /// Scales by `scale` around `point` and moves `point` to `target`.
    private static func zoom(around point: CGPoint, by scale: CGFloat, to target: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: -point.x, y: -point.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: target.x, y: target.y))
    }

    private func roundedRectangle(_ rect: CGRect, radius: CGFloat, color: CIColor) -> CIImage {
        let generator = CIFilter.roundedRectangleGenerator()
        generator.extent = rect
        generator.radius = Float(radius)
        generator.color = color
        return generator.outputImage ?? .empty()
    }

    private func cursorLayer(at time: Double, outputTime: Double) -> CIImage? {
        guard let cursorPath, let sprite, var position = cursorPath.position(at: time) else { return nil }
        if let cursorLoop, let loopStart = cursorPath.position(at: timeMap?.sourceTime(at: cursorLoop.start) ?? cursorLoop.start) {
            position = cursorLoop.blend(position, toward: loopStart, at: outputTime)
        }

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

/// Brings the cursor back to its starting point over the last moments of a looping section, so the
/// loop has no jump. Times are in the final video.
nonisolated struct CursorLoop: Sendable {
    let start: Double
    let end: Double

    /// How long the return takes: a quarter of the loop, at most 0.8 s.
    private var blendDuration: Double { min(0.8, (end - start) / 4) }

    func blend(_ position: CGPoint, toward target: CGPoint, at time: Double) -> CGPoint {
        let blendStart = end - blendDuration
        guard time > blendStart, blendDuration > 0 else { return position }
        let x = min((time - blendStart) / blendDuration, 1)
        let eased = x * x * (3 - 2 * x)
        return CGPoint(x: position.x + (target.x - position.x) * eased, y: position.y + (target.y - position.y) * eased)
    }
}
