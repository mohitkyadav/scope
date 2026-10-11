//
//  CaptureSources.swift
//  Scope
//

import AppKit
import Observation
import ScreenCaptureKit

struct Display: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let scDisplay: SCDisplay

    var resolution: String { "\(pixelWidth) × \(pixelHeight)" }
}

struct CaptureWindow: Identifiable {
    let id: CGWindowID
    let appName: String
    let title: String
    let scWindow: SCWindow
    /// The icon of the app the window belongs to.
    let icon: NSImage?

    var label: String { "\(appName) — \(title)" }
}

/// The displays and windows Scope can record, and which one is selected.
@Observable
final class CaptureSources {
    enum Kind: String, CaseIterable, Identifiable {
        case display = "Display"
        case window = "Window"

        var id: Self { self }
    }

    var kind: Kind = .display
    private(set) var displays: [Display] = []
    private(set) var windows: [CaptureWindow] = []
    private(set) var errorMessage: String?
    var selectedDisplayID: CGDirectDisplayID?
    var selectedWindowID: CGWindowID?
    private var ownApp: SCRunningApplication?

    var selectedDisplay: Display? { displays.first { $0.id == selectedDisplayID } }
    var selectedWindow: CaptureWindow? { windows.first { $0.id == selectedWindowID } }

    var hasSelection: Bool {
        switch kind {
        case .display: selectedDisplay != nil
        case .window: selectedWindow != nil
        }
    }

    /// What to record. For a display, Scope's own windows are left out of the video.
    /// A window is captured on its own, so it still records when other windows cover it.
    var selectedFilter: SCContentFilter? {
        switch kind {
        case .display:
            guard let selectedDisplay else { return nil }
            return SCContentFilter(
                display: selectedDisplay.scDisplay,
                excludingApplications: ownApp.map { [$0] } ?? [],
                exceptingWindows: []
            )
        case .window:
            guard let selectedWindow else { return nil }
            return SCContentFilter(desktopIndependentWindow: selectedWindow.scWindow)
        }
    }

    /// Where the selection is on screen, for recording cursor positions relative to it.
    var selectedArea: CaptureArea? {
        switch kind {
        case .display: selectedDisplayID.map(CaptureArea.display)
        case .window: selectedWindowID.map(CaptureArea.window)
        }
    }

    /// The screen the countdown appears on: the chosen display, or the one the chosen window is on.
    var selectedScreen: NSScreen? {
        switch kind {
        case .display:
            return NSScreen.screens.first { $0.displayID == selectedDisplayID }
        case .window:
            guard let frame = selectedWindow?.scWindow.frame else { return nil }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return NSScreen.screens.first { screen in
                screen.displayID.map { CGDisplayBounds($0).contains(center) } ?? false
            } ?? NSScreen.main
        }
    }

    func load() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            displays = content.displays.map(Display.init)
            windows = content.windows
                .filter(Self.isRecordable)
                .compactMap(CaptureWindow.init)
                .sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
            ownApp = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            errorMessage = nil
        } catch {
            displays = []
            windows = []
            errorMessage = error.localizedDescription
        }

        // Keep the current choices if they're still around, otherwise fall back to sensible defaults.
        if selectedDisplay == nil {
            selectedDisplayID = displays.first { CGDisplayIsMain($0.id) != 0 }?.id ?? displays.first?.id
        }
        if selectedWindow == nil {
            selectedWindowID = windows.first?.id
        }
    }

    /// Normal app windows only: no menu bar items, overlays, tiny helper windows or Scope itself.
    private static func isRecordable(_ window: SCWindow) -> Bool {
        window.windowLayer == 0
            && window.isOnScreen
            && window.frame.width >= 50
            && window.frame.height >= 50
            && window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
    }
}

private extension Display {
    init(_ display: SCDisplay) {
        let screen = NSScreen.screens.first { $0.displayID == display.displayID }
        let mode = CGDisplayCopyDisplayMode(display.displayID)

        id = display.displayID
        name = screen?.localizedName ?? "Display \(display.displayID)"
        pixelWidth = mode?.pixelWidth ?? display.width
        pixelHeight = mode?.pixelHeight ?? display.height
        scDisplay = display
    }
}

private extension CaptureWindow {
    init?(_ window: SCWindow) {
        guard let title = window.title, !title.isEmpty,
              let appName = window.owningApplication?.applicationName
        else { return nil }

        id = window.windowID
        self.appName = appName
        self.title = title
        scWindow = window
        icon = window.owningApplication.flatMap { NSRunningApplication(processIdentifier: $0.processID)?.icon }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
