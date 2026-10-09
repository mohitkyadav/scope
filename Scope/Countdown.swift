//
//  Countdown.swift
//  Scope
//

import AppKit
import Observation
import SwiftUI

/// A 3-2-1 countdown shown in the middle of a screen before recording starts.
enum Countdown {
    /// Returns `false` if the countdown was cancelled.
    static func run(on screen: NSScreen) async -> Bool {
        let model = CountdownModel()

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: CountdownView(model: model))
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }

        for value in [3, 2, 1] {
            model.value = value
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return false
            }
        }
        return true
    }
}

@Observable
private final class CountdownModel {
    var value = 3
}

private struct CountdownView: View {
    let model: CountdownModel

    var body: some View {
        VStack(spacing: 16) {
            Text("\(model.value)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: model.value)
                .frame(width: 220, height: 220)
                .background(.ultraThinMaterial, in: .circle)

            Text("Press \(Recorder.stopShortcut) to stop recording")
                .font(.title3.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: .capsule)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
