import SwiftUI

struct SyncStatusBadge: View {
    let isSyncing: Bool
    let syncError: String?
    var onTap: (() -> Void)? = nil

    @State private var rotationDegrees: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if isSyncing {
                    // Only arrows rotate, not cloud
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .rotationEffect(.degrees(rotationDegrees))
                } else if syncError != nil {
                    Image(systemName: "exclamationmark.icloud")
                } else {
                    Image(systemName: "checkmark.icloud")
                }
            }
            .font(.caption2)
            .foregroundStyle(iconColor)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.easeInOut(duration: 0.25), value: isSyncing)
        .animation(.easeInOut(duration: 0.25), value: syncError == nil)
        .contentTransition(.interpolate)
        .onTapGesture {
            onTap?()
        }
        .onChange(of: isSyncing) { _, syncing in
            if syncing {
                startSpinning()
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    rotationDegrees = 0
                }
            }
        }
    }

    private func startSpinning() {
        rotationDegrees = 0
        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
            rotationDegrees = 360
        }
    }

    private var iconColor: Color {
        if isSyncing { return .secondary }
        if syncError != nil { return .orange }
        return .secondary
    }

    private var label: String {
        if isSyncing { return "Синхронизация..." }
        if syncError != nil { return "Ошибка" }
        return "Синхронизировано"
    }
}
