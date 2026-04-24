import SwiftUI

struct SyncStatusBadge: View {
    let isSyncing: Bool
    let syncError: String?
    var onTap: (() -> Void)? = nil

    @State private var rotationDegrees: Double = 0

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 12))
            .foregroundStyle(iconColor)
            .rotationEffect(isSyncing ? .degrees(rotationDegrees) : .zero)
            .animation(.easeInOut(duration: 0.25), value: isSyncing)
            .animation(.easeInOut(duration: 0.25), value: syncError == nil)
            .onTapGesture { onTap?() }
            .onChange(of: isSyncing) { _, syncing in
                if syncing {
                    rotationDegrees = 0
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        rotationDegrees = 360
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        rotationDegrees = 0
                    }
                }
            }
    }

    private var iconName: String {
        if isSyncing { return "arrow.triangle.2.circlepath" }
        if syncError != nil { return "exclamationmark.icloud" }
        return "checkmark.icloud"
    }

    private var iconColor: Color {
        if syncError != nil { return .orange }
        return .secondary
    }
}
