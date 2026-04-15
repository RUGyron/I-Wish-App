import SwiftUI

struct SyncStatusBadge: View {
    let state: SyncStatusService.State

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
                .foregroundStyle(iconColor)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var iconName: String {
        switch state {
        case .idle: return "icloud"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.icloud"
        case .offline: return "icloud.slash"
        case .error: return "exclamationmark.icloud"
        }
    }

    private var iconColor: Color {
        switch state {
        case .idle: return .secondary
        case .syncing: return .accentColor
        case .synced: return .green
        case .offline, .error: return .orange
        }
    }

    private var label: String {
        switch state {
        case .idle: return "iCloud"
        case .syncing: return "Синхронизация..."
        case .synced(let date):
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            return fmt.localizedString(for: date, relativeTo: .now)
        case .offline: return "Нет сети"
        case .error: return "Ошибка синхронизации"
        }
    }
}
