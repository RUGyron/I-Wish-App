import Foundation
import SwiftData

@Model
final class Wishlist {
    // Без `@Attribute(.unique)` — CloudKit mirror не поддерживает unique constraints.
    // Уникальность гарантируется `UUID()`.
    var id: UUID
    var name: String
    var coverImageData: Data?
    var coverEmoji: String?
    var createdAt: Date
    var updatedAt: Date
    var ownerRecordID: String?

    @Relationship(deleteRule: .cascade, inverse: \Item.wishlist)
    var items: [Item] = []

    init(
        name: String,
        coverImageData: Data? = nil,
        coverEmoji: String? = nil,
        ownerRecordID: String? = nil
    ) {
        let now = Date.now
        self.id = UUID()
        self.name = name
        self.coverImageData = coverImageData
        self.coverEmoji = coverEmoji
        self.createdAt = now
        self.updatedAt = now
        self.ownerRecordID = ownerRecordID
    }
}
