import Foundation
import SwiftData

@Model
final class Item {
    var id: UUID
    var name: String
    var descriptionText: String?
    var coverImageData: Data?
    var coverEmoji: String?
    var priceValue: Double?
    var currency: String
    var url: String?
    var linkMetadataData: Data?
    var tierRaw: String
    var sortIndex: Double
    var probationEndAt: Date?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var wishlist: Wishlist?

    var tier: ItemTier {
        get { ItemTier(rawValue: tierRaw) ?? .maybe }
        set { tierRaw = newValue.rawValue }
    }

    var price: Double? {
        get { priceValue }
        set { priceValue = newValue }
    }

    init(
        name: String,
        tier: ItemTier = .maybe,
        sortIndex: Double = 1000.0,
        currency: String = "RUB",
        price: Double? = nil,
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
        self.priceValue = price
        self.currency = currency
        self.url = url
        self.linkMetadataData = nil
        self.tierRaw = tier.rawValue
        self.sortIndex = sortIndex
        self.probationEndAt = nil
        self.isArchived = false
        self.createdAt = now
        self.updatedAt = now
    }
}
