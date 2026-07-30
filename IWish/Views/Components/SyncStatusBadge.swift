import SwiftUI
import Combine

struct SyncStatusBadge: View {
    let isSyncing: Bool
    let syncError: String?
    /// Сколько изменений в outbox ждёт push в Firestore (offline mode).
    var pendingCount: Int = 0
    /// Offline / network blocked.
    var isOffline: Bool = false
    /// Момент старта текущего sync. Spinner показывается макс 3 сек после старта,
    /// дальше — статичная иконка + pendingCount. Это спасает от ощущения "бесконечной
    /// синхры" на медленной сети (3G/Edge), где запрос может идти 5-10 сек.
    var syncStartedAt: Date? = nil
    var onTap: (() -> Void)? = nil

    /// Каждые 0.5 сек tick'аем чтобы пересчитать `showSpinner` (без него taймер sync прохода
    /// после 3 сек был бы виден только при следующем view-refresh).
    @State private var tickerNow = Date()

    private static let maxSpinnerSeconds: TimeInterval = 3.0

    private var showSpinner: Bool {
        guard isSyncing && !isOffline else { return false }
        // Без явного syncStartedAt spinner не показываем вообще — это значит источник sync
        // не наш outbox (например background polling refreshWishlists), его не надо crawl'ить
        // у юзера на глазах. Только реальная отправка локальных изменений = spinner.
        guard let started = syncStartedAt else { return false }
        return tickerNow.timeIntervalSince(started) < Self.maxSpinnerSeconds
    }

    var body: some View {
        HStack(spacing: 4) {
            if showSpinner {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor)
                    .frame(width: 16, height: 16)
            }
            if pendingCount > 0 {
                Text("\(pendingCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOffline ? Color.orange : Color.secondary)
            }
        }
        .onTapGesture { onTap?() }
        .animation(.easeInOut(duration: 0.2), value: isSyncing)
        .animation(.easeInOut(duration: 0.2), value: pendingCount)
        .animation(.easeInOut(duration: 0.2), value: isOffline)
        .animation(.easeInOut(duration: 0.2), value: syncError == nil)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { now in
            // Tick только когда есть смысл (sync активен) — иначе тратим CPU зря.
            if isSyncing { tickerNow = now }
        }
    }

    private var iconName: String {
        // Offline имеет приоритет: при отсутствии сети syncError — естественное следствие,
        // юзеру важнее видеть причину ("нет сети"), а не симптом ("ошибка sync").
        if isOffline { return "wifi.slash" }
        if syncError != nil { return "exclamationmark.icloud" }
        return "checkmark.icloud"
    }

    private var iconColor: Color {
        if isOffline { return .orange }
        if syncError != nil { return .orange }
        return .secondary
    }
}
