import Foundation
import Network
import UIKit
import os.log

/// Threshold-based мониторинг сетевой доступности Firestore + preemptive lock через NWPathMonitor.
///
/// **Дизайн (после Bug #4 от Влада, 2026-05-11; preemptive lock от 2026-05-16):**
/// - НЕ блокируем UI при первом fail (single network glitch — норма).
/// - После N подряд network-fails объявляем "сеть отсутствует" → blocked=true.
/// - После M подряд успешных запросов возвращаем blocked=false (плавный recovery).
/// - При blocked'е раз в 5 секунд триггерим silent health-ping: GET небольшого
///   well-known документа (server timestamp). Если он отвечает → success counter растёт.
/// - Локальное чтение SwiftData продолжает работать — мы блокируем только write-actions
///   (см. DataService.swift + view-level disable через `isWriteBlocked`).
/// - Параллельно NWPathMonitor: если OS сообщает `path.status != .satisfied`
///   (airplane mode, нет сетевого пути) — preemptive lock сразу, без ожидания threshold.
///   Восстановление всё равно через successThreshold (path up != API up).
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

    /// NWPathMonitor сообщает что путь не satisfied (airplane mode / нет сети на уровне OS).
    /// Используется как preemptive lock — мгновенный override без ожидания threshold'а.
    private(set) var pathUnsatisfied: Bool = false

    /// Сколько подряд network-fails нужно для блокировки UI.
    /// TG-style: реагируем сразу на первый network-fail. На flaky 2G / data-loss клиент должен
    /// мгновенно показать индикатор и остановить flush, а не ждать 3 × URLSession-timeout (= 30 сек).
    static let failThreshold = 1

    /// Сколько подряд successes нужно для разблокировки.
    /// Тоже один success → выходим из blocked мгновенно (TG-style recovery).
    static let successThreshold = 1

    /// Период silent retry-ping'а пока blocked=true.
    static let retryInterval: TimeInterval = 5.0

    private var retryTimer: Timer?
    private weak var firestore: FirestoreService?
    private weak var syncEngine: SyncEngine?
    private let log = Logger(subsystem: "RUGyron.IWish", category: "NetworkMonitor")

    /// Кэш пути к последнему успешно прочитанному документу — для дешёвого silentPing.
    /// Один GET / 5 sec вместо runQuery с N reads. Сбрасывается на nil если ping fail'нул на нём.
    private var lightPingPath: String?

    /// OS-level path monitor — детектит airplane mode и пропадание сети моментально.
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "RUGyron.IWish.NetworkMonitor.path")

    private var pathPollTimer: Timer?

    init() {
        // Pessimistic boot: проверяем NWPathMonitor сразу синхронно, чтобы при offline-старте
        // не показывать "online" пока не прилетит первый async path callback (может занять
        // секунды на iOS). Без этого: запуск в 100% loss → splash снимается мгновенно → UI
        // показывает зелёный icon → через 5+ сек прилетает unsatisfied → switch на wifi.slash.
        // Это не TG-style. Лучше startовать pessimistic и upgrade'нуть когда сеть реально есть.
        let initialPath = pathMonitor.currentPath
        if initialPath.status != .satisfied {
            pathUnsatisfied = true
            isBlocked = true
        }
        setupPathMonitor()
        observeForeground()
        startPathPolling()
    }

    private func setupPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let unsatisfied = (path.status != .satisfied)
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(unsatisfied: unsatisfied)
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    /// Backup для случаев когда NWPathMonitor pathUpdateHandler не срабатывает (наблюдалось
    /// на iOS 26 при toggle airplane mode внутри уже запущенного app — handler не вызывался).
    /// Каждые 2 сек читаем currentPath напрямую и synchronously синкаем state.
    private func startPathPolling() {
        pathPollTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let cur = self.pathMonitor.currentPath
                let unsatisfied = (cur.status != .satisfied)
                if unsatisfied != self.pathUnsatisfied {
                    self.handlePathUpdate(unsatisfied: unsatisfied)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pathPollTimer = timer
    }

    /// При возврате app в foreground пересоздаём NWPathMonitor — iOS может suspend'ить его
    /// в background, и path callback не приходит сразу при airplane mode toggle.
    private func observeForeground() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restartPathMonitor()
            }
        }
    }

    private func restartPathMonitor() {
        log.info("NetworkMonitor: restarting NWPathMonitor on foreground")
        let snapshot = pathMonitor.currentPath
        let unsatisfied = (snapshot.status != .satisfied)
        handlePathUpdate(unsatisfied: unsatisfied)
    }

    /// Реакция на OS path update — моментально mirror'им state в isBlocked.
    /// UX как в TG: путь пропал — banner моментально; путь вернулся — banner сразу прячется
    /// (даже если Firestore ещё не connected). HTTP-fails остаются как secondary threshold для
    /// случаев когда path satisfied но API недоступен (captive portal / DNS / firewall).
    private func handlePathUpdate(unsatisfied: Bool) {
        let wasUnsatisfied = pathUnsatisfied
        pathUnsatisfied = unsatisfied
        if unsatisfied {
            if !isBlocked {
                isBlocked = true
                consecutiveSuccesses = 0
                startRetryTimer()
                log.warning("NetworkMonitor: BLOCKED preemptively (NWPath unsatisfied)")
            }
        } else if wasUnsatisfied {
            // Path вернулся → instant unblock. consecutiveFails сбросим чтобы HTTP threshold
            // не оставил blocked при первой transient ошибке.
            log.info("NetworkMonitor: UNBLOCKED — NWPath satisfied")
            isBlocked = false
            consecutiveFails = 0
            consecutiveSuccesses = 0
            stopRetryTimer()
            // Offline outbox: запустить flush pending ops моментально после восстановления сети.
            syncEngine?.onNetworkUp()
        }
    }

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

    /// SyncEngine ref — триггерим `onNetworkUp()` когда path satisfied (out of blocked state).
    func attach(syncEngine: SyncEngine) {
        self.syncEngine = syncEngine
    }

    /// Записать успешный сетевой запрос. Threshold-based exit из blocked-state.
    func recordSuccess() {
        consecutiveFails = 0
        consecutiveSuccesses += 1
        if isBlocked && consecutiveSuccesses >= Self.successThreshold {
            isBlocked = false
            stopRetryTimer()
            log.info("NetworkMonitor: UNBLOCKED after \(self.consecutiveSuccesses, privacy: .public) successes")
            syncEngine?.onNetworkUp()
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
