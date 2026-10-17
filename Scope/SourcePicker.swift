//
//  SourcePicker.swift
//  Scope
//

import SwiftUI

/// What to record: a Display / Window / Area switch, then a pill showing the chosen display or
/// window (with its app's icon) that opens a menu of the others, or the chosen area, which is
/// picked on screen.
struct SourcePicker: View {
    @Bindable var sources: CaptureSources
    @State private var isSelectingArea = false

    var body: some View {
        if let errorMessage = sources.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                PillPicker(options: CaptureSources.Kind.allCases.map { ($0, $0.rawValue) }, selection: $sources.kind)
                    .fixedSize()

                if sources.kind == .area {
                    Button(action: selectArea) {
                        SourceLabel(icon: .symbol("rectangle.dashed"), title: areaTitle, indicator: "scope")
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Choose the area to record")
                } else {
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
            .onChange(of: sources.kind) {
                // There's nothing to record until an area is chosen, so go straight to choosing one.
                if sources.kind == .area, sources.selectedRegion == nil {
                    selectArea()
                }
            }
        }
    }

    private func selectArea() {
        guard !isSelectingArea else { return }
        isSelectingArea = true
        Task {
            if let region = await AreaSelector.select(current: sources.regionDisplay == nil ? nil : sources.selectedRegion) {
                sources.selectedRegion = region
            }
            isSelectingArea = false
        }
    }

    /// "1280 × 720 on Studio Display", in pixels.
    private var areaTitle: String {
        guard let region = sources.selectedRegion, let display = sources.regionDisplay else { return "Choose an area" }
        let scale = NSScreen.screens.first { $0.displayID == region.displayID }?.backingScaleFactor ?? 2
        let size = "\(Int((region.rect.width * scale).rounded())) × \(Int((region.rect.height * scale).rounded()))"
        return NSScreen.screens.count > 1 ? "\(size) on \(display.name)" : size
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
        case .area:
            EmptyView()
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
        case .area: .symbol("rectangle.dashed")
        }
    }

    private var currentTitle: String {
        switch sources.kind {
        case .display: sources.selectedDisplay?.name ?? "No display"
        case .window: sources.selectedWindow?.label ?? "Choose a window"
        case .area: areaTitle
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
    /// The symbol at the end, showing what clicking does.
    var indicator = "chevron.up.chevron.down"

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

            Image(systemName: indicator)
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
