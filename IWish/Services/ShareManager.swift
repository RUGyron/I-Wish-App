import SwiftUI
import SwiftData
import CryptoKit

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
        canInvite: Bool,
        ownerUID: String,
        ownerName: String?
    ) async {
        isLoading = true
        error = nil

        do {
            print("[Share] Starting generateShare, ownerUID: \(ownerUID)")

            // 0. Получить ключ шифрования wishlist'а из Keychain.
            //    Если nil — wishlist никогда не шифровался (создан до encryption); это inconsistency.
            //    DataService.createWishlist всегда сохраняет ключ — но защита от corner case.
            guard let key = KeychainService.load(for: wishlist.id.uuidString) else {
                print("[Share] FAILED: no key in Keychain for wishlist \(wishlist.id.uuidString)")
                self.error = "Не найден ключ шифрования списка. Попробуйте создать список заново."
                isLoading = false
                return
            }

            let newShortID = String(
                wishlist.id.uuidString
                    .replacingOccurrences(of: "-", with: "")
                    .prefix(12)
                    .lowercased()
            )

            // Always delete existing invite link before creating new one
            try? await firestore.deleteInviteLink(shortID: newShortID)

            // 1. Publish wishlist + items to Firestore (encrypted with wishlist key)
            let localItems = (wishlist.items ?? []).filter { !$0.isArchived }
            // При первой публикации в shared переносим существующих авторов из локальных items.
                // Для personal items, добавленных ДО внедрения авторства, поля будут nil — UI это терпит
            // и не покажет "от <имя>", что корректно (мы не выдумываем автора задним числом).
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
                    isArchived: item.isArchived,
                    addedByUID: item.addedByUID,
                    addedByName: item.addedByName
                )
            }
            try await firestore.createSharedWishlist(
                wishlistID: wishlist.id.uuidString,
                name: wishlist.name,
                emoji: wishlist.coverEmoji,
                coverImageData: wishlist.coverImageData,
                gradientSeed: wishlist.gradientSeed,
                ownerUID: ownerUID,
                ownerName: ownerName,
                items: sharedItems,
                key: key
            )

            let itemCount = localItems.count
            let expiry = ttl.duration.map { Date.now.addingTimeInterval($0) }

            // 2. Create invite link in Firestore for QR/link resolution (encrypted preview)
            try await firestore.createInviteLink(
                shortID: newShortID,
                wishlistID: wishlist.id.uuidString,
                wishlistName: wishlist.name,
                wishlistEmoji: wishlist.coverEmoji,
                wishlistCoverImageData: wishlist.coverImageData,
                ownerName: ownerName,
                role: role.rawValue,
                itemCount: itemCount,
                gradientSeed: wishlist.gradientSeed,
                canInvite: canInvite,
                expiresAt: expiry,
                key: key
            )

            // 3. Build URL with key fragment: https://.../j/<shortID>#k=<base64key>
            let keyFragment = EncryptionService.keyFragment(key)
            let userURL = URL(string: "\(Self.linkDomain)/j/\(newShortID)#k=\(keyFragment)")!

            // 4. Update local state
            self.shareURL = userURL
            self.expiresAt = expiry
            self.shortID = newShortID
            self.wishlistID = wishlist.id
            self.wishlistRef = wishlist

            // 5. Create owner membership (owner always canInvite). Membership — plaintext, ключ не нужен.
            try await firestore.joinWishlist(wishlistID: wishlist.id.uuidString, userUID: ownerUID, role: "owner", canInvite: true)

            // 5. Mark wishlist as shared locally
            wishlist.isShared = true
            wishlist.sharedWishlistID = wishlist.id.uuidString
            wishlist.ownerRecordID = ownerUID
            wishlist.myRole = "owner"  // иначе UI не показывает owner-only фичи до первого polling refresh
            wishlist.canInvite = true // owner always can invite
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
            try? await firestore.deleteSharedWishlistFull(wishlistID: wid.uuidString)
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
