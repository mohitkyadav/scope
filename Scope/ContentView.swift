//
//  ContentView.swift
//  Scope
//

import AppKit
import AVFoundation
import SwiftUI

struct ContentView: View {
    @State private var permission = ScreenRecordingPermission()
    @State private var sources = CaptureSources()
    @State private var library = RecordingLibrary()
    @State private var audio = AudioSettings()
    @State private var camera = CameraSettings()
    @State private var microphoneMeter = AudioMeter()
    @State private var systemAudioMeter = AudioMeter()
    @State private var areaOutline = AreaOutline()
    @Environment(Recorder.self) private var recorder
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    private let opener = ProjectOpener.shared
    private let projectFolder = ProjectFolder.shared

    var body: some View {
        VStack(spacing: 0) {
            if !permission.isGranted {
                PermissionBanner(openSettings: permission.request)
                    .padding([.horizontal, .top], 20)
            }

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

            if permission.isGranted {
                RecordingPanel(
                    sources: sources,
                    audio: audio,
                    camera: camera,
                    microphoneLevel: microphoneMeter.level,
                    systemAudioLevel: systemAudioMeter.level,
                    recorder: recorder,
                    canRecord: canRecord
                ) {
                    Task { await toggleRecording() }
                }
                .padding(16)
            }
        }
        .toolbar {
            AppTitleToolbarItem()
            TrailingSpace()
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .help("Settings")
            }
        }
        .toolbar(removing: .title)
        .frame(minWidth: 720, minHeight: 520)
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                permission.refresh()
                projectFolder.refresh()
                Task { await library.reload() }
                // Windows come and go while Scope is in the background.
                if permission.isGranted {
                    Task { await sources.load() }
                }
            }
        }
        .onChange(of: recorder.state) {
            // Outline the area while it's being recorded, from the countdown on.
            if recorder.state == .countingDown || recorder.state == .recording, sources.kind == .area, let region = sources.selectedRegion {
                areaOutline.show(region)
            } else if recorder.state == .idle || recorder.state == .stopping {
                areaOutline.hide()
            }
        }
        .onChange(of: recorder.lastProject) {
            Task { await library.reload() }
        }
        .onChange(of: projectFolder.url) {
            Task { await library.reload() }
        }
        .onChange(of: opener.pending, initial: true) {
            for project in opener.takePending() {
                openWindow(id: EditorView.windowID, value: project.url)
            }
        }
        .task {
            await library.reload()
        }
        .task {
            audio.loadMicrophones()
            camera.loadCameras()
            if audio.microphoneEnabled {
                await audio.requestMicrophoneAccess()
            }
            if camera.cameraEnabled {
                await camera.requestCameraAccess()
            }
            // Reload when a microphone or camera is plugged in.
            for await _ in NotificationCenter.default.notifications(named: AVCaptureDevice.wasConnectedNotification) {
                audio.loadMicrophones()
                camera.loadCameras()
            }
        }
        .task(id: microphoneToMeter) {
            guard let microphoneToMeter else { return }
            await microphoneMeter.runMicrophone(deviceID: microphoneToMeter)
        }
        .task(id: systemAudioToMeter) {
            guard systemAudioToMeter != nil, let filter = sources.selectedFilter else { return }
            await systemAudioMeter.runSystemAudio(filter: filter)
        }
        .task {
            // ...or unplugged.
            for await _ in NotificationCenter.default.notifications(named: AVCaptureDevice.wasDisconnectedNotification) {
                audio.loadMicrophones()
                camera.loadCameras()
            }
        }
        .task(id: permission.isGranted) {
            guard permission.isGranted else { return }
            await sources.load()
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
                await sources.load()
            }
        }
    }

    /// Meters only run while Scope is in front or recording, so the mic and screen
    /// recording indicators aren't left on the rest of the time.
    private var metersActive: Bool {
        scenePhase == .active || recorder.state != .idle
    }

    private var microphoneToMeter: String? {
        metersActive ? audio.microphoneToRecord?.id : nil
    }

    /// Changes whenever the system audio meter should restart with a different source.
    private var systemAudioToMeter: String? {
        guard metersActive, audio.systemAudioEnabled, permission.isGranted else { return nil }
        switch sources.kind {
        case .display: return "display-\(sources.selectedDisplayID ?? 0)"
        case .window: return "window-\(sources.selectedWindowID ?? 0)"
        case .area: return "display-\(sources.selectedRegion?.displayID ?? 0)"
        }
    }

    private var canRecord: Bool {
        switch recorder.state {
        case .idle: permission.isGranted && sources.hasSelection
        case .countingDown, .recording: true
        case .stopping: false
        }
    }

    private func toggleRecording() async {
        switch recorder.state {
        case .idle:
            guard let filter = sources.selectedFilter, let area = sources.selectedArea else { return }
            await recorder.start(
                filter: filter,
                area: area,
                microphoneID: audio.microphoneToRecord?.id,
                systemAudio: audio.systemAudioEnabled,
                cameraID: camera.cameraToRecord?.id,
                project: RecordingLibrary.newProject(),
                countdownScreen: sources.selectedScreen
            )
        case .countingDown:
            recorder.cancelCountdown()
        case .recording:
            await recorder.stop()
        case .stopping:
            break
        }
    }
}

/// Scope's icon and name at the top left of the main window.
private struct AppTitleToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) { title }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { title }
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
            Text("Scope")
                .font(.title3.weight(.semibold))
        }
        .padding(.leading, 4)
    }
}

#Preview {
    ContentView()
        .environment(Recorder())
}
