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
    var sharedWishlistID: String?
    var gradientSeed: Int = 0
    /// "owner", "editor", "viewer", nil (personal)
    var myRole: String?
    /// Whether the current user can invite others to this shared wishlist
    var canInvite: Bool = false
    /// Number of participants (synced from Firestore)
    var memberCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Item.wishlist)
    var items: [Item]?

    init(
        name: String,
        coverImageData: Data? = nil,
        coverEmoji: String? = nil,
        ownerRecordID: String? = nil,
        isShared: Bool = false,
        isArchived: Bool = false,
        sharedWishlistID: String? = nil,
        gradientSeed: Int? = nil
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
        self.sharedWishlistID = sharedWishlistID
        self.gradientSeed = gradientSeed ?? DefaultCoverGenerator.stableHash(self.id.uuidString)
    }
}

// MARK: - Permissions

extension Wishlist {
    /// Может ли текущий юзер редактировать содержимое (items + сам wishlist).
    /// Personal wishlists всегда editable. Shared — только если роль owner/editor.
    var isEditable: Bool {
        if !isShared { return true }
        guard let role = myRole else { return true } // legacy / pending sync
        return role == "owner" || role == "editor"
    }

    /// Только владелец shared wishlist'а — может расшаривать/менять роли/удалять wishlist целиком.
    var isOwnedByMe: Bool {
        if !isShared { return true }  // personal — own
        return myRole == "owner"
    }

    /// Является ли роль текущего юзера "viewer" (только просмотр).
    var isViewerOnly: Bool {
        return isShared && myRole == "viewer"
    }
}
