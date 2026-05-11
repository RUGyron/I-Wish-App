import Foundation
import os.log

/// Threshold-based мониторинг сетевой доступности Firestore.
///
/// **Дизайн (после Bug #4 от Влада, 2026-05-11):**
/// - НЕ блокируем UI при первом fail (single network glitch — норма).
/// - После N подряд network-fails объявляем "сеть отсутствует" → blocked=true.
/// - После M подряд успешных запросов возвращаем blocked=false (плавный recovery).
/// - При blocked'е раз в 5 секунд триггерим silent health-ping: GET небольшого
///   well-known документа (server timestamp). Если он отвечает → success counter растёт.
/// - Локальное чтение SwiftData продолжает работать — мы блокируем только write-actions
///   (см. DataService.swift + view-level disable через `isWriteBlocked`).
///
/// Какие ошибки считаем network-fail:
/// - URLError (no network / timeout / connection lost).
/// - HTTP 5xx / 408 / 502/503/504.
/// - 4xx НЕ считаем — это legitimate server-side rejection (rate limit, auth, etc).
/// - FirestoreError.rateLimited тоже игнорируем (не сетевой fail).
@MainActor
@Observable
final class NetworkMonitor {
    /// Объявлено: сеть нестабильна. UI должен показать overlay/banner и блокировать writes.
    private(set) var isBlocked: Bool = false

    /// Последний счётчик подряд идущих failures. Для отладки/тестов.
    private(set) var consecutiveFails: Int = 0

    /// Последний счётчик подряд идущих successes. Для отладки/тестов.
    private(set) var consecutiveSuccesses: Int = 0

    /// Сколько подряд network-fails нужно для блокировки UI.
    static let failThreshold = 3

    /// Сколько подряд successes нужно для разблокировки.
    static let successThreshold = 2

    /// Период silent retry-ping'а пока blocked=true.
    static let retryInterval: TimeInterval = 5.0

    private var retryTimer: Timer?
    private weak var firestore: FirestoreService?
    private let log = Logger(subsystem: "RUGyron.IWish", category: "NetworkMonitor")

    /// Кэш пути к последнему успешно прочитанному документу — для дешёвого silentPing.
    /// Один GET / 5 sec вместо runQuery с N reads. Сбрасывается на nil если ping fail'нул на нём.
    private var lightPingPath: String?

    init() {}

    // NB: NetworkMonitor сейчас singleton (живёт в AppServices.shared), deinit не вызывается.
    // Если в будущем станет non-singleton — добавить isolated deinit с invalidate timer'а.

    /// Externally setter: вызвать после успешного GET известного документа чтобы silentPing
    /// мог использовать его как health-check без runQuery.
    func cacheLightPingPath(_ path: String) {
        lightPingPath = path
    }

    /// Подключаем после полной инициализации AppServices (избегаем циклической зависимости).
    func attach(firestore: FirestoreService) {
        self.firestore = firestore
    }

    /// Записать успешный сетевой запрос. Threshold-based exit из blocked-state.
    func recordSuccess() {
        consecutiveFails = 0
        consecutiveSuccesses += 1
        if isBlocked && consecutiveSuccesses >= Self.successThreshold {
            isBlocked = false
            stopRetryTimer()
            log.info("NetworkMonitor: UNBLOCKED after \(self.consecutiveSuccesses, privacy: .public) successes")
        }
    }

    /// Записать ошибку. Если это network-flavored (URLError, 5xx) — increment fail counter.
    /// Не-сетевые ошибки (4xx, decryption, rate-limit) ИГНОРИРУЮТСЯ — они не indicator потери сети.
    func recordError(_ error: Error) {
        // 404 на cached lightPingPath означает что документ удалён — invalidate cache,
        // чтобы следующий silentPing fall back на fetchMyMemberships.
        if let fs = error as? FirestoreService.FirestoreError,
           case .requestFailed(let status, _) = fs, status == 404 {
            lightPingPath = nil
        }

        guard Self.isNetworkError(error) else {
            // Не сетевая ошибка — никак не влияет на network state.
            // Но НЕ сбрасываем consecutiveSuccesses — она не получила подтверждения сети.
            return
        }
        consecutiveSuccesses = 0
        consecutiveFails += 1
        if !isBlocked && consecutiveFails >= Self.failThreshold {
            isBlocked = true
            startRetryTimer()
            log.warning("NetworkMonitor: BLOCKED after \(self.consecutiveFails, privacy: .public) network-fails")
        }
    }

    /// HTTP-уровень: 5xx / 408 = network instability; 4xx = client error (не сетевой).
    static func isNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            // Любая URLError — networking failure.
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .internationalRoamingOff, .callIsActive, .dataNotAllowed:
                return true
            default:
                // Прочие URLError (.cancelled, .badURL и пр.) тоже считаем как сеть,
                // но cancelled — игнорируем (юзер отменил task).
                return urlError.code != .cancelled
            }
        }
        // FirestoreError.requestFailed теперь несёт numeric statusCode — используем его.
        // statusCode == 0 = non-HTTP (мы не дошли до сервера); 5xx / 408 = серверный fail.
        if let fsError = error as? FirestoreService.FirestoreError {
            if case .requestFailed(let statusCode, _) = fsError {
                if statusCode == 0 {
                    // Non-HTTP error, но не URLError (странно — обычно URLError ловится выше).
                    // На всякий случай: считаем как сетевой fail чтобы не пропустить degraded state.
                    return true
                }
                // 5xx — серверная нестабильность. 408 = request timeout от сервера.
                if statusCode >= 500 || statusCode == 408 {
                    return true
                }
            }
            // Прочие FirestoreError (notFound, decryptionFailed, rateLimited, ownerMismatch) — НЕ сетевые.
            return false
        }
        return false
    }

    // MARK: - Retry timer

    private func startRetryTimer() {
        stopRetryTimer()
        let timer = Timer(timeInterval: Self.retryInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.silentPing()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    /// Тихий health-check во время blocked-state.
    /// Стратегия (от дешёвого к дорогому):
    ///   1. Если есть cached `lightPingPath` (последний успешный GET) — GET его (1 read).
    ///   2. Иначе — fetchMyMemberships (runQuery с N reads).
    /// Outcome автоматически записывается через request() wrapping.
    private func silentPing() async {
        guard let firestore else { return }
        if let path = lightPingPath {
            _ = try? await firestore.publicLightPing(path: path)
            return
        }
        guard let myUID = AppServices.shared.auth.uid, !myUID.isEmpty else { return }
        _ = try? await firestore.fetchMyMemberships(userUID: myUID)
    }
}
