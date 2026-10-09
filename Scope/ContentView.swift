//
//  ContentView.swift
//  Scope
//

import AppKit
import SwiftUI

struct ContentView: View {
    @State private var permission = ScreenRecordingPermission()
    @State private var displayList = DisplayList()
    @State private var library = RecordingLibrary()
    @Environment(Recorder.self) private var recorder
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

            if library.recordings.isEmpty {
                ContentUnavailableView(
                    "No Recordings",
                    systemImage: "film.stack",
                    description: Text("Recordings you make will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RecordingsList(library: library)
            }

            Divider()

            HStack(spacing: 16) {
                if permission.isGranted {
                    DisplayPicker(displayList: displayList)
                        .disabled(recorder.state != .idle)
                }

                Spacer(minLength: 0)

                RecordButton(isRecording: recorder.isRecording, elapsed: recorder.elapsed) {
                    Task { await toggleRecording() }
                }
                .disabled(!canRecord)
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 360)
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                permission.refresh()
                Task { await library.reload() }
            }
        }
        .onChange(of: recorder.lastRecordingURL) {
            Task { await library.reload() }
        }
        .task {
            await library.reload()
        }
        .task(id: permission.isGranted) {
            guard permission.isGranted else { return }
            await displayList.load()
        }
        .alert(
            "Recording failed",
            isPresented: Binding(
                get: { recorder.errorMessage != nil },
                set: { if !$0 { recorder.errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(recorder.errorMessage ?? "")
        }
        .task {
            // Reload when a monitor is plugged in, unplugged or changes resolution.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                guard permission.isGranted else { continue }
                await displayList.load()
            }
        }
    }

    private var canRecord: Bool {
        switch recorder.state {
        case .idle: permission.isGranted && displayList.selected != nil
        case .recording: true
        case .countingDown, .stopping: false
        }
    }

    private func toggleRecording() async {
        if recorder.isRecording {
            await recorder.stop()
            return
        }

        guard let filter = displayList.selectedFilter else { return }
        do {
            await recorder.start(filter: filter, outputURL: try RecordingLibrary.newRecordingURL())
        } catch {
            recorder.errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
        .environment(Recorder())
}
