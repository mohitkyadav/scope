//
//  SceneCompositor.swift
//  Scope
//

import AVFoundation
import CoreImage

/// Hands the frame renderer and the tracks it draws from to `SceneCompositor`.
nonisolated final class SceneInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    /// Frames change even when the source video doesn't (the cursor moves, the view pans), so render every one.
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let renderer: FrameRenderer
    let screenTrackID: CMPersistentTrackID
    let webcamTrackID: CMPersistentTrackID?

    init(timeRange: CMTimeRange, renderer: FrameRenderer, screenTrackID: CMPersistentTrackID, webcamTrackID: CMPersistentTrackID?) {
        self.timeRange = timeRange
        self.renderer = renderer
        self.screenTrackID = screenTrackID
        self.webcamTrackID = webcamTrackID
        requiredSourceTrackIDs = ([screenTrackID] + [webcamTrackID].compactMap { $0 }).map { NSNumber(value: $0) }
    }
}

/// Draws each frame of a project from its screen and webcam videos using `FrameRenderer`.
/// AVFoundation creates this itself, for the editor's player and later for export.
nonisolated final class SceneCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = CIContext()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? SceneInstruction,
              let output = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: AVError(.unknown))
            return
        }

        // Either can be missing: before the first screen frame, or outside the webcam's time range.
        let screen = request.sourceFrame(byTrackID: instruction.screenTrackID).map { CIImage(cvPixelBuffer: $0) }
        let webcam = instruction.webcamTrackID
            .flatMap { request.sourceFrame(byTrackID: $0) }
            .map { CIImage(cvPixelBuffer: $0) }

        var frame = instruction.renderer.render(source: screen, webcam: webcam, time: request.compositionTime.seconds)
        // Exports can be smaller than the recording.
        let size = request.renderContext.size
        let canvas = instruction.renderer.canvasSize
        if size != canvas, canvas.width > 0, canvas.height > 0 {
            frame = frame.transformed(by: CGAffineTransform(scaleX: size.width / canvas.width, y: size.height / canvas.height))
        }
        context.render(frame, to: output, bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
        request.finish(withComposedVideoFrame: output)
    }
}
