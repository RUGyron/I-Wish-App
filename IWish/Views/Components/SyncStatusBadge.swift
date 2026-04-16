import SwiftUI

struct SyncStatusBadge: View {
    let state: SyncStatusService.State
    var onTap: (() -> Void)? = nil

    @State private var rotationDegrees: Double = 0

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
        .onChange(of: state) { _, newValue in
            if case .syncing = newValue {
                withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
                    rotationDegrees += 360
                }
            } else {
                withAnimation(.default) {
                    rotationDegrees = 0
                }
            }
        }
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
            if Date.now.timeIntervalSince(date) < 10 {
                return "Только что"
            }
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            return fmt.localizedString(for: date, relativeTo: .now)
        case .offline: return "Нет сети"
        case .error: return "Ошибка синхронизации"
        }
    }
}
