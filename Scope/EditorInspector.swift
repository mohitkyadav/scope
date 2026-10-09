//
//  EditorInspector.swift
//  Scope
//

import SwiftUI

/// The settings panel on the right of the editor.
struct EditorInspector: View {
    @Binding var settings: EditorSettings

    var body: some View {
        Form {
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
        .formStyle(.grouped)
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
    EditorInspector(settings: .constant(EditorSettings()))
        .frame(width: 300)
}
