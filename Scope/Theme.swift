//
//  Theme.swift
//  Scope
//

import AppKit
import SwiftUI

/// Scope's colours and the small shared pieces of its look. Colours adapt to light and dark mode;
/// the dark values match the designs.
extension Color {
    // Tints of the text colour, so they lighten the background in dark mode and darken it in light mode.
    /// The floating cards, like the recording panel.
    static let scopeCard = Color.primary.opacity(0.05)
    /// Pills and chips inside cards.
    static let scopePill = Color.primary.opacity(0.07)
    /// The selected segment inside a pill.
    static let scopePillSelected = Color.primary.opacity(0.16)
    /// Hairline borders around cards and pills.
    static let scopeStroke = Color.primary.opacity(0.08)
    /// The area around the editor's preview, a little darker than the window.
    static let scopeStage = Color.black.opacity(0.18)

    static let scopeRecord = Color(red: 0.91, green: 0.29, blue: 0.24)
    static let scopeZoom = Color(red: 0.55, green: 0.36, blue: 0.97)
    static let scopeClip = Color(red: 0.17, green: 0.44, blue: 0.84)
    static let scopeSelection = Color(red: 0.97, green: 0.73, blue: 0.18)
    static let scopeNote = Color(red: 0.95, green: 0.55, blue: 0.2)
}

/// A row of options in a pill, with the selected one raised, like the Display / Window switch.
struct PillPicker<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                Button {
                    selection = value
                } label: {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(value == selection ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if value == selection {
                                Capsule().fill(Color.scopePillSelected)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(value == selection ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.scopePill))
    }
}

/// A rounded pill holding a group of buttons, like the editor's toolbar groups.
struct PillGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 2) {
            content
        }
        .buttonStyle(PillItemStyle())
        .padding(3)
        .background(Capsule().fill(Color.scopePill))
        .overlay(Capsule().strokeBorder(Color.scopeStroke))
    }
}

/// A button inside a `PillGroup`: no border, a soft highlight while pressed.
struct PillItemStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.6))
            .background(Capsule().fill(configuration.isPressed ? Color.scopePillSelected : .clear))
            .contentShape(Capsule())
    }
}
