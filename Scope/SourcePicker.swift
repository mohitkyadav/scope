//
//  SourcePicker.swift
//  Scope
//

import SwiftUI

struct SourcePicker: View {
    @Bindable var sources: CaptureSources

    var body: some View {
        if let errorMessage = sources.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                Picker("Source", selection: $sources.kind) {
                    ForEach(CaptureSources.Kind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                switch sources.kind {
                case .display:
                    Picker("Display", selection: $sources.selectedDisplayID) {
                        ForEach(sources.displays) { display in
                            Text("\(display.name) — \(display.resolution)")
                                .tag(Optional(display.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                case .window:
                    Picker("Window", selection: $sources.selectedWindowID) {
                        if sources.windows.isEmpty {
                            Text("No windows").tag(CGWindowID?.none)
                        }
                        ForEach(sources.windows) { window in
                            Text(window.label)
                                .tag(Optional(window.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)

                    Button {
                        Task { await sources.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh the window list")
                }
            }
        }
    }
}
