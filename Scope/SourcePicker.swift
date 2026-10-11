//
//  SourcePicker.swift
//  Scope
//

import SwiftUI

/// What to record: a Display / Window switch, then a pill showing the chosen display or window
/// (with its app's icon) that opens a menu of the others.
struct SourcePicker: View {
    @Bindable var sources: CaptureSources

    var body: some View {
        if let errorMessage = sources.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                PillPicker(options: CaptureSources.Kind.allCases.map { ($0, $0.rawValue) }, selection: $sources.kind)
                    .fixedSize()

                Menu {
                    menuItems
                } label: {
                    SourceLabel(icon: currentIcon, title: currentTitle)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        switch sources.kind {
        case .display:
            ForEach(sources.displays) { display in
                Button {
                    sources.selectedDisplayID = display.id
                } label: {
                    Label("\(display.name) — \(display.resolution)", systemImage: display.id == sources.selectedDisplayID ? "checkmark" : "display")
                }
            }
        case .window:
            if sources.windows.isEmpty {
                Text("No windows")
            }
            ForEach(sources.windows) { window in
                Button {
                    sources.selectedWindowID = window.id
                } label: {
                    if let icon = window.icon {
                        Label { Text(window.label) } icon: { Image(nsImage: icon) }
                    } else {
                        Text(window.label)
                    }
                }
            }
            Divider()
            Button("Refresh Windows") {
                Task { await sources.load() }
            }
        }
    }

    private var currentIcon: SourceLabel.Icon {
        switch sources.kind {
        case .display: .symbol("display")
        case .window: sources.selectedWindow?.icon.map { .image($0) } ?? .symbol("macwindow")
        }
    }

    private var currentTitle: String {
        switch sources.kind {
        case .display: sources.selectedDisplay?.name ?? "No display"
        case .window: sources.selectedWindow?.label ?? "Choose a window"
        }
    }
}

/// The source pill: an icon, a name that's cut short if it's long, and up/down arrows.
private struct SourceLabel: View {
    enum Icon {
        case symbol(String)
        case image(NSImage)
    }

    let icon: Icon
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch icon {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.body)
                        .foregroundStyle(.secondary)
                case .image(let image):
                    Image(nsImage: image)
                        .resizable()
                }
            }
            .frame(width: 22, height: 22)

            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 220, alignment: .leading)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.scopePill))
        .overlay(Capsule().strokeBorder(Color.scopeStroke))
        .contentShape(Capsule())
    }
}
