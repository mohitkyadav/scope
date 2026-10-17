//
//  ZoomAreaPicker.swift
//  Scope
//

import SwiftUI

/// A frame of the recording with the part a zoom shows marked by a box. Drag the box to move it,
/// drag one of its corners to zoom in or out, or click anywhere to centre it there.
struct ZoomAreaPicker: View {
    let image: CGImage?
    /// The recording's width divided by its height.
    let aspectRatio: CGFloat
    /// The box's centre and size as fractions of the recording, from the top left.
    let center: CGPoint
    let size: CGSize
    /// Whether the centre was picked by hand, rather than worked out from the clicks.
    let isPicked: Bool
    /// Called while dragging with the box's new centre, or with the size the box is being dragged
    /// to, and then with the change's name for undo once the drag ends.
    let onMove: (CGPoint) -> Void
    let onResize: (CGSize) -> Void
    let onEnded: (String) -> Void

    private enum Drag {
        /// The box's centre minus where the drag started, as fractions.
        case move(offset: CGSize)
        case resize
    }

    @State private var drag: Drag?

    /// How close to a corner, in points, a drag has to start to resize the box.
    private static let handleReach: CGFloat = 14

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geometry in
                    let bounds = geometry.size
                    let box = box(in: bounds)
                    ZStack(alignment: .topLeading) {
                        if let image {
                            Image(decorative: image, scale: 1)
                                .resizable()
                        } else {
                            Color.secondary.opacity(0.15)
                        }
                        // Darken what the zoom leaves out.
                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: bounds))
                            path.addRect(box)
                        }
                        .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))

                        Rectangle()
                            .strokeBorder(isPicked ? Color.accentColor : .white, style: StrokeStyle(lineWidth: 2, dash: isPicked ? [] : [5, 3]))
                            .frame(width: box.width, height: box.height)
                            .offset(x: box.minX, y: box.minY)
                        ForEach(Array(Self.corners(of: box).enumerated()), id: \.offset) { _, corner in
                            Circle()
                                .fill(.white)
                                .stroke(isPicked ? Color.accentColor : .secondary, lineWidth: 1)
                                .frame(width: 8, height: 8)
                                .position(corner)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(dragGesture(bounds: bounds, box: box))
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .accessibilityElement()
            .accessibilityLabel("Zoom area")
            .accessibilityValue(isPicked ? "Picked by hand" : "Automatic")
            .accessibilityHint("Drag to choose what the zoom shows")
    }

    /// The box in points, kept inside the frame.
    private func box(in bounds: CGSize) -> CGRect {
        let width = min(size.width, 1) * bounds.width
        let height = min(size.height, 1) * bounds.height
        let center = Self.clamp(center, size: size)
        return CGRect(x: center.x * bounds.width - width / 2, y: center.y * bounds.height - height / 2, width: width, height: height)
    }

    private func dragGesture(bounds: CGSize, box: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard bounds.width > 0, bounds.height > 0 else { return }
                let location = CGPoint(x: value.location.x / bounds.width, y: value.location.y / bounds.height)
                if drag == nil {
                    let start = value.startLocation
                    let nearCorner = Self.corners(of: box).contains { hypot($0.x - start.x, $0.y - start.y) <= Self.handleReach }
                    if nearCorner {
                        drag = .resize
                    } else if box.contains(start) {
                        let center = Self.clamp(center, size: size)
                        drag = .move(offset: CGSize(width: center.x - start.x / bounds.width, height: center.y - start.y / bounds.height))
                    } else {
                        // A click outside the box centres it there.
                        drag = .move(offset: .zero)
                    }
                }
                switch drag {
                case .move(let offset):
                    onMove(Self.clamp(CGPoint(x: location.x + offset.width, y: location.y + offset.height), size: size))
                case .resize:
                    let center = Self.clamp(center, size: size)
                    onResize(CGSize(width: 2 * abs(location.x - center.x), height: 2 * abs(location.y - center.y)))
                case nil:
                    break
                }
            }
            .onEnded { _ in
                if let drag {
                    if case .resize = drag {
                        onEnded("Change Zoom Level")
                    } else {
                        onEnded("Move Zoom")
                    }
                }
                drag = nil
            }
    }

    /// Keeps a box of `size` centred on `point` inside the frame.
    private static func clamp(_ point: CGPoint, size: CGSize) -> CGPoint {
        func clamp(_ value: CGFloat, _ extent: CGFloat) -> CGFloat {
            extent >= 1 ? 0.5 : min(max(value, extent / 2), 1 - extent / 2)
        }
        return CGPoint(x: clamp(point.x, size.width), y: clamp(point.y, size.height))
    }

    private static func corners(of box: CGRect) -> [CGPoint] {
        [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
         CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
    }
}
