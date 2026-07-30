import Foundation
import SwiftData

@Model
final class Item {
    var id: UUID = UUID()
    var name: String = ""
    var descriptionText: String?
    var coverImageData: Data?
    var coverEmoji: String?
    var priceValue: Double?
    var priceMaxValue: Double?
    var currency: String = "RUB"
    var url: String?
    var linkMetadataData: Data?
    var tierRaw: String = "maybe"
    var sortIndex: Double = 1000.0
    var probationEndAt: Date?
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Цвет градиента-фона под эмодзи (когда coverImageData == nil).
    /// nil → DefaultCoverView fallback'нется на stableHash(UUID).
    var gradientHue: Double?
    /// UID юзера, который добавил item (для проверок). Опционально — у legacy items нет.
    var addedByUID: String?
    /// displayName юзера на момент добавления (для отображения "от <имя>"). Опционально.
    var addedByName: String?
    /// Soft-delete tombstone. UI фильтрует isTombstoned=true; CF чистит через 30 дней после deletedAt.
    /// Решает offline conflict "A удалил, B одновременно редактирует": LWW по deletedAt vs fieldTimestamps.
    ///
    /// **ВАЖНО**: было `isDeleted` — переименовано в `isTombstoned` так как `isDeleted`
    /// reserved property в NSManagedObject (CoreData base SwiftData). Конфликт приводил к
    /// тому что SwiftData рассматривал объект как scheduled-for-deletion и regenerate'ил
    /// его с default false → UI flip-back после визуального удаления.
    var isTombstoned: Bool = false
    var deletedAt: Date?
    /// JSON dict `{fieldName: Date}` для per-field LWW при offline-sync.
    /// Каждый локальный edit обновляет timestamp поля; на sync клиент мерджит per-field на
    /// основе этих timestamps vs server'ных.
    var fieldTimestampsJSON: Data?
    var wishlist: Wishlist?

    var tier: ItemTier {
        get { ItemTier(rawValue: tierRaw) ?? .maybe }
        set { tierRaw = newValue.rawValue }
    }

    var price: Double? {
        get { priceValue }
        set { priceValue = newValue }
    }

    var priceMax: Double? {
        get { priceMaxValue }
        set { priceMaxValue = newValue }
    }

    enum PriceMode {
        case none
        case exact(Double)
        case range(min: Double, max: Double)
    }

    var priceMode: PriceMode {
        switch (priceValue, priceMaxValue) {
        case (nil, nil): return .none
        case (let p?, nil): return .exact(p)
        case (let p?, let m?) where m > p: return .range(min: p, max: m)
        case (let p?, let m?): return .range(min: m, max: p)
        case (nil, let m?): return .range(min: 0, max: m)
        }
    }

    init(
        name: String,
        tier: ItemTier = .maybe,
        sortIndex: Double = 1000.0,
        currency: String = "RUB",
        price: Double? = nil,
        priceMax: Double? = nil,
        descriptionText: String? = nil,
        url: String? = nil,
        coverImageData: Data? = nil,
        coverEmoji: String? = nil,
        gradientHue: Double? = nil,
        addedByUID: String? = nil,
        addedByName: String? = nil
    ) {
        let now = Date.now
        self.id = UUID()
        self.name = name
        self.descriptionText = descriptionText
        self.coverImageData = coverImageData
        self.coverEmoji = coverEmoji
        self.priceValue = price
        self.priceMaxValue = priceMax
        self.currency = currency
        self.url = url
        self.tierRaw = tier.rawValue
        self.sortIndex = sortIndex
        self.isArchived = false
        self.createdAt = now
        self.updatedAt = now
        self.gradientHue = gradientHue
        self.addedByUID = addedByUID
        self.addedByName = addedByName
    }
}
