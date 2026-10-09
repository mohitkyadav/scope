//
//  EditorInspector.swift
//  Scope
//

import SwiftUI

/// The settings panel on the right of the editor.
struct EditorInspector: View {
    @Binding var settings: EditorSettings
    let zoomCount: Int

    var body: some View {
        Form {
            Section {
                Toggle("Auto zoom", isOn: $settings.autoZoom)

                Group {
                    LabeledSlider("Level", value: $settings.zoomLevel, in: 1.25...3) {
                        String(format: "%.1f×", $0)
                    }
                    LabeledSlider("Transition", value: $settings.zoomTransition, in: 0.3...5) {
                        String(format: "%.1f s", $0)
                    }
                }
                .disabled(!settings.autoZoom)
            } header: {
                Text("Zoom")
            } footer: {
                Text(zoomCount == 1 ? "1 zoom, placed around your clicks." : "\(zoomCount) zooms, placed around your clicks.")
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

            Section("Background") {
                BackgroundPicker(selection: $settings.background)

                Group {
                    LabeledSlider("Padding", value: $settings.padding, in: 0...0.2) {
                        "\(Int(($0 * 100).rounded()))%"
                    }
                    LabeledSlider("Corners", value: $settings.cornerRadius, in: 0...40) {
                        "\(Int($0.rounded()))"
                    }
                    Toggle("Shadow", isOn: $settings.shadow)
                }
                .disabled(settings.background == .none)
            }
        }
        .formStyle(.grouped)
    }
}

/// A row of swatches, one per background.
private struct BackgroundPicker: View {
    @Binding var selection: Background

    var body: some View {
        // Adaptive columns wrap onto a second row instead of forcing the panel wider than it is.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28, maximum: 28), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(Background.allCases) { background in
                Button {
                    selection = background
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
        if let (topLeft, bottomRight) = background.colors {
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
                    .frame(width: 40, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

#Preview {
    EditorInspector(settings: .constant(EditorSettings()), zoomCount: 3)
        .frame(width: 300)
}
