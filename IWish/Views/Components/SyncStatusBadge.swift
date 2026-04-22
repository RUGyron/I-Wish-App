import SwiftUI

struct SyncStatusBadge: View {
    let isSyncing: Bool
    let syncError: String?
    let lastSyncDate: Date?
    var onTap: (() -> Void)? = nil

    @State private var rotationDegrees: Double = 0
    @State private var showCheckmark = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
                .foregroundStyle(iconColor)
                .rotationEffect(.degrees(rotationDegrees))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .onTapGesture {
            if let onTap {
                withAnimation(.linear(duration: 0.6)) {
                    rotationDegrees += 360
                }
                onTap()
            }
        }
        .onChange(of: isSyncing) { _, syncing in
            if syncing {
                withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
                    rotationDegrees += 360
                }
            } else {
                withAnimation(.default) {
                    rotationDegrees = 0
                }
                // Show checkmark briefly after sync completes
                if syncError == nil {
                    showCheckmark = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { showCheckmark = false }
                    }
                }
            }
        }
    }

    private var iconName: String {
        if isSyncing { return "arrow.triangle.2.circlepath" }
        if syncError != nil { return "exclamationmark.icloud" }
        if showCheckmark { return "checkmark.icloud" }
        return "icloud"
    }

    private var iconColor: Color {
        if isSyncing { return .accentColor }
        if syncError != nil { return .orange }
        if showCheckmark { return .green }
        return .secondary
    }

    private var label: String {
        if isSyncing { return "Синхронизация..." }
        if syncError != nil { return "Ошибка синхры" }
        if showCheckmark { return "Только что" }
        if let date = lastSyncDate {
            if Date.now.timeIntervalSince(date) < 10 { return "Только что" }
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            return fmt.localizedString(for: date, relativeTo: .now)
        }
        return "iCloud"
    }
}
