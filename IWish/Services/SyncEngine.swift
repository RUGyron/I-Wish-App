import Foundation
import SwiftData
import os.log

private let syncLog = Logger(subsystem: "RUGyron.IWish", category: "SyncEngine")

/// Offline-sync outbox engine.
///
/// **Жизненный цикл операции:**
/// 1. DataService.update*/delete* применяет изменение локально (SwiftData) + вызывает `enqueue(op)`.
/// 2. Op оседает в `PendingOperation` таблице.
/// 3. `flush()` срабатывает: (a) при появлении сети, (b) каждые 60 сек если есть ops,
///    (c) после успешного push (chain-trigger), (d) при app foreground.
/// 4. Op'a процессится — клиент делает GET текущего серверного состояния, мерджит per-field
///    LWW, PATCH с precondition `updateTime`. Precondition fail → retry from GET.
/// 5. Success → op удаляется из таблицы. Failure → recordFailure + exponential backoff.
///
/// **Idempotency**: все ID — client-side UUID. Retry safe.
/// **Sequencing**: `dependsOnOpID` — item-create ждёт wishlist-create.
@MainActor
@Observable
final class SyncEngine {
    /// Кол-во pending ops (для status chip).
    private(set) var pendingCount: Int = 0
    /// Сейчас идёт flush.
    private(set) var isSyncing: Bool = false
    /// Момент старта текущего flush — для UI hard-cap отображения spinner'а.
    private(set) var syncStartedAt: Date?
    /// Последний успешный flush (для UI hint "всё сохранено").
    private(set) var lastSuccess: Date?
    /// Последняя ошибка op'ы (для красного chip / tooltip).
    private(set) var lastError: String?

    /// Сколько ops максимум обработать за один flush цикл, чтобы spinner не висел вечно
    /// на медленной сети (3G/Edge). Остальные подождут следующего тика.
    static let maxOpsPerFlush = 3
    /// Max wall-clock секунд на один flush. После — break, остальное в следующий цикл.
    static let maxFlushSeconds: TimeInterval = 10

    private weak var firestore: FirestoreService?
    private weak var modelContext: ModelContext?
    private weak var networkMonitor: NetworkMonitor?
    private weak var auth: AuthService?

    private var flushTimer: Timer?
    /// Защита от concurrent flushes (только один за раз).
    private var isFlushing = false

    /// Op'ы которые были enqueued < `chipDisplayThreshold` сек назад.
    /// `hasPendingSync` игнорирует их — иначе чип «Ждёт сети» успевает мигнуть
    /// при быстром opportunistic flush (онлайн-кейс ~100-300 мс).
    private var freshlyEnqueued: Set<UUID> = []
    /// Сколько времени op должна провисеть в outbox, прежде чем UI считает её «застрявшей».
    static let chipDisplayThreshold: TimeInterval = 0.7

    /// Подключаем зависимости после полной инициализации AppServices.
    func configure(
        firestore: FirestoreService,
        modelContext: ModelContext,
        networkMonitor: NetworkMonitor,
        auth: AuthService
    ) {
        self.firestore = firestore
        self.modelContext = modelContext
        self.networkMonitor = networkMonitor
        self.auth = auth
        refreshPendingCount()
        startPeriodicFlush()
    }

    /// Запустить периодический retry pending ops (раз в 60 сек если queue не пуста).
    private func startPeriodicFlush() {
        flushTimer?.invalidate()
        let timer = Timer(timeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.pendingCount > 0 { await self.flush() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }

    /// Добавить op в outbox. UI вызывает после применения изменений локально.
    func enqueue(_ op: PendingOperation) {
        guard let ctx = modelContext else { return }
        ctx.insert(op)
        try? ctx.save()
        // Свежая op — чип-индикатор её не показывает первые `chipDisplayThreshold` секунд,
        // чтобы при быстром flush'е (онлайн) чип не мигал.
        let opID = op.id
        freshlyEnqueued.insert(opID)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.chipDisplayThreshold))
            await MainActor.run {
                guard let self else { return }
                if self.freshlyEnqueued.remove(opID) != nil {
                    // Триггерим UI redraw чтобы chip появился если op ещё pending.
                    self.refreshPendingCount()
                }
            }
        }
        refreshPendingCount()
        syncLog.info("Enqueued \(op.operationType, privacy: .public) for \(op.entityType, privacy: .public)/\(op.entityID, privacy: .public)")
        // Опrtunistic flush — если сеть есть, запускаем сразу.
        if networkMonitor?.isBlocked != true {
            Task { await flush() }
        }
    }

    /// Триггерится извне при появлении сети (NetworkMonitor → onPathSatisfied).
    func onNetworkUp() {
        guard pendingCount > 0 else { return }
        Task { await flush() }
    }

    /// Прогнать pending queue. Respects dependsOnOpID + nextRetryAt + backoff.
    /// Single-flight: повторный вызов пока flush идёт — no-op.
    /// **Hard cap** на одну итерацию: `maxOpsPerFlush` штук И `maxFlushSeconds` сек.
    /// Spinner не зависнет надолго даже на 3G — остальные ops подождут следующего тика.
    func flush() async {
        guard !isFlushing else { return }
        guard let ctx = modelContext else { return }
        isFlushing = true
        isSyncing = true
        syncStartedAt = Date()
        defer {
            isFlushing = false
            isSyncing = false
            syncStartedAt = nil
            refreshPendingCount()
        }

        let now = Date()
        var descriptor = FetchDescriptor<PendingOperation>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 100
        guard let allOps = try? ctx.fetch(descriptor) else { return }

        // FIFO с учётом dependencies. Op зависимая ждёт пока её зависимость не будет removed
        // (после успешного sync) — т.е. отсутствует в pending queue.
        let pendingIDs = Set(allOps.map { $0.id })
        let ready = allOps.filter { op in
            // Backoff schedule
            guard op.isReadyForRetry(at: now) else { return false }
            // Dependency satisfied: nil или зависимость уже success'нула (нет в pending).
            if let dep = op.dependsOnOpID, pendingIDs.contains(dep) { return false }
            return true
        }

        let flushDeadline = now.addingTimeInterval(Self.maxFlushSeconds)
        var processed = 0
        for op in ready {
            // Перепроверка networkMonitor каждую итерацию — может потеряться сеть в процессе.
            if networkMonitor?.isBlocked == true {
                syncLog.info("flush(): network blocked, pausing — \(ready.count - processed) ops left")
                break
            }
            // Hard cap: max N ops per cycle, max T seconds wall-clock.
            if processed >= Self.maxOpsPerFlush {
                syncLog.info("flush(): maxOpsPerFlush reached, deferring \(ready.count - processed) ops")
                break
            }
            if Date() >= flushDeadline {
                syncLog.info("flush(): maxFlushSeconds exceeded, deferring \(ready.count - processed) ops")
                break
            }
            do {
                try await process(op)
                ctx.delete(op)
                try? ctx.save()
                lastSuccess = Date()
                lastError = nil
            } catch {
                op.recordFailure(error)
                try? ctx.save()
                lastError = error.localizedDescription
                syncLog.warning("Op \(op.operationType, privacy: .public) for \(op.entityType, privacy: .public)/\(op.entityID, privacy: .public) failed (attempt \(op.attemptCount, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                if op.attemptCount >= PendingOperation.maxAttempts {
                    syncLog.error("Op \(op.id, privacy: .public) gave up after \(PendingOperation.maxAttempts) attempts")
                }
            }
            processed += 1
        }
    }

    /// Manual retry от юзера (tap на status chip).
    func retryAll() async {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<PendingOperation>()
        if let allOps = try? ctx.fetch(descriptor) {
            for op in allOps {
                op.nextRetryAt = nil
                op.lastError = nil
            }
            try? ctx.save()
        }
        await flush()
    }

    /// Очистить все ops (например при signOut).
    func clearAll() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<PendingOperation>()
        if let allOps = try? ctx.fetch(descriptor) {
            for op in allOps { ctx.delete(op) }
            try? ctx.save()
        }
        refreshPendingCount()
    }

    /// Есть ли pending op'ы для конкретной сущности (для per-item UI indicator).
    /// Свежие op (< `chipDisplayThreshold` сек) игнорим, чтобы чип не мигал
    /// при мгновенном flush'е в online-режиме.
    func hasPendingSync(entityType: String, entityID: String) -> Bool {
        guard let ctx = modelContext else { return false }
        let predicate = #Predicate<PendingOperation> { op in
            op.entityType == entityType && op.entityID == entityID
        }
        var descriptor = FetchDescriptor<PendingOperation>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let op = try? ctx.fetch(descriptor).first else { return false }
        return !freshlyEnqueued.contains(op.id)
    }

    /// Есть ли pending op для сущности, ВКЛЮЧАЯ только что enqueued (в отличие от `hasPendingSync`,
    /// который прячет op младше `chipDisplayThreshold` ради UI-чипа). Использовать для решений об
    /// overwrite на read/merge-пути: иначе poll, влетевший в окно ~0.7с после локальной правки,
    /// затрёт её stale-снапшотом до того как op синканётся. Для data-consistency важна сама наличие op,
    /// а не её «возраст» для индикатора.
    func hasAnyPendingSync(entityType: String, entityID: String) -> Bool {
        guard let ctx = modelContext else { return false }
        let predicate = #Predicate<PendingOperation> { op in
            op.entityType == entityType && op.entityID == entityID
        }
        var descriptor = FetchDescriptor<PendingOperation>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? ctx.fetch(descriptor).first) != nil
    }

    private func refreshPendingCount() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<PendingOperation>()
        pendingCount = (try? ctx.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Operation processing

    /// Dispatch op в соответствующий обработчик. Throws → recordFailure + backoff.
    private func process(_ op: PendingOperation) async throws {
        guard let firestore else { throw SyncError.notConfigured }
        guard let uid = auth?.uid else { throw SyncError.notAuthenticated }
        switch (op.entityType, op.operationType) {
        case ("wishlist", "update"):
            try await processWishlistUpdate(op, uid: uid, firestore: firestore)
        case ("wishlist", "delete"):
            try await processWishlistDelete(op, uid: uid, firestore: firestore)
        case ("wishlist", "archive"), ("wishlist", "unarchive"):
            try await processWishlistArchive(op, uid: uid, firestore: firestore)
        case ("item", "create"):
            try await processItemCreate(op, uid: uid, firestore: firestore)
        case ("item", "update"):
            try await processItemUpdate(op, uid: uid, firestore: firestore)
        case ("item", "delete"):
            try await processItemDelete(op, uid: uid, firestore: firestore)
        case ("item", "archive"), ("item", "unarchive"):
            try await processItemArchive(op, uid: uid, firestore: firestore)
        default:
            throw SyncError.unknownOperation("\(op.entityType)/\(op.operationType)")
        }
    }

    // MARK: - Wishlist operations

    private func processWishlistUpdate(_ op: PendingOperation, uid: String, firestore: FirestoreService) async throws {
        // Payload: {"fields": {...}, "timestamps": {...}, "sharedID": optional}
        // Делегируем merge в FirestoreService — он сам читает текущее, мерджит per-field, пушит.
        let payload = decodePayload(op.payloadJSON)
        try await firestore.syncWishlistUpdate(
            uid: uid,
            wishlistID: op.entityID,
            fields: payload.fields,
            fieldTimestamps: payload.timestamps,
            sharedWishlistID: payload.sharedID
        )
    }

    private func processWishlistDelete(_ op: PendingOperation, uid: String, firestore: FirestoreService) async throws {
        let payload = decodePayload(op.payloadJSON)
        try await firestore.syncWishlistSoftDelete(
            uid: uid,
            wishlistID: op.entityID,
            deletedAt: payload.fields["deletedAt"].flatMap(parseDate) ?? Date(),
            sharedWishlistID: payload.sharedID
        )
    }

    private func processWishlistArchive(_ op: PendingOperation, uid: String, firestore: FirestoreService) async throws {
        let payload = decodePayload(op.payloadJSON)
        let archived = (payload.fields["isArchived"] as? Bool) ?? (op.operationType == "archive")
        try await firestore.syncWishlistArchive(
            uid: uid,
            wishlistID: op.entityID,
            isArchived: archived,
            sharedWishlistID: payload.sharedID
        )
    }

    // MARK: - Item operations

    private func processItemCreate(_ op: PendingOperation, uid: String, firestore: FirestoreService) async throws {
        let payload = decodePayload(op.payloadJSON)
        guard let wishlistID = payload.parentID else { throw SyncError.missingParent }
        let keyID = payload.sharedID ?? wishlistID
        guard let key = KeychainService.load(for: keyID) else { throw SyncError.notConfigured }

        let fields = payload.fields
        let name = (fields["name"] as? String) ?? ""
        let tier = (fields["tier"] as? String) ?? "maybe"
        let price = fields["price"] as? Double
        let priceMax = fields["priceMax"] as? Double
        let currency = (fields["currency"] as? String) ?? "RUB"
        let url = fields["url"] as? String
        let emoji = fields["coverEmoji"] as? String
        let sortIndex = (fields["sortIndex"] as? Double) ?? 1000
        let descriptionText = fields["description"] as? String
        let coverImageData = fields["coverImageData"] as? Data
        let linkMetadataData = fields["linkMeta"] as? Data
        let probationEndAt = parseDate(fields["probationEndAt"] as Any)
        let gradientHue = fields["gradientHue"] as? Double
        let addedByUID = fields["addedByUID"] as? String
        let addedByName = fields["addedByName"] as? String

        if let sharedID = payload.sharedID {
            try await firestore.createSharedItem(
                wishlistID: sharedID,
                itemID: op.entityID,
                name: name,
                tier: tier,
                price: price,
                priceMax: priceMax,
                currency: currency,
                url: url,
                emoji: emoji,
                sortIndex: sortIndex,
                descriptionText: descriptionText,
                coverImageData: coverImageData,
                linkMetadataData: linkMetadataData,
                probationEndAt: probationEndAt,
                addedByUID: addedByUID,
                addedByName: addedByName,
                gradientHue: gradientHue,
                key: key
            )
        } else {
            try await firestore.createPersonalItem(
                uid: uid,
                wishlistID: wishlistID,
                itemID: op.entityID,
                name: name,
                tier: tier,
                price: price,
                priceMax: priceMax,
                currency: currency,
                url: url,
                emoji: emoji,
                sortIndex: sortIndex,
                descriptionText: descriptionText,
                coverImageData: coverImageData,
                linkMetadataData: linkMetadataData,
                probationEndAt: probationEndAt,
                addedByUID: addedByUID,
                addedByName: addedByName,
                gradientHue: gradientHue,
                key: key
            )
        }
    }

    private func processItemUpdate(_ op: PendingOperation, uid: String, firestore: FirestoreService) async throws {
        let payload = decodePayload(op.payloadJSON)
        guard let wishlistID = payload.parentID else { throw SyncError.missingParent }
        try await firestore.syncItemUpdate(
            uid: uid,
            wishlistID: wishlistID,
            itemID: op.entityID,
            fields: payload.fields,
            fieldTimestamps: payload.timestamps,
            sharedWishlistID: payload.sharedID
        )
    }

    private func processItemDelete(_ op: PendingOperation, uid: String, firestore: FirestoreService) async throws {
        let payload = decodePayload(op.payloadJSON)
        guard let wishlistID = payload.parentID else { throw SyncError.missingParent }
        try await firestore.syncItemSoftDelete(
            uid: uid,
            wishlistID: wishlistID,
            itemID: op.entityID,
            deletedAt: payload.fields["deletedAt"].flatMap(parseDate) ?? Date(),
            sharedWishlistID: payload.sharedID
        )
    }

    private func processItemArchive(_ op: PendingOperation, uid: String, firestore: FirestoreService) async throws {
        let payload = decodePayload(op.payloadJSON)
        guard let wishlistID = payload.parentID else { throw SyncError.missingParent }
        let archived = (payload.fields["isArchived"] as? Bool) ?? (op.operationType == "archive")
        try await firestore.syncItemArchive(
            uid: uid,
            wishlistID: wishlistID,
            itemID: op.entityID,
            isArchived: archived,
            sharedWishlistID: payload.sharedID
        )
    }

    // MARK: - Payload helpers

    struct DecodedPayload {
        var fields: [String: Any] = [:]
        var timestamps: [String: Date] = [:]
        /// Parent reference (для items это wishlistID).
        var parentID: String?
        /// SharedWishlistID если op для shared wishlist.
        var sharedID: String?
    }

    private func decodePayload(_ data: Data?) -> DecodedPayload {
        var result = DecodedPayload()
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return result }
        // Бинарные поля лежат как base64-маркер (см. SyncPayload.binaryMarkerKey) — разворачиваем
        // обратно в Data, иначе `fields["coverImageData"] as? Data` ниже даёт nil и фото не синкается.
        if let fields = obj["fields"] as? [String: Any] {
            result.fields = fields.mapValues { SyncPayload.restore($0) }
        }
        if let ts = obj["timestamps"] as? [String: String] {
            let iso = ISO8601DateFormatter()
            for (k, v) in ts {
                if let d = iso.date(from: v) { result.timestamps[k] = d }
            }
        }
        result.parentID = obj["parentID"] as? String
        result.sharedID = obj["sharedID"] as? String
        return result
    }

    private func parseDate(_ value: Any) -> Date? {
        if let d = value as? Date { return d }
        if let s = value as? String { return ISO8601DateFormatter().date(from: s) }
        if let t = value as? TimeInterval { return Date(timeIntervalSince1970: t) }
        return nil
    }

    enum SyncError: LocalizedError {
        case notConfigured
        case notAuthenticated
        case unknownOperation(String)
        case missingParent
        case preconditionFailed

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Sync not configured"
            case .notAuthenticated: return "Sign-in required"
            case .unknownOperation(let s): return "Unknown sync op: \(s)"
            case .missingParent: return "Item missing parent wishlist"
            case .preconditionFailed: return "Concurrent write detected"
            }
        }
    }
}

// MARK: - Payload builder

/// Помощник для DataService — собрать payloadJSON для PendingOperation.
enum SyncPayload {
    /// Ключ-маркер для бинарных полей. JSON не умеет нести `Data`, поэтому она упаковывается как
    /// `{"__b64": "<base64>"}` и разворачивается обратно в `restore(_:)` при чтении payload'а.
    ///
    /// Критично: сырая `Data` в `JSONSerialization.data(withJSONObject:)` бросает
    /// NSInvalidArgumentException — ObjC-исключение, которое `try?` НЕ перехватывает, т.е. процесс
    /// падает. Без этой упаковки добавление желания с фото / по ссылке и смена обложки списка
    /// роняли приложение, причём уже ПОСЛЕ локального save() — операция не попадала в outbox
    /// и изменение не уезжало на сервер вообще.
    static let binaryMarkerKey = "__b64"

    static func encode(
        fields: [String: Any] = [:],
        timestamps: [String: Date] = [:],
        parentID: String? = nil,
        sharedID: String? = nil
    ) -> Data? {
        let iso = ISO8601DateFormatter()
        var dict: [String: Any] = [:]
        // Fields могут содержать Date и Data — приводим к JSON-совместимому виду.
        var fieldsForJSON: [String: Any] = [:]
        for (k, v) in fields {
            fieldsForJSON[k] = jsonSafe(v, iso: iso)
        }
        dict["fields"] = fieldsForJSON
        dict["timestamps"] = timestamps.mapValues { iso.string(from: $0) }
        if let parentID { dict["parentID"] = parentID }
        if let sharedID { dict["sharedID"] = sharedID }
        return try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }

    /// Рекурсивно приводит значение к JSON-совместимому виду: `Data` → base64-маркер,
    /// `Date` → ISO8601, вложенные словари/массивы — поэлементно.
    /// `nil`-опционалы не трогаем: они валидно бриджатся в JSON `null`.
    private static func jsonSafe(_ value: Any, iso: ISO8601DateFormatter) -> Any {
        if let data = value as? Data { return [binaryMarkerKey: data.base64EncodedString()] }
        if let date = value as? Date { return iso.string(from: date) }
        if let dict = value as? [String: Any] { return dict.mapValues { jsonSafe($0, iso: iso) } }
        if let array = value as? [Any] { return array.map { jsonSafe($0, iso: iso) } }
        return value
    }

    /// Обратная операция к `jsonSafe`: base64-маркер → `Data`, рекурсивно.
    /// Значения без маркера возвращаются как есть, поэтому payload'ы без бинарных полей
    /// (в т.ч. записанные до этого фикса) читаются ровно как раньше.
    static func restore(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            if dict.count == 1, let b64 = dict[binaryMarkerKey] as? String {
                return Data(base64Encoded: b64) ?? value
            }
            return dict.mapValues { restore($0) }
        }
        if let array = value as? [Any] { return array.map { restore($0) } }
        return value
    }
}
