//
//  SettingsView.swift
//  Scope
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Scope › Settings.
struct SettingsView: View {
    @AppStorage(RecordingPreferences.countdownKey) private var countdown = 3
    @AppStorage(RecordingPreferences.frameRateKey) private var frameRate = 60
    private let projectFolder = ProjectFolder.shared

    var body: some View {
        Form {
            Section("Recording") {
                Picker("Countdown", selection: $countdown) {
                    Text("Off").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                }
                Picker("Frame rate", selection: $frameRate) {
                    Text("60 fps").tag(60)
                    Text("30 fps").tag(30)
                }
                LabeledContent("Stop recording", value: "\(Recorder.stopShortcut) from any app")
            }

            Section {
                LabeledContent("Save projects to") {
                    HStack {
                        Picker("Save projects to", selection: folderChoice) {
                            FolderLabel(url: ProjectFolder.downloads).tag(FolderChoice.downloads)
                            if let chosen = projectFolder.chosen {
                                FolderLabel(url: chosen).tag(FolderChoice.chosen)
                            }
                            Divider()
                            Text("Choose Folder…").tag(FolderChoice.choose)
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Show in Finder") {
                            NSWorkspace.shared.open(projectFolder.url)
                        }
                    }
                }
            } header: {
                Text("Saving")
            } footer: {
                Group {
                    if projectFolder.isMissing, let chosen = projectFolder.chosen {
                        Text("“\(chosen.lastPathComponent)” can't be found, so new recordings go to Downloads until it's back.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("New recordings and exports are saved here. Existing projects stay where they are.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }

    private enum FolderChoice {
        case downloads, chosen, choose
    }

    /// "Choose Folder…" opens a panel instead of staying selected.
    private var folderChoice: Binding<FolderChoice> {
        Binding(
            get: { projectFolder.chosen == nil ? .downloads : .chosen },
            set: { choice in
                switch choice {
                case .downloads: projectFolder.useDownloads()
                case .chosen: break
                // Let the menu close before the panel opens.
                case .choose: DispatchQueue.main.async { projectFolder.choose() }
                }
            }
        )
    }
}

/// A folder's Finder icon and name, e.g. "Downloads".
private struct FolderLabel: View {
    let url: URL

    var body: some View {
        Label {
            Text(FileManager.default.displayName(atPath: url.path))
        } icon: {
            Image(nsImage: icon)
        }
    }

    private var icon: NSImage {
        let image = FileManager.default.fileExists(atPath: url.path)
            ? NSWorkspace.shared.icon(forFile: url.path)
            : NSWorkspace.shared.icon(for: .folder)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

#Preview {
    SettingsView()
}
