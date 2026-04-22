import CloudKit
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
    private let sharingService = CloudKitSharingService()

    private let ckContainer = CKContainer(
        identifier: ModelContainerFactory.cloudKitContainerID
    )

    func generateShare(
        for wishlist: Wishlist,
        role: ShareRole,
        ttl: InviteTTL,
        ownerName: String?
    ) async {
        isLoading = true
        error = nil

        do {
            // 1. Get owner's userRecordID
            let ownerRecordID = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CKRecord.ID, Error>) in
                ckContainer.fetchUserRecordID { recordID, error in
                    if let recordID { cont.resume(returning: recordID) }
                    else { cont.resume(throwing: error ?? CKError(.internalError)) }
                }
            }

            let newShortID = String(
                wishlist.id.uuidString
                    .replacingOccurrences(of: "-", with: "")
                    .prefix(12)
                    .lowercased()
            )

            // Always delete existing ShareLink before creating new one
            try? await sharingService.deleteShareLink(shortID: newShortID)

            // 2. Publish wishlist + items to PublicDB
            let localItems = (wishlist.items ?? []).filter { !$0.isArchived }
            let sharedItems = localItems.map { item in
                CloudKitSharingService.SharedItemInfo(
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
            try await sharingService.publishWishlist(
                id: wishlist.id.uuidString,
                name: wishlist.name,
                emoji: wishlist.coverEmoji,
                ownerRecordID: ownerRecordID.recordName,
                ownerName: ownerName,
                items: sharedItems,
                role: role.rawValue
            )

            let itemCount = localItems.count
            let expiry = ttl.duration.map { Date.now.addingTimeInterval($0) }
            let effectiveExpiry = expiry ?? Date.distantFuture

            // 3. Create ShareLink in PublicDB for QR/link resolution
            let userURL = URL(string: "\(Self.linkDomain)/j/\(newShortID)")!

            try await sharingService.createShareLink(
                shortID: newShortID,
                wishlistID: wishlist.id.uuidString,
                wishlistName: wishlist.name,
                wishlistEmoji: wishlist.coverEmoji,
                ownerName: ownerName,
                role: role,
                itemCount: itemCount,
                expiresAt: effectiveExpiry
            )

            // 4. Update local state
            self.shareURL = userURL
            self.expiresAt = expiry
            self.shortID = newShortID
            self.wishlistID = wishlist.id
            self.wishlistRef = wishlist

            // 5. Mark wishlist as shared
            wishlist.isShared = true
            wishlist.sharedWishlistID = wishlist.id.uuidString
            wishlist.updatedAt = .now
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Wishlist ID to track for cleanup on revoke
    private var wishlistID: UUID?
    private var wishlistRef: Wishlist?

    func revokeAll() async {
        // Delete SharedWishlist + SharedItems from PublicDB
        if let wid = wishlistID {
            try? await sharingService.deleteSharedWishlist(wishlistID: wid.uuidString)
        }
        // Delete ShareLink from PublicDB
        if let shortID {
            try? await sharingService.deleteShareLink(shortID: shortID)
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
