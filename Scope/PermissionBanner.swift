//
//  PermissionBanner.swift
//  Scope
//

import SwiftUI

struct PermissionBanner: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Scope can't record your screen yet")
                    .font(.headline)
                Text("Turn on Scope in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen Scope.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open System Settings", action: openSettings)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}

#Preview {
    PermissionBanner {}
        .padding()
        .frame(width: 480)
}
