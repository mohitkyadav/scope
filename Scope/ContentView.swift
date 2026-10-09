//
//  ContentView.swift
//  Scope
//

import AppKit
import SwiftUI

struct ContentView: View {
    @State private var permission = ScreenRecordingPermission()
    @State private var displayList = DisplayList()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            if !permission.isGranted {
                PermissionBanner(openSettings: permission.request)
                    .padding([.horizontal, .top], 20)
            }

            Text("Recordings")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 20)

            ContentUnavailableView(
                "No Recordings",
                systemImage: "film.stack",
                description: Text("Recordings you make will appear here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 16) {
                if permission.isGranted {
                    DisplayPicker(displayList: displayList)
                }

                Spacer(minLength: 0)

                RecordButton {
                    // Recording starts in step 1.2.
                }
                .disabled(!permission.isGranted || displayList.selected == nil)
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 360)
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                permission.refresh()
            }
        }
        .task(id: permission.isGranted) {
            guard permission.isGranted else { return }
            await displayList.load()
        }
        .task {
            // Reload when a monitor is plugged in, unplugged or changes resolution.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                guard permission.isGranted else { continue }
                await displayList.load()
            }
        }
    }
}

#Preview {
    ContentView()
}
