//
//  EditorInspector.swift
//  Scope
//

import SwiftUI

/// The settings panel on the right of the editor.
struct EditorInspector: View {
    @Binding var settings: EditorSettings
    let zoomCount: Int
    let hasWebcam: Bool
    /// Replaces the timeline's zooms with ones placed around the clicks.
    var suggestZooms: () -> Void = {}
    /// A small copy of the image background, if one has been chosen.
    var backgroundThumbnail: NSImage?
    var chooseBackgroundImage: () -> Void = {}
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

            Section {
                Toggle("Auto zoom", isOn: $settings.autoZoom)

                Group {
                    LabeledSlider("Level", value: $settings.zoomLevel, in: 1.25...3) {
                        String(format: "%.1f×", $0)
                    }
                    LabeledSlider("Transition", value: $settings.zoomTransition, in: 0.3...5) {
                        String(format: "%.1f s", $0)
                    }
                    LabeledContent("Zooms") {
                        Button("Suggest from Clicks", action: suggestZooms)
                    }
                }
                .disabled(!settings.autoZoom)
            } header: {
                Text("Zoom")
            } footer: {
                Text(zoomCount == 1 ? "1 zoom on the timeline." : "\(zoomCount) zooms on the timeline.")
                    .foregroundStyle(.secondary)
            }

            Section("Cursor") {
                LabeledSlider("Smoothing", value: $settings.cursorSmoothing, in: 0...1) {
                    $0 == 0 ? "Off" : "\(Int($0 * 100))%"
                }
                LabeledSlider("Size", value: $settings.cursorSize, in: 0.5...3) {
                    String(format: "%.1f×", $0)
                }
                Toggle("Show clicks", isOn: $settings.showClicks)
            }

            if hasWebcam {
                Section {
                    Toggle("Show bubble", isOn: $settings.webcamVisible)

                    Group {
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
                    .disabled(!settings.webcamVisible)
                } header: {
                    Text("Webcam")
                } footer: {
                    Text("Drag the bubble in the preview to move it.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Background") {
                BackgroundPicker(selection: $settings.background, imageThumbnail: backgroundThumbnail, chooseImage: chooseBackgroundImage)

                if settings.background == .image {
                    LabeledContent("Image") {
                        Button(backgroundThumbnail == nil ? "Choose…" : "Change…", action: chooseBackgroundImage)
                    }
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
        .formStyle(.grouped)
        .onChange(of: isEditingNote) {
            onNoteEditingChanged(isEditingNote)
        }
    }
}

/// A row of swatches, one per background. The image swatch shows the chosen image, or asks for one.
private struct BackgroundPicker: View {
    @Binding var selection: Background
    let imageThumbnail: NSImage?
    let chooseImage: () -> Void

    var body: some View {
        // Adaptive columns wrap onto a second row instead of forcing the panel wider than it is.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28, maximum: 28), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(Background.allCases) { background in
                Button {
                    if background == .image, imageThumbnail == nil {
                        chooseImage()
                    } else {
                        selection = background
                    }
                } label: {
                    swatch(for: background)
                        .frame(width: 28, height: 28)
                        .overlay {
                            if background == selection {
                                Circle()
                                    .stroke(Color.accentColor, lineWidth: 2)
                                    .padding(-4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(background.name)
                .accessibilityLabel(background.name)
                .accessibilityAddTraits(background == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func swatch(for background: Background) -> some View {
        if background == .image {
            if let imageThumbnail {
                Image(nsImage: imageThumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.separator))
            } else {
                Circle()
                    .stroke(.separator)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        } else if let (topLeft, bottomRight) = background.colors {
            Circle()
                .fill(LinearGradient(colors: [Color(topLeft), Color(bottomRight)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(.separator))
        } else {
            Circle()
                .stroke(.separator)
                .overlay(Image(systemName: "nosign").foregroundStyle(.secondary))
        }
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

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        LabeledContent {
            HStack {
                Slider(value: $value, in: range)
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
    EditorInspector(settings: .constant(EditorSettings()), zoomCount: 3, hasWebcam: true)
        .frame(width: 300)
}
