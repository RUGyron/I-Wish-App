import SwiftUI

struct SyncStatusBadge: View {
    let isSyncing: Bool
    let syncError: String?
    var onTap: (() -> Void)? = nil

    var body: some View {
        Group {
            if isSyncing {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor)
            }
        }
        .onTapGesture { onTap?() }
        .animation(.easeInOut(duration: 0.2), value: isSyncing)
        .animation(.easeInOut(duration: 0.2), value: syncError == nil)
    }

    private var iconName: String {
        if syncError != nil { return "exclamationmark.icloud" }
        return "checkmark.icloud"
    }

    private var iconColor: Color {
        if syncError != nil { return .orange }
        return .secondary
    }
}
