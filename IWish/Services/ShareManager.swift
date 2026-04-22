import SwiftUI
import SwiftData

// MARK: - Share Role

enum ShareRole: String, CaseIterable, Identifiable {
    case editor
    case viewer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .editor: return "Редактор"
        case .viewer: return "Только просмотр"
        }
    }
}

// MARK: - Share Manager

@Observable
final class ShareManager {
    private(set) var shareURL: URL?
    private(set) var expiresAt: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var shortID: String?

    private static let linkDomain = "https://rugyron.github.io/I-Wish-App"
    private let firestore = FirestoreService()

    func generateShare(
        for wishlist: Wishlist,
        role: ShareRole,
        ttl: InviteTTL,
        ownerUID: String,
        ownerName: String?
    ) async {
        isLoading = true
        error = nil

        do {
            print("[Share] Starting generateShare, ownerUID: \(ownerUID)")
            let newShortID = String(
                wishlist.id.uuidString
                    .replacingOccurrences(of: "-", with: "")
                    .prefix(12)
                    .lowercased()
            )

            // Always delete existing invite link before creating new one
            try? await firestore.deleteInviteLink(shortID: newShortID)

            // 1. Publish wishlist + items to Firestore
            let localItems = (wishlist.items ?? []).filter { !$0.isArchived }
            let sharedItems = localItems.map { item in
                FirestoreService.SharedItemInfo(
                    itemID: item.id.uuidString,
                    name: item.name,
                    tier: item.tier.rawValue,
                    price: item.price,
                    currency: item.currency,
                    url: item.url,
                    coverEmoji: item.coverEmoji,
                    sortIndex: item.sortIndex,
                    isArchived: item.isArchived
                )
            }
            try await firestore.publishWishlist(
                id: wishlist.id.uuidString,
                name: wishlist.name,
                emoji: wishlist.coverEmoji,
                ownerUID: ownerUID,
                ownerName: ownerName,
                items: sharedItems
            )

            let itemCount = localItems.count
            let expiry = ttl.duration.map { Date.now.addingTimeInterval($0) }

            // 2. Create invite link in Firestore for QR/link resolution
            let userURL = URL(string: "\(Self.linkDomain)/j/\(newShortID)")!

            try await firestore.createInviteLink(
                shortID: newShortID,
                wishlistID: wishlist.id.uuidString,
                wishlistName: wishlist.name,
                wishlistEmoji: wishlist.coverEmoji,
                ownerName: ownerName,
                role: role.rawValue,
                itemCount: itemCount,
                expiresAt: expiry
            )

            // 3. Update local state
            self.shareURL = userURL
            self.expiresAt = expiry
            self.shortID = newShortID
            self.wishlistID = wishlist.id
            self.wishlistRef = wishlist

            // 4. Mark wishlist as shared
            wishlist.isShared = true
            wishlist.sharedWishlistID = wishlist.id.uuidString
            wishlist.updatedAt = .now
            print("[Share] SUCCESS — shareURL: \(userURL)")
        } catch {
            print("[Share] FAILED: \(error)")
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Wishlist ID to track for cleanup on revoke
    private var wishlistID: UUID?
    private var wishlistRef: Wishlist?

    func revokeAll() async {
        // Delete shared wishlist + items from Firestore
        if let wid = wishlistID {
            try? await firestore.deleteSharedWishlist(wishlistID: wid.uuidString)
        }
        // Delete invite link from Firestore
        if let shortID {
            try? await firestore.deleteInviteLink(shortID: shortID)
        }
        wishlistRef?.isShared = false
        wishlistRef?.updatedAt = .now
        wishlistRef = nil
        shareURL = nil
        expiresAt = nil
        shortID = nil
        wishlistID = nil
        error = nil
    }

    var hasActiveShare: Bool { shareURL != nil }

    func invitationText(wishlistName: String) -> String {
        guard let url = shareURL else { return "" }
        return "Присоединяйся к моему списку желаний «\(wishlistName)» в I Wish!\n\n\(url.absoluteString)"
    }
}
