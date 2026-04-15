import Foundation
import SwiftData

@Model
final class Wishlist {
    var id: UUID = UUID()
    var name: String = ""
    var coverImageData: Data?
    var coverEmoji: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var ownerRecordID: String?
    var isShared: Bool = false
    var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Item.wishlist)
    var items: [Item]?

    init(
        name: String,
        coverImageData: Data? = nil,
        coverEmoji: String? = nil,
        ownerRecordID: String? = nil,
        isShared: Bool = false,
        isArchived: Bool = false
    ) {
        let now = Date.now
        self.id = UUID()
        self.name = name
        self.coverImageData = coverImageData
        self.coverEmoji = coverEmoji
        self.createdAt = now
        self.updatedAt = now
        self.ownerRecordID = ownerRecordID
        self.isShared = isShared
        self.isArchived = isArchived
    }
}
