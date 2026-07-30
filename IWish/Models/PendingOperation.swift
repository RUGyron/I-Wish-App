import Foundation
import SwiftData

/// Outbox-запись для offline-sync. Каждая локальная мутация (create/update/delete/archive)
/// создаёт PendingOperation, который SyncEngine разворачивает в Firestore при наличии сети.
///
/// **Идемпотентность**: все ID — client-side UUID, операции safe для retry.
/// **Sequencing**: `dependsOnOpID` цепочка — например item create зависит от wishlist create.
/// **Backoff**: `nextRetryAt` exponential (5s → 30s → 2m → 10m → 1h → drop).
@Model
final class PendingOperation {
    @Attribute(.unique) var id: UUID = UUID()
    /// "wishlist" | "item" | "membership" | "wishlistShare" | "wishlistLeave"
    var entityType: String = "item"
    /// Local UUID сущности (Wishlist.id / Item.id). Для shared ops — sharedWishlistID.
    var entityID: String = ""
    /// "create" | "update" | "delete" | "archive" | "unarchive" | "reorder" | "leaveWishlist"
    var operationType: String = "update"
    /// Сериализованный payload — какие поля поменялись + их новые значения + per-field timestamps.
    /// JSON структура: `{"fields": {...}, "timestamps": {"name": ISO8601, ...}}`.
    var payloadJSON: Data?
    /// Когда мутация произошла локально.
    var createdAt: Date = Date()
    /// Время последней попытки sync.
    var lastAttempt: Date?
    /// Сколько раз пытались отправить (для backoff).
    var attemptCount: Int = 0
    /// Текст последней ошибки (для диагностики в UI).
    var lastError: String?
    /// Когда можно попробовать снова (exponential backoff).
    var nextRetryAt: Date?
    /// FK к op'ы которая должна успешно sync'нуться перед нашей. nil = независимая.
    /// Пример: item-create depends on wishlist-create — нельзя запушить item пока wishlist
    /// не существует на сервере.
    var dependsOnOpID: UUID?

    init(
        entityType: String,
        entityID: String,
        operationType: String,
        payloadJSON: Data? = nil,
        dependsOnOpID: UUID? = nil
    ) {
        self.id = UUID()
        self.entityType = entityType
        self.entityID = entityID
        self.operationType = operationType
        self.payloadJSON = payloadJSON
        self.createdAt = Date()
        self.attemptCount = 0
        self.dependsOnOpID = dependsOnOpID
    }
}

extension PendingOperation {
    /// Exponential backoff schedule: [5s, 30s, 2m, 10m, 1h]. После 6-й попытки — drop op'у.
    static let backoffSchedule: [TimeInterval] = [5, 30, 120, 600, 3600]
    static let maxAttempts = 6

    /// Готова ли op'a к попытке отправки (учитывая backoff и now).
    func isReadyForRetry(at now: Date = Date()) -> Bool {
        guard attemptCount < Self.maxAttempts else { return false }
        guard let next = nextRetryAt else { return true }
        return now >= next
    }

    /// Зафиксировать failed-попытку и установить следующий retry-момент.
    func recordFailure(_ error: Error, at now: Date = Date()) {
        attemptCount += 1
        lastAttempt = now
        lastError = error.localizedDescription
        let idx = min(attemptCount - 1, Self.backoffSchedule.count - 1)
        nextRetryAt = now.addingTimeInterval(Self.backoffSchedule[idx])
    }
}
