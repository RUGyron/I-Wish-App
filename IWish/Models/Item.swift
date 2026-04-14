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
    var currency: String = "RUB"
    var url: String?
    var linkMetadataData: Data?
    var tierRaw: String = "maybe"
    var sortIndex: Double = 1000.0
    var probationEndAt: Date?
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
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
        self.tierRaw = tier.rawValue
        self.sortIndex = sortIndex
        self.isArchived = false
        self.createdAt = now
        self.updatedAt = now
    }
}
