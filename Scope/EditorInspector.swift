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
    case camera = "Camera"

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
    /// Called when the border's hex field gains or loses focus, so typing in it doesn't trigger shortcuts.
    var onHexEditingChanged: (Bool) -> Void = { _ in }

    @FocusState private var isEditingNote: Bool
    @FocusState private var isEditingHex: Bool
    /// The hex field's text while it's typed in.
    @State private var hexText = ""

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
            case .zoom:
                if let zoom = selectedZoom {
                    selectedZoomSection(zoom)
                }
                zoomDefaultsSection
                motionSection
            case .cursor:
                cursorSection
            case .camera:
                cameraSection
                if hasWebcam, settings.webcamVisible {
                    framingSection
                    borderSection
                }
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
                        if let colors = background.colors {
                            LinearGradient(colors: colors.map { Color($0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
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

            // Without a background the recording fills the frame, so these would do nothing.
            if settings.background != .none {
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
        }
    }

    /// The webcam bubble, called the camera overlay here.
    @ViewBuilder
    private var cameraSection: some View {
        Section {
            if hasWebcam {
                Toggle("Overlay", isOn: $settings.webcamVisible)
                if settings.webcamVisible {
                    Picker("Shape", selection: $settings.webcamShape) {
                        ForEach(BubbleShape.allCases) { shape in
                            Label(shape.name, systemImage: shape.symbol)
                                .labelStyle(.iconOnly)
                                .help(shape.name)
                                .tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    LabeledSlider("Size", value: $settings.webcamSize, in: 0.1...0.45) {
                        "\(Int(($0 * 100).rounded()))%"
                    }
                    LabeledContent("Position") {
                        CornerPicker(x: $settings.webcamX, y: $settings.webcamY)
                    }
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
                Text("Drag the camera in the preview to move it anywhere.")
                    .foregroundStyle(.secondary)
            } else if !hasWebcam {
                Text("Turn on the camera before recording to add yourself to the video.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Which part of the camera shows in the bubble.
    private var framingSection: some View {
        Section {
            LabeledSlider("Zoom", value: $settings.webcamZoom, in: 1...3) {
                String(format: "%.2g×", $0)
            }
            LabeledSlider("Horizontal", value: $settings.webcamFocusX, in: -1...1) {
                Self.offset($0, back: "←", forward: "→")
            }
            LabeledSlider("Vertical", value: $settings.webcamFocusY, in: -1...1) {
                Self.offset($0, back: "↑", forward: "↓")
            }
            LabeledContent("") {
                Button("Reset") {
                    settings.webcamZoom = 1
                    settings.webcamFocusX = 0
                    settings.webcamFocusY = 0
                }
                .disabled(settings.webcamZoom == 1 && settings.webcamFocusX == 0 && settings.webcamFocusY == 0)
            }
        } header: {
            Text("Framing")
        } footer: {
            Text("Zoom in so your face fills the bubble, then move to the part of the camera to show.")
                .foregroundStyle(.secondary)
        }
    }

    /// The border's colour for the colour picker. Picking one makes the border custom.
    private var customBorderColor: Binding<Color> {
        Binding(
            get: { Color(settings.webcamBorderRGB ?? settings.webcamBorderColor) },
            set: { color in
                guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                settings.webcamBorderColor = RGB(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
                settings.webcamBorder = .custom
            }
        )
    }

    /// Uses the typed hex colour, or puts back the current one if it isn't a colour.
    private func applyHex() {
        guard let color = RGB(hex: hexText) else {
            hexText = settings.webcamBorderRGB?.hex ?? ""
            return
        }
        hexText = color.hex
        guard color != settings.webcamBorderRGB else { return }
        settings.webcamBorderColor = color
        settings.webcamBorder = .custom
    }

    /// "Centre", "← 40%" or "40% →".
    private static func offset(_ value: Double, back: String, forward: String) -> String {
        let percent = Int((abs(value) * 100).rounded())
        if percent == 0 { return "Centre" }
        return value < 0 ? "\(back) \(percent)%" : "\(percent)% \(forward)"
    }

    private var borderSection: some View {
        Section("Border") {
            LabeledContent("Colour") {
                HStack(spacing: 8) {
                    ForEach(BubbleBorder.presets) { border in
                        BorderSwatch(border: border, isSelected: settings.webcamBorder == border) {
                            settings.webcamBorder = border
                        }
                    }
                    ColorPicker("Custom", selection: customBorderColor, supportsOpacity: false)
                        .labelsHidden()
                        .help("Pick any colour")
                }
            }
            if let color = settings.webcamBorderRGB {
                LabeledContent("Hex") {
                    TextField("Hex", text: $hexText, prompt: Text("#RRGGBB"))
                        .labelsHidden()
                        .monospaced()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .focused($isEditingHex)
                        .onSubmit(applyHex)
                }
                .onChange(of: color, initial: true) {
                    if !isEditingHex {
                        hexText = color.hex
                    }
                }
                .onChange(of: isEditingHex) {
                    onHexEditingChanged(isEditingHex)
                    if !isEditingHex {
                        applyHex()
                    }
                }
            }
            if settings.webcamBorder != .none {
                LabeledSlider("Thickness", value: $settings.webcamBorderWidth, in: 0.005...0.06) {
                    "\(Int(($0 * 100).rounded(.up)))%"
                }
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

    private var motionSection: some View {
        Section {
            Toggle("Motion blur", isOn: $settings.motionBlur)
        } header: {
            Text("Motion")
        } footer: {
            Text("Blurs zooms, pans and the cursor while they move, like a real camera.")
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
            Toggle("Match cursor shape", isOn: $settings.cursorShapes)
                .help("Show the hand over links, the text cursor over text and so on, as while recording")
            Toggle("Glide across cuts", isOn: $settings.cursorGlide)
                .help("Where part of the recording is cut out, move the cursor smoothly instead of letting it jump")
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

/// Four buttons that put the camera in a corner. The one in use is highlighted.
private struct CornerPicker: View {
    @Binding var x: Double
    @Binding var y: Double

    private struct Corner: Identifiable {
        let name: String
        let x: Double
        let y: Double
        let alignment: Alignment
        var id: String { name }
    }

    private let corners = [
        Corner(name: "Top left", x: 0, y: 0, alignment: .topLeading),
        Corner(name: "Top right", x: 1, y: 0, alignment: .topTrailing),
        Corner(name: "Bottom left", x: 0, y: 1, alignment: .bottomLeading),
        Corner(name: "Bottom right", x: 1, y: 1, alignment: .bottomTrailing),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(corners) { corner in
                let isSelected = x == corner.x && y == corner.y
                Button {
                    x = corner.x
                    y = corner.y
                } label: {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(isSelected ? Color.accentColor : .secondary, lineWidth: 1.5)
                        .overlay(alignment: corner.alignment) {
                            Circle()
                                .fill(isSelected ? Color.accentColor : .secondary)
                                .frame(width: 6, height: 6)
                                .padding(3)
                        }
                        .frame(width: 26, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(corner.name)
                .accessibilityLabel(corner.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// A round swatch for a border colour, crossed out for no border.
private struct BorderSwatch: View {
    let border: BubbleBorder
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let color = border.color {
                    Circle().fill(Color(color))
                } else {
                    Circle()
                        .fill(.background)
                        .overlay {
                            Rectangle()
                                .fill(.secondary)
                                .frame(width: 1.5)
                                .rotationEffect(.degrees(45))
                        }
                        .clipShape(Circle())
                }
            }
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
            .frame(width: 18, height: 18)
            .padding(3)
            .overlay {
                if isSelected {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(border.name)
        .accessibilityLabel(border.name)
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
