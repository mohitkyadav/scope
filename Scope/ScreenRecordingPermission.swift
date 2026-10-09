//
//  ScreenRecordingPermission.swift
//  Scope
//

import AppKit
import CoreGraphics
import Observation

@Observable
final class ScreenRecordingPermission {
    private(set) var isGranted = CGPreflightScreenCaptureAccess()

    func refresh() {
        isGranted = CGPreflightScreenCaptureAccess()
    }

    /// Asks macOS for access, which also adds Scope to the list in System Settings,
    /// then opens that page so the user can turn it on.
    func request() {
        isGranted = CGRequestScreenCaptureAccess()
        guard !isGranted else { return }

        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
