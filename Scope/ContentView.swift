//
//  ContentView.swift
//  Scope
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "record.circle")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Scope")
                .font(.title)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    ContentView()
}
