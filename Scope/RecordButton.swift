//
//  RecordButton.swift
//  Scope
//

import SwiftUI

struct RecordButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Record", systemImage: "record.circle.fill")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: 240)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.red)
    }
}

#Preview {
    RecordButton {}
        .padding()
}
