//
//  DisplayPicker.swift
//  Scope
//

import SwiftUI

struct DisplayPicker: View {
    @Bindable var displayList: DisplayList

    var body: some View {
        if let errorMessage = displayList.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } else {
            Picker("Display", selection: $displayList.selectedID) {
                ForEach(displayList.displays) { display in
                    Text("\(display.name) — \(display.resolution)")
                        .tag(Optional(display.id))
                }
            }
            .fixedSize()
        }
    }
}
