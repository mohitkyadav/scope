//
//  EditorInspector.swift
//  Scope
//

import SwiftUI

/// The tabs of the editor's settings panel.
enum InspectorTab: String, CaseIterable, Identifiable {
    case style = "Style"
    case zoom = "Zoom"
    case cursor = "Cursor"

    var id: Self { self }
}

/// The settings panel on the right of the editor, one tab at a time. A selected note's text shows
/// above whichever tab is open.
struct EditorInspector: View {
    let tab: InspectorTab
    @Binding var settings: EditorSettings
    let zoomCount: Int
    let hasWebcam: Bool
    /// Replaces the timeline's zooms with ones placed around the clicks.
    var suggestZooms: () -> Void = {}
    /// The selected zoom, and how to change it: the new zoom, whether a slider is still being
    /// dragged, and the name of the change for undo.
    var selectedZoom: ZoomSegment?
    var onZoomChange: (ZoomSegment, Bool, String) -> Void = { _, _, _ in }
    var onZoomSliderReleased: (String) -> Void = { _ in }
    /// Which background library image the project uses, if it uses one.
    var backgroundImageID: String?
    var chooseBackgroundImage: () -> Void = {}
    var useBackgroundImage: (BackgroundLibrary.Item) -> Void = { _ in }
    /// The selected note's text, if a note is selected.
    var noteText: Binding<String>?
    var onNoteEditingChanged: (Bool) -> Void = { _ in }

    @FocusState private var isEditingNote: Bool

    var body: some View {
        Form {
            if let noteText {
                Section {
                    TextField("Text", text: noteText, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($isEditingNote)
                } header: {
                    Text("Note")
                } footer: {
                    Text("Drag the note in the preview to move it.")
                        .foregroundStyle(.secondary)
                }
            }

            switch tab {
            case .style:
                backgroundSection
                cameraSection
            case .zoom:
                if let zoom = selectedZoom {
                    selectedZoomSection(zoom)
                }
                zoomDefaultsSection
            case .cursor:
                cursorSection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: isEditingNote) {
            onNoteEditingChanged(isEditingNote)
        }
    }

    private var backgroundSection: some View {
        Section("Background") {
            SwatchGroup("Gradients") {
                ForEach(Background.gradients) { background in
                    Swatch(name: background.name, isSelected: settings.background == background) {
                        settings.background = background
                    } content: {
                        if let (topLeft, bottomRight) = background.colors {
                            LinearGradient(colors: [Color(topLeft), Color(bottomRight)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        } else {
                            Color.scopePill
                                .overlay(Image(systemName: "nosign").font(.title3).foregroundStyle(.secondary))
                        }
                    }
                }
            }

            SwatchGroup("Images") {
                Swatch(name: "Add Image…", isSelected: false, action: chooseBackgroundImage) {
                    Color.scopePill
                        .overlay(Image(systemName: "plus").font(.title3).foregroundStyle(.secondary))
                }
                ForEach(BackgroundLibrary.shared.items) { item in
                    Swatch(name: "Image", isSelected: settings.background == .image && item.id == backgroundImageID) {
                        useBackgroundImage(item)
                    } content: {
                        Image(nsImage: item.thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .contextMenu {
                        Button("Remove from Library") {
                            BackgroundLibrary.shared.remove(item)
                        }
                    }
                }
            }

            if settings.background == .image {
                LabeledSlider("Blur", value: $settings.backgroundBlur, in: 0...1) {
                    $0 == 0 ? "Off" : "\(Int(($0 * 100).rounded()))%"
                }
            }

            Group {
                LabeledSlider("Padding", value: $settings.padding, in: 0...0.2) {
                    "\(Int(($0 * 100).rounded()))%"
                }
                LabeledSlider("Corners", value: $settings.cornerRadius, in: 0...40) {
                    "\(Int($0.rounded()))"
                }
                Toggle("Shadow", isOn: $settings.shadow)
                LabeledSlider("Parallax", value: $settings.parallax, in: 0...1) {
                    "\(Int(($0 * 100).rounded()))%"
                }
                .help("How much the background zooms along with the recording")
            }
            .disabled(settings.background == .none)
        }
    }

    /// The webcam bubble, called the camera overlay here.
    @ViewBuilder
    private var cameraSection: some View {
        Section {
            if hasWebcam {
                Toggle("Overlay", isOn: $settings.webcamVisible)
                if settings.webcamVisible {
                    LabeledSlider("Size", value: $settings.webcamSize, in: 0.1...0.45) {
                        "\(Int(($0 * 100).rounded()))%"
                    }
                    Picker("Shape", selection: $settings.webcamShape) {
                        ForEach(BubbleShape.allCases) { shape in
                            Text(shape.name).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Shadow", isOn: $settings.webcamShadow)
                    Toggle("Mirror", isOn: $settings.webcamMirrored)
                }
            } else {
                LabeledContent("Overlay", value: "No camera")
            }
        } header: {
            Text("Camera")
        } footer: {
            if hasWebcam, settings.webcamVisible {
                Text("Drag the camera in the preview to move it.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var zoomDefaultsSection: some View {
        Section {
            Toggle("Auto zoom", isOn: $settings.autoZoom)

            Group {
                LabeledSlider("Level", value: $settings.zoomLevel, in: 1.1...3) {
                    String(format: "%.2g×", $0)
                }
                LevelPresets { settings.zoomLevel = $0 }
                LabeledSlider("Transition", value: $settings.zoomTransition, in: 0.3...5) {
                    String(format: "%.1f s", $0)
                }
                LabeledContent("Zooms") {
                    Button("Suggest from Clicks", action: suggestZooms)
                }
            }
            .disabled(!settings.autoZoom)
        } header: {
            Text(selectedZoom == nil ? "Zoom" : "Defaults")
        } footer: {
            Text("Defaults for \(zoomCount == 1 ? "the 1 zoom" : "the \(zoomCount) zooms") on the timeline. Select a zoom to give it its own settings.")
                .foregroundStyle(.secondary)
        }
    }

    private var cursorSection: some View {
        Section("Cursor") {
            LabeledSlider("Smoothing", value: $settings.cursorSmoothing, in: 0...1) {
                $0 == 0 ? "Off" : "\(Int($0 * 100))%"
            }
            LabeledSlider("Size", value: $settings.cursorSize, in: 0.5...3) {
                String(format: "%.1f×", $0)
            }
            Toggle("Show clicks", isOn: $settings.showClicks)
        }
    }
}

extension EditorInspector {
    /// Settings for the zoom selected on the timeline, starting from the defaults until changed.
    @ViewBuilder
    fileprivate func selectedZoomSection(_ zoom: ZoomSegment) -> some View {
        Section {
            LabeledSlider(
                "Level",
                value: Binding(
                    get: { zoom.level ?? settings.zoomLevel },
                    set: { level in
                        var changed = zoom
                        changed.level = level
                        onZoomChange(changed, true, "Change Zoom Level")
                    }
                ),
                in: 1.1...3,
                format: { String(format: "%.2g×", $0) },
                onEditingChanged: { if !$0 { onZoomSliderReleased("Change Zoom Level") } }
            )
            LevelPresets { level in
                var changed = zoom
                changed.level = level
                onZoomChange(changed, false, "Change Zoom Level")
            }
            LabeledSlider(
                "Transition",
                value: Binding(
                    get: { zoom.transition ?? settings.zoomTransition },
                    set: { transition in
                        var changed = zoom
                        changed.transition = transition
                        onZoomChange(changed, true, "Change Zoom Transition")
                    }
                ),
                in: 0.3...5,
                format: { String(format: "%.1f s", $0) },
                onEditingChanged: { if !$0 { onZoomSliderReleased("Change Zoom Transition") } }
            )
            Toggle("Follow cursor", isOn: Binding(
                get: { zoom.followsCursor ?? true },
                set: { follows in
                    var changed = zoom
                    changed.followsCursor = follows
                    onZoomChange(changed, false, follows ? "Follow Cursor" : "Stop Following Cursor")
                }
            ))
            LabeledContent("Settings") {
                Button("Use Defaults") {
                    var changed = zoom
                    changed.level = nil
                    changed.transition = nil
                    changed.followsCursor = nil
                    onZoomChange(changed, false, "Use Default Zoom Settings")
                }
                .disabled(!zoom.hasOwnSettings)
            }
        } header: {
            Text("Selected Zoom")
        } footer: {
            Text(zoom.hasOwnSettings ? "This zoom has its own settings." : "Uses the zoom defaults below until you change something.")
                .foregroundStyle(.secondary)
        }
    }
}

/// Quick picks for the zoom level: a gentle zoom, the usual one, and a close-up.
private struct LevelPresets: View {
    static let levels = [1.25, 1.5, 2.0]
    let choose: (Double) -> Void

    var body: some View {
        LabeledContent("Presets") {
            HStack(spacing: 6) {
                ForEach(Self.levels, id: \.self) { level in
                    Button(String(format: "%g×", level)) { choose(level) }
                        .controlSize(.small)
                }
            }
        }
    }
}

/// A titled grid of background swatches.
private struct SwatchGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: Background.gradients.count), spacing: 8) {
                content
            }
        }
        .padding(.vertical, 4)
    }
}

/// A rounded square showing a background, outlined in the accent colour when it's in use.
private struct Swatch<Content: View>: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { content }
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.scopeStroke)
                }
                .padding(3)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension Color {
    init(_ rgb: RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// A slider with its current value shown on the right.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    var onEditingChanged: (Bool) -> Void = { _ in }

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: @escaping (Double) -> String, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.title = title
        _value = value
        self.range = range
        self.format = format
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        LabeledContent {
            HStack {
                Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)
                    .fixedSize()
            }
        } label: {
            Text(title)
        }
    }
}

#Preview {
    EditorInspector(tab: .style, settings: .constant(EditorSettings()), zoomCount: 3, hasWebcam: true)
        .frame(width: 300)
}
