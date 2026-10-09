//
//  ContentView.swift
//  Scope
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("Recordings")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 20)

            ContentUnavailableView(
                "No Recordings",
                systemImage: "film.stack",
                description: Text("Recordings you make will appear here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            RecordButton {
                // Recording starts in step 1.2.
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

#Preview {
    ContentView()
}
