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
    /// How the cursor looks over the recording.
    let sprites: CursorSprites?
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
    /// Where the webcam bubble is hidden.
    let webcamHides: [WebcamHide]
    /// The image background, already scaled to fill the frame and blurred, if one is chosen.
    var backgroundImage: CIImage?
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
        // Before the first video frame there's no source image, or only an infinite empty one.
        let source = source.flatMap { $0.extent.isInfinite ? nil : $0 } ?? firstFrame ?? CIImage(color: .black)

        var canvas = blurredScene(source, at: outputTime)
        let webcamVisibility = WebcamHide.visibility(at: time, hides: webcamHides)
        if settings.webcamVisible, webcamVisibility > 0, let webcam, let bubble = bubble(webcam, visibility: webcamVisibility) {
            canvas = bubble.composited(over: canvas)
        }
        for note in notes {
            if let layer = noteLayer(note, at: time) {
                canvas = layer.composited(over: canvas)
            }
        }
        return canvas.cropped(to: CGRect(origin: .zero, size: canvasSize))
    }

    /// The recording with its cursor, zoomed and placed on the background: everything that moves.
    /// `cursorTimes` are when to draw the cursor, averaged if there's more than one.
    private func scene(_ source: CIImage, at outputTime: Double, cursorTimes: [Double]? = nil) -> CIImage {
        let time = timeMap?.sourceTime(at: outputTime) ?? outputTime
        let videoRect = CGRect(origin: .zero, size: videoSize)
        var frame = source.cropped(to: videoRect)

        if settings.showClicks {
            for ripple in rippleLayers(at: time) {
                frame = ripple.composited(over: frame)
            }
        }
        let cursors = (cursorTimes ?? [outputTime]).compactMap { outputTime in
            cursorLayer(at: timeMap?.sourceTime(at: outputTime) ?? outputTime, outputTime: outputTime)
        }
        if !cursors.isEmpty {
            frame = Self.average(cursors).composited(over: frame)
        }
        let video = frame.cropped(to: videoRect)
        return settings.background == .none ? zoom(video, at: time) : placeOnBackground(video, at: time)
    }

    // MARK: - Motion blur

    /// How long the virtual shutter is open for each frame: half a frame at 60 fps, like a film camera.
    private static let shutter = 1.0 / 120
    /// The most moments averaged into one frame.
    private static let maxBlurSamples = 16

    /// The scene, blurred along the way things move while the shutter is open. When the camera moves,
    /// the whole scene is drawn at several moments and averaged; when only the cursor moves, just the
    /// cursor is. Still frames are drawn once.
    private func blurredScene(_ source: CIImage, at outputTime: Double) -> CIImage {
        guard settings.motionBlur else { return scene(source, at: outputTime) }
        let open = max(0, outputTime - Self.shutter / 2)
        let close = outputTime + Self.shutter / 2
        let (from, to) = (timeMap?.sourceTime(at: open) ?? open, timeMap?.sourceTime(at: close) ?? close)

        let cameraSamples = Self.sampleCount(forMotion: cameraMotion(from: from, to: to))
        let cursorSamples = Self.sampleCount(forMotion: cursorMotion(from: from, to: to))
        if cameraSamples > 1 {
            let times = Self.moments(max(cameraSamples, cursorSamples), from: open, to: close)
            return Self.average(times.map { scene(source, at: $0) })
        }
        return scene(source, at: outputTime, cursorTimes: Self.moments(cursorSamples, from: open, to: close))
    }

    /// Enough moments that each is at most a couple of pixels from the next.
    private static func sampleCount(forMotion pixels: CGFloat) -> Int {
        pixels < 2 ? 1 : min(Int((pixels / 2).rounded(.up)) + 1, maxBlurSamples)
    }

    /// `count` evenly spaced times from `start` to `end`, or just the middle for one.
    private static func moments(_ count: Int, from start: Double, to end: Double) -> [Double] {
        guard count > 1 else { return [(start + end) / 2] }
        return (0..<count).map { start + (end - start) * Double($0) / Double(count - 1) }
    }

    /// How far, in canvas pixels, the recording's corners move between two times.
    private func cameraMotion(from a: Double, to b: Double) -> CGFloat {
        let (start, end) = (videoToCanvas(at: a), videoToCanvas(at: b))
        let rect = CGRect(origin: .zero, size: videoSize)
        return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
            .map { Self.distance($0.applying(start), $0.applying(end)) }
            .max() ?? 0
    }

    /// How far, in canvas pixels, the cursor moves between two times.
    private func cursorMotion(from a: Double, to b: Double) -> CGFloat {
        guard let cursorPath, let start = cursorPath.position(at: a), let end = cursorPath.position(at: b) else { return 0 }
        let transform = videoToCanvas(at: b)
        let point = { (position: CGPoint) in
            CGPoint(x: position.x * self.videoSize.width, y: (1 - position.y) * self.videoSize.height).applying(transform)
        }
        return Self.distance(point(start), point(end))
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Images mixed equally, each at `1 / count` opacity and added up.
    private static func average(_ images: [CIImage]) -> CIImage {
        guard images.count > 1 else { return images.first ?? .empty() }
        let weight = 1 / CGFloat(images.count)
        return images
            .map { $0.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: weight)]) }
            .reduce(CIImage.empty()) { sum, image in
                image.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: sum])
            }
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

    /// The webcam in its bubble, with a border and a soft shadow. It sits on the finished frame, so it
    /// isn't zoomed and stays where it's placed. Below a `visibility` of 1 it's shrinking and fading away.
    private func bubble(_ webcam: CIImage, visibility: Double) -> CIImage? {
        let extent = webcam.extent
        guard !extent.isInfinite, extent.width > 0, extent.height > 0 else { return nil }

        let size = settings.webcamFrameSize(in: canvasSize)
        // Settings measure from the top left; Core Image from the bottom left.
        let topLeftCenter = settings.webcamCenter(in: canvasSize)
        let center = CGPoint(x: topLeftCenter.x, y: canvasSize.height - topLeftCenter.y)
        let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let radius = settings.webcamCornerRadius(in: canvasSize)
        let shorterSide = min(size.width, size.height)

        // Fill the bubble with the camera, zoomed in and moved to the chosen part of it, and mirrored
        // like a camera preview unless turned off. The camera can move as far as it overhangs the bubble.
        let scale = max(size.width / extent.width, size.height / extent.height) * max(settings.webcamZoom, 1)
        let overhang = CGSize(width: (extent.width * scale - size.width) / 2, height: (extent.height * scale - size.height) / 2)
        let offset = CGPoint(x: -settings.webcamFocusX * overhang.width, y: settings.webcamFocusY * overhang.height)
        let camera = webcam.transformed(by: CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
            .concatenating(CGAffineTransform(scaleX: settings.webcamMirrored ? -scale : scale, y: scale))
            .concatenating(CGAffineTransform(translationX: center.x + offset.x, y: center.y + offset.y)))
        var bubble = camera.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: roundedRectangle(rect, radius: radius, color: .white),
        ])

        if let color = settings.webcamBorderRGB {
            let width = max(shorterSide * settings.webcamBorderWidth, 1)
            // White is a little see-through so it doesn't glare.
            let alpha = settings.webcamBorder == .white ? 0.85 : 1
            let border = roundedRectangle(
                rect.insetBy(dx: -width, dy: -width),
                radius: radius > 0 ? radius + width : 0,
                color: CIColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha)
            )
            bubble = bubble.composited(over: border)
        }
        if settings.webcamShadow {
            let shadow = roundedRectangle(rect.offsetBy(dx: 0, dy: -shorterSide * 0.03), radius: radius, color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.4))
                .applyingGaussianBlur(sigma: shorterSide * 0.05)
            bubble = bubble.composited(over: shadow)
        }
        guard visibility < 1 else { return bubble }

        // Shrink a little while fading, so it eases away rather than blinking off.
        return bubble
            .transformed(by: Self.scale(around: center, by: 0.8 + 0.2 * visibility))
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: visibility)])
    }

    /// How far zoomed in the view is at `time`, from 0 to 1.
    private func zoomState(at time: Double) -> AutoZoom.State {
        guard settings.autoZoom else { return AutoZoom.State() }
        let state = AutoZoom.state(at: time, segments: zoomSegments, defaultLevel: settings.zoomLevel, defaultTransition: settings.zoomTransition)
        return state.amount > 0.001 ? state : AutoZoom.State()
    }

    /// Without a background: the recording grows by the zoom level towards the camera's focus, and the
    /// view stops at the recording's edges.
    private func zoom(_ frame: CIImage, at time: Double) -> CIImage {
        let rect = CGRect(origin: .zero, size: videoSize)
        guard let zoom = zoomCamera(at: time, window: rect) else { return frame }
        return frame.transformed(by: Self.scale(around: zoom.anchor, by: zoom.scale)).cropped(to: rect)
    }

    /// Where the recording sits on the canvas before any zoom, and how much it's scaled down to fit:
    /// the whole canvas without a background, or the area inside the padding with one.
    private var windowLayout: (frame: CGRect, scale: CGFloat) {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        guard settings.background != .none else { return (canvas, 1) }
        let inset = settings.padding * min(canvas.width, canvas.height)
        let scale = min(
            (canvas.width - 2 * inset) / videoSize.width,
            (canvas.height - 2 * inset) / videoSize.height
        )
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return (CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height), scale)
    }

    /// The zoom at `time`, as a scale around a fixed point on the canvas, or `nil` when not zoomed in.
    private func zoomCamera(at time: Double, window: CGRect) -> (anchor: CGPoint, scale: CGFloat)? {
        let state = zoomState(at: time)
        guard state.amount > 0 else { return nil }
        let focusFraction = camera?.focus(at: time) ?? CGPoint(x: 0.5, y: 0.5)
        let focus = CGPoint(x: window.minX + focusFraction.x * window.width, y: window.minY + (1 - focusFraction.y) * window.height)
        return Self.camera(level: state.level, amount: state.amount, focus: focus, frame: CGRect(origin: .zero, size: canvasSize))
    }

    /// Where a point of the recording shows up on the canvas at `time`, after placing and zooming.
    private func videoToCanvas(at time: Double) -> CGAffineTransform {
        let (frame, scale) = windowLayout
        let placed = CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: frame.minX, y: frame.minY))
        guard let zoom = zoomCamera(at: time, window: frame) else { return placed }
        return placed.concatenating(Self.scale(around: zoom.anchor, by: zoom.scale))
    }

    /// The camera for a zoom: the picture grows by up to `level` around one fixed anchor point. The
    /// anchor is chosen so that, fully zoomed in, the view is centred on `focus` but stops at the edges
    /// of `frame`. Growing around a fixed point means the zoom moves in one smooth line, never
    /// changing direction, like a camera moving in.
    private static func camera(level: Double, amount: Double, focus: CGPoint, frame: CGRect) -> (anchor: CGPoint, scale: CGFloat) {
        let view = CGSize(width: frame.width / level, height: frame.height / level)
        let center = CGPoint(
            x: clamp(focus.x, between: frame.minX + view.width / 2, and: frame.maxX - view.width / 2),
            y: clamp(focus.y, between: frame.minY + view.height / 2, and: frame.maxY - view.height / 2)
        )
        // Fully zoomed in, `center` lands in the middle of the frame: x' = middle + level × (x − center).
        // That transform leaves exactly one point where it was, which is the anchor.
        let anchor = CGPoint(
            x: (level * center.x - frame.midX) / (level - 1),
            y: (level * center.y - frame.midY) / (level - 1)
        )
        return (anchor, 1 + (level - 1) * amount)
    }

    /// Scales by `scale` while leaving `point` where it is.
    private static func scale(around point: CGPoint, by scale: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: -point.x, y: -point.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: point.x, y: point.y))
    }

    /// Shrinks the video into the padded area of the canvas, rounds its corners and puts it on the
    /// background with a soft shadow, like a window.
    ///
    /// Zooming works like a camera moving in on the whole picture: the window, with its corners and
    /// shadow, grows by the zoom level towards the point being zoomed in on, and the view stops at the
    /// edges of the frame, so near the window's edge the background beside it stays in view. The
    /// background itself grows only `parallax` as much as the window (by default not at all), which
    /// gives a sense of depth.
    private func placeOnBackground(_ video: CIImage, at time: Double) -> CIImage {
        guard let (topLeft, bottomRight) = settings.background.colors else { return video }

        let canvas = CGRect(origin: .zero, size: canvasSize)
        let shorterSide = min(canvas.width, canvas.height)
        let (frame, scale) = windowLayout
        let radius = settings.cornerRadius * pixelsPerPoint * scale

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

        // The background isn't cropped until the end, so it still fills the frame once it's moved.
        // An image's edge pixels are stretched outwards for the same reason.
        var background: CIImage
        if settings.background == .image, let backgroundImage {
            background = backgroundImage.clampedToExtent()
        } else {
            let gradient = CIFilter.linearGradient()
            gradient.point0 = CGPoint(x: canvas.minX, y: canvas.maxY)
            gradient.point1 = CGPoint(x: canvas.maxX, y: canvas.minY)
            gradient.color0 = CIColor(topLeft)
            gradient.color1 = CIColor(bottomRight)
            background = gradient.outputImage ?? CIImage(color: CIColor(topLeft))
        }

        if let (anchor, windowScale) = zoomCamera(at: time, window: frame) {
            window = window.transformed(by: Self.scale(around: anchor, by: windowScale))
            background = background.transformed(by: Self.scale(around: anchor, by: 1 + (windowScale - 1) * settings.parallax))
        }

        return window.composited(over: background).cropped(to: canvas)
    }

    /// Keeps `value` between two limits given in either order.
    private static func clamp(_ value: CGFloat, between a: CGFloat, and b: CGFloat) -> CGFloat {
        min(max(value, min(a, b)), max(a, b))
    }

    private func roundedRectangle(_ rect: CGRect, radius: CGFloat, color: CIColor) -> CIImage {
        let generator = CIFilter.roundedRectangleGenerator()
        generator.extent = rect
        generator.radius = Float(radius)
        generator.color = color
        return generator.outputImage ?? .empty()
    }

    private func cursorLayer(at time: Double, outputTime: Double) -> CIImage? {
        guard let cursorPath, let sprites, var position = cursorPath.position(at: time) else { return nil }
        let sprite = settings.cursorShapes ? sprites.sprite(at: time) : sprites.arrow
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
