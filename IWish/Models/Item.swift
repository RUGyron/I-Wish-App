import Foundation
import SwiftData

@Model
final class Item {
    // Без `@Attribute(.unique)` — CloudKit mirror не поддерживает unique constraints.
    // Уникальность гарантируется `UUID()`.
    var id: UUID
    var name: String
    var descriptionText: String?
    var coverImageData: Data?
    var coverEmoji: String?
    var price: Decimal?
    var currency: String
    var url: String?
    var linkMetadataData: Data?
    var tier: ItemTier
    var sortIndex: Double
    var probationEndAt: Date?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var wishlist: Wishlist?

    init(
        name: String,
        tier: ItemTier = .maybe,
        sortIndex: Double = 1000.0,
        currency: String = "RUB",
        price: Decimal? = nil,
        descriptionText: String? = nil,
        url: String? = nil,
        coverImageData: Data? = nil,
        coverEmoji: String? = nil
    ) {
        let now = Date.now
        self.id = UUID()
        self.name = name
        self.descriptionText = descriptionText
        self.coverImageData = coverImageData
        self.coverEmoji = coverEmoji
        self.price = price
        self.currency = currency
        self.url = url
        self.linkMetadataData = nil
        self.tier = tier
        self.sortIndex = sortIndex
        self.probationEndAt = nil
        self.isArchived = false
        self.createdAt = now
        self.updatedAt = now
    }
}
