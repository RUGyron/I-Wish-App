import Foundation
import FirebaseRemoteConfig
import os.log

private let rcLog = Logger(subsystem: "RUGyron.IWish", category: "RemoteConfig")

/// Firebase Remote Config gate для force-update.
/// Параметры в Firebase Console:
///   - `min_supported_build` (Number, default 0): минимальный CFBundleVersion. Если current < min — блокируем.
///   - `force_update_message` (String, default ""): кастомное сообщение для ForceUpdateBlockingView.
@Observable
@MainActor
final class RemoteConfigService {
    var isLoading = true
    var minSupportedBuild: Int = 0
    var forceUpdateMessage: String?
    var fetchFailed = false

    private let rc = RemoteConfig.remoteConfig()
    private var pollTimer: Timer?

    init() {
        let settings = RemoteConfigSettings()
        // Force-update требует свежий config — поэтому minimumFetchInterval=0 везде.
        // Apple рекомендует >=3600 для обычных RC параметров, но для kill-switch это legitimate.
        settings.minimumFetchInterval = 0
        rc.configSettings = settings
        rc.setDefaults([
            "min_supported_build": 0 as NSNumber,
            "force_update_message": "" as NSString
        ])
    }

    /// Первый fetch при старте app — с loading spinner.
    /// После первого успешного fetch запускает 15-секундный polling для динамического kill-switch.
    func fetch() async {
        isLoading = true
        defer { isLoading = false }

        await performFetch()
        startPolling()
    }

    private func performFetch() async {
        do {
            // Timeout 3 секунды — иначе при отсутствии сети юзер залипнет на splash.
            // Force-update gate важнее для нормально работающей сети; offline-юзер всё равно
            // не сможет обновиться, так что задерживать его на splash смысла нет.
            try await withTimeout(seconds: 3) { [rc] in
                let _ = try await rc.fetchAndActivate()
            }

            minSupportedBuild = rc.configValue(forKey: "min_supported_build").numberValue.intValue
            let msg = rc.configValue(forKey: "force_update_message").stringValue
            forceUpdateMessage = msg.isEmpty ? nil : msg
            fetchFailed = false
            rcLog.info("RC fetched: minBuild=\(self.minSupportedBuild), msg=\(self.forceUpdateMessage ?? "nil", privacy: .public)")
        } catch {
            fetchFailed = true
            rcLog.warning("RC fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Adaptive polling:
    /// - Когда force-update **требуется** (UI заблокирован) — раз в 15с, чтобы быстро отпустить
    ///   после публикации новой версии или отката kill-switch.
    /// - Когда **не требуется** (нормальная работа) — раз в 120с, чтобы не жечь батарею
    ///   и не спамить Firebase. 2 минуты задержки на kill-switch acceptable.
    /// Перепланирует таймер при каждом fetch (см. `performFetch` ниже).
    private func startPolling() {
        scheduleNextPoll()
    }

    private func scheduleNextPoll() {
        pollTimer?.invalidate()
        let interval: TimeInterval = requiresForceUpdate ? 15.0 : 120.0
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.performFetch()
                self?.scheduleNextPoll()
            }
        }
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    var requiresForceUpdate: Bool {
        guard !fetchFailed else { return false }  // нет сети — пускаем (не блокируем offline)
        return currentBuild < minSupportedBuild
    }
}

// MARK: - Timeout helper

@MainActor
private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw RemoteConfigTimeout.timedOut
        }
        guard let first = try await group.next() else {
            throw RemoteConfigTimeout.timedOut
        }
        group.cancelAll()
        return first
    }
}

private enum RemoteConfigTimeout: Error {
    case timedOut
}
