//
//  DisplayList.swift
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

@Observable
final class DisplayList {
    private(set) var displays: [Display] = []
    private(set) var errorMessage: String?
    var selectedID: CGDirectDisplayID?

    var selected: Display? { displays.first { $0.id == selectedID } }

    func load() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            displays = content.displays.map(Display.init)
            errorMessage = nil
        } catch {
            displays = []
            errorMessage = error.localizedDescription
        }

        // Keep the current choice if it's still connected, otherwise fall back to the main display.
        if selected == nil {
            selectedID = displays.first { CGDisplayIsMain($0.id) != 0 }?.id ?? displays.first?.id
        }
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

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
