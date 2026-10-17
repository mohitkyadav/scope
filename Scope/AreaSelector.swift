//
//  AreaSelector.swift
//  Scope
//

import AppKit
import SwiftUI

/// Part of a display to record, in points from the display's top left.
struct ScreenRegion: Equatable {
    var displayID: CGDirectDisplayID
    var rect: CGRect
}

/// Lets the user drag out an area of the screen to record, like ⌘⇧4: every screen dims, and
/// dragging on one of them picks a rectangle there. Escape cancels.
enum AreaSelector {
    /// Areas smaller than this, in points, are taken as a stray click rather than a selection.
    static let minimumSize: CGFloat = 40

    /// Returns the chosen area, or `nil` if it was cancelled. `current` is shown to start with.
    static func select(current: ScreenRegion?) async -> ScreenRegion? {
        let session = SelectionSession()
        return await withCheckedContinuation { continuation in
            session.begin(current: current) { continuation.resume(returning: $0) }
        }
    }
}

@MainActor
private final class SelectionSession {
    private var panels: [NSPanel] = []
    private var keyMonitor: Any?
    private var completion: ((ScreenRegion?) -> Void)?
    private let model = SelectionModel()

    func begin(current: ScreenRegion?, completion: @escaping (ScreenRegion?) -> Void) {
        self.completion = completion
        model.current = current

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let panel = KeyPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.sharingType = .none
            panel.acceptsMouseMovedEvents = true
            panel.contentView = NSHostingView(rootView: SelectionView(
                model: model,
                displayID: displayID,
                scale: screen.backingScaleFactor,
                finish: { [weak self] region in self?.end(region) }
            ))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        NSApp.activate()
        let screenUnderMouse = NSScreen.screens.firstIndex { $0.frame.contains(NSEvent.mouseLocation) } ?? 0
        if panels.indices.contains(screenUnderMouse) {
            panels[screenUnderMouse].makeKey()
        }
        NSCursor.crosshair.push()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch Int(event.keyCode) {
            case 53: // Escape
                self?.end(nil)
                return nil
            case 36, 76: // Return keeps the area already chosen.
                self?.end(self?.model.current)
                return nil
            default:
                return event
            }
        }
    }

    private func end(_ region: ScreenRegion?) {
        guard let completion else { return }
        self.completion = nil
        NSCursor.pop()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        completion(region)
    }
}

/// A borderless panel that can still take key presses, for Escape and Return.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@Observable
private final class SelectionModel {
    /// The area chosen before, shown until a new one is dragged out.
    var current: ScreenRegion?
    /// The area being dragged out.
    var dragging: ScreenRegion?
}

private struct SelectionView: View {
    let model: SelectionModel
    let displayID: CGDirectDisplayID
    let scale: CGFloat
    let finish: (ScreenRegion?) -> Void

    var body: some View {
        GeometryReader { geometry in
            let rect = shownRect
            ZStack(alignment: .topLeading) {
                // Dim everything but the area.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    if let rect {
                        path.addRect(rect)
                    }
                }
                .fill(.black.opacity(0.4), style: FillStyle(eoFill: true))

                if let rect {
                    Rectangle()
                        .strokeBorder(.white, lineWidth: 1.5)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                    sizeLabel(for: rect, in: geometry.size)
                }

                hint
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                    .padding(.top, 60)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        let rect = CGRect(
                            x: min(drag.startLocation.x, drag.location.x),
                            y: min(drag.startLocation.y, drag.location.y),
                            width: abs(drag.location.x - drag.startLocation.x),
                            height: abs(drag.location.y - drag.startLocation.y)
                        )
                        .intersection(CGRect(origin: .zero, size: geometry.size))
                        model.dragging = ScreenRegion(displayID: displayID, rect: rect)
                    }
                    .onEnded { _ in
                        guard let dragging = model.dragging else { return }
                        model.dragging = nil
                        // Whole points, so the video's size comes out exact.
                        let rect = dragging.rect.integral
                        guard rect.width >= AreaSelector.minimumSize, rect.height >= AreaSelector.minimumSize else { return }
                        finish(ScreenRegion(displayID: displayID, rect: rect))
                    }
            )
        }
        .ignoresSafeArea()
    }

    /// The area to show on this screen: the one being dragged, or else the one chosen before.
    private var shownRect: CGRect? {
        if let dragging = model.dragging {
            return dragging.displayID == displayID ? dragging.rect : nil
        }
        return model.current?.displayID == displayID ? model.current?.rect : nil
    }

    /// The area's size in pixels, under it, or above it near the bottom of the screen.
    private func sizeLabel(for rect: CGRect, in size: CGSize) -> some View {
        let text = "\(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded()))"
        let below = rect.maxY + 34 < size.height
        return Text(text)
            .font(.callout.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.black.opacity(0.7), in: .capsule)
            .fixedSize()
            .position(x: rect.midX, y: below ? rect.maxY + 18 : rect.minY - 18)
    }

    private var hint: some View {
        Text(model.current == nil
             ? "Drag to choose an area to record · Esc to cancel"
             : "Drag to choose a new area · Return to keep this one · Esc to cancel")
            .font(.title3.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: .capsule)
    }
}

/// A thin outline just outside the area being recorded, so it's clear what's in the video. It
/// sits outside the area and is hidden from screen capture, so it never shows in the recording.
@MainActor
final class AreaOutline {
    private var panel: NSPanel?
    private var region: ScreenRegion?

    func show(_ region: ScreenRegion) {
        guard region != self.region || panel == nil else { return }
        hide()
        self.region = region
        guard let screen = NSScreen.screens.first(where: { $0.displayID == region.displayID }) else { return }
        let inset: CGFloat = -3
        // AppKit measures from the bottom left of the main screen; the region from its display's top left.
        let frame = CGRect(
            x: screen.frame.minX + region.rect.minX,
            y: screen.frame.maxY - region.rect.maxY,
            width: region.rect.width,
            height: region.rect.height
        ).insetBy(dx: inset, dy: inset)

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView:
            Rectangle()
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        region = nil
    }
}
