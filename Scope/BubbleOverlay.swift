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
            let diameter = settings.webcamDiameter(in: canvasSize) * scale
            let center = settings.webcamCenter(in: canvasSize)

            outline
                .frame(width: diameter, height: diameter)
                .contentShape(settings.webcamShape == .circle ? AnyShape(Circle()) : AnyShape(Rectangle()))
                .position(x: video.minX + center.x * scale, y: video.minY + center.y * scale)
                .onHover { isHovering = $0 }
                .gesture(
                    DragGesture()
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

    @ViewBuilder
    private var outline: some View {
        let visible = isHovering || dragStart != nil
        Group {
            if settings.webcamShape == .circle {
                Circle().strokeBorder(Color.accentColor, lineWidth: 2)
            } else {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: geometry.size.width * 0.18, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .opacity(visible ? 1 : 0)
    }
}
