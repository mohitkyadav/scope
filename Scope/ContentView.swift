//
//  ContentView.swift
//  Scope
//

import SwiftUI

struct ContentView: View {
    @State private var permission = ScreenRecordingPermission()
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

            RecordButton {
                // Recording starts in step 1.2.
            }
            .disabled(!permission.isGranted)
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 360)
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                permission.refresh()
            }
        }
    }
}

#Preview {
    ContentView()
}
