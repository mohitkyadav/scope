//
//  LevelMeter.swift
//  Scope
//

import SwiftUI

/// A small horizontal bar showing an audio level from 0 to 1.
struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * CGFloat(level))
            }
        }
        .frame(width: 60, height: 6)
        .animation(.linear(duration: 0.05), value: level)
        .accessibilityElement()
        .accessibilityLabel("Level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private var color: Color {
        switch level {
        case 0.9...: .red
        case 0.7...: .yellow
        default: .green
        }
    }
}

#Preview {
    VStack {
        LevelMeter(level: 0.3)
        LevelMeter(level: 0.8)
        LevelMeter(level: 0.95)
    }
    .padding()
}
