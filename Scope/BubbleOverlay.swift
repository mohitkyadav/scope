//
//  BubbleOverlay.swift
//  Scope
//

import AVFoundation
import SwiftUI

/// An invisible handle over the webcam bubble in the preview, so it can be dragged around.
/// It outlines the bubble while hovered or dragged.
struct BubbleOverlay: View {
    @Binding var settings: EditorSettings
    /// The size of the rendered frame, which the preview shows scaled to fit.
    let canvasSize: CGSize

    @State private var dragStart: CGPoint?
    @State private var isHovering = false

    var body: some View {
        GeometryReader { geometry in
            let video = AVMakeRect(aspectRatio: canvasSize, insideRect: CGRect(origin: .zero, size: geometry.size))
            let scale = video.width / max(canvasSize.width, 1)
            let size = settings.webcamFrameSize(in: canvasSize)
            // Circular corners, like the rendered bubble, so a circle stays a circle.
            let shape = RoundedRectangle(cornerRadius: settings.webcamCornerRadius(in: canvasSize) * scale, style: .circular)
            let center = settings.webcamCenter(in: canvasSize)

            shape
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isHovering || dragStart != nil ? 1 : 0)
                .frame(width: size.width * scale, height: size.height * scale)
                .contentShape(shape)
                .position(x: video.minX + center.x * scale, y: video.minY + center.y * scale)
                .onHover { isHovering = $0 }
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { drag in
                            let start = dragStart ?? CGPoint(x: center.x / canvasSize.width, y: center.y / canvasSize.height)
                            dragStart = start
                            settings.webcamX = min(max(start.x + drag.translation.width / video.width, 0), 1)
                            settings.webcamY = min(max(start.y + drag.translation.height / video.height, 0), 1)
                        }
                        .onEnded { _ in
                            dragStart = nil
                        }
                )
                .help("Drag to move the webcam")
                .accessibilityLabel("Webcam bubble")
                .accessibilityHint("Drag to move it")
        }
    }
}
