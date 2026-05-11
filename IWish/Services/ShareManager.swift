import SwiftUI
import SwiftData
import CryptoKit
import os.log

private let shareLog = Logger(subsystem: "RUGyron.IWish", category: "ShareManager")

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

    /// Sharing flow с защитой от owner-flip.
    ///
    /// Дизайн (post-2026-05-10 fix):
    /// - **Не-owner с canInvite** имеет право только сгенерировать новый invite link для уже
    ///   существующего share. createSharedWishlist и joinWishlist НЕ вызываются —
    ///   shared_wishlists и memberships других участников не трогаются.
    /// - **Owner** при первой публикации делает full create (createSharedWishlist + joinWishlist
    ///   для собственного owner-membership). При повторном открытии sheet'а (wishlist уже shared)
    ///   обновляется только invite link — wishlist DOC и memberships не перезаписываются,
    ///   чтобы не создавать race и не сбрасывать ownerName/createdAt без необходимости.
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
            // 0. Получить ключ шифрования wishlist'а из Keychain.
            //    Не-owner participant получает ключ при join через invite link → он у него в Keychain.
            //    Owner получает ключ при createWishlist.
            guard let key = KeychainService.load(for: wishlist.id.uuidString) else {
                shareLog.error("FAILED: no key in Keychain for wishlist \(wishlist.id.uuidString, privacy: .public)")
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

            // 1. Определить роль вызывающего относительно wishlist'а.
            //    isShared==false означает personal wishlist который сейчас впервые публикуется
            //    → текущий пользователь становится owner'ом этого share.
            //    isShared==true: проверяем ownership через WIRE-GET (не доверяем local
            //    wl.ownerRecordID / myRole — могло быть отравлено старым owner-flip багом).
            let isFirstPublish = !wishlist.isShared
            let isOwner: Bool
            if isFirstPublish {
                isOwner = true
            } else {
                // Wire-check: сравниваем актуальный ownerUID из Firestore с callerUID.
                let wireOwnerUID = try? await firestore.fetchSharedWishlistOwnerUID(wishlistID: wishlist.id.uuidString)
                isOwner = (wireOwnerUID == ownerUID)
                // Заодно self-heal local cache если расходится — не блокирует flow.
                if let wo = wireOwnerUID, wo != wishlist.ownerRecordID {
                    wishlist.ownerRecordID = wo
                }
            }

            shareLog.info("generateShare: wlid=\(wishlist.id.uuidString, privacy: .public) isFirstPublish=\(isFirstPublish, privacy: .public) isOwner=\(isOwner, privacy: .public) myRole=\(wishlist.myRole ?? "nil", privacy: .public) callerUID=\(ownerUID, privacy: .private)")

            // 2. Только при first-time публикации owner'ом пишем shared_wishlists + items + owner membership.
            //    Повторные открытия sheet'а у owner'а не пере-записывают wishlist DOC.
            //    Не-owner НИКОГДА не пишет shared_wishlists / owner membership.
            if isFirstPublish && isOwner {
                let localItems = (wishlist.items ?? []).filter { !$0.isArchived }
                let sharedItems = localItems.map { item in
                    FirestoreService.SharedItemInfo(
                        itemID: item.id.uuidString,
                        name: item.name,
                        tier: item.tier.rawValue,
                        price: item.priceValue,
                        priceMax: item.priceMaxValue,
                        currency: item.currency,
                        url: item.url,
                        coverEmoji: item.coverEmoji,
                        coverImageData: item.coverImageData,
                        linkMetadataData: item.linkMetadataData,
                        descriptionText: item.descriptionText,
                        probationEndAt: item.probationEndAt,
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
                    gradientHue: wishlist.gradientHue,
                    ownerUID: ownerUID,
                    ownerName: ownerName,
                    items: sharedItems,
                    key: key
                )
                try await firestore.joinWishlist(
                    wishlistID: wishlist.id.uuidString,
                    userUID: ownerUID,
                    userName: ownerName ?? "",
                    role: "owner",
                    canInvite: true
                )
            }

            // 3. Resolve ownerName для invite link preview.
            //    - Owner (включая first-publish): использует свой ownerName.
            //    - Non-owner inviter: пытаемся достать имя реального owner'а из Firestore (cosmetic).
            //      Если не получилось — fallback к "Владелец списка".
            let inviteLinkOwnerName: String?
            if isOwner {
                inviteLinkOwnerName = ownerName
            } else {
                // Cosmetic — не критично если не получится. Не блокирует flow.
                if let info = try? await firestore.fetchSharedWishlist(wishlistID: wishlist.id.uuidString, key: key) {
                    inviteLinkOwnerName = info.ownerName
                } else {
                    inviteLinkOwnerName = nil
                }
            }

            let itemCount = (wishlist.items ?? []).filter { !$0.isArchived }.count
            let expiry = ttl.duration.map { Date.now.addingTimeInterval($0) }

            // 4. Always replace invite link (TTL/role/canInvite могут измениться).
            //    Это ЕДИНСТВЕННЫЙ Firestore-write который делает не-owner inviter.
            try? await firestore.deleteInviteLink(shortID: newShortID)
            try await firestore.createInviteLink(
                shortID: newShortID,
                wishlistID: wishlist.id.uuidString,
                wishlistName: wishlist.name,
                wishlistEmoji: wishlist.coverEmoji,
                wishlistCoverImageData: wishlist.coverImageData,
                ownerName: inviteLinkOwnerName,
                role: role.rawValue,
                itemCount: itemCount,
                gradientSeed: wishlist.gradientSeed,
                canInvite: canInvite,
                expiresAt: expiry,
                key: key
            )

            // 5. Build URL with key fragment.
            let keyFragment = EncryptionService.keyFragment(key)
            let userURL = URL(string: "\(Self.linkDomain)/j/\(newShortID)#k=\(keyFragment)")!

            self.shareURL = userURL
            self.expiresAt = expiry
            self.shortID = newShortID
            self.wishlistID = wishlist.id
            self.wishlistRef = wishlist

            // 6. Mark wishlist as shared locally — ТОЛЬКО при first publish owner'ом.
            //    Не-owner НЕ меняет свой myRole/ownerRecordID.
            if isFirstPublish && isOwner {
                wishlist.isShared = true
                wishlist.sharedWishlistID = wishlist.id.uuidString
                wishlist.ownerRecordID = ownerUID
                wishlist.myRole = "owner"
                wishlist.canInvite = true
                wishlist.updatedAt = .now
            }

            // SECURITY: НЕ логируем shareURL — он содержит fragment с AES-ключом (#k=).
            // Только confirmation что share создан + plaintext shortID для debug.
            shareLog.info("share generated: shortID=\(newShortID, privacy: .public)")
        } catch let firestoreError as FirestoreService.FirestoreError {
            shareLog.error("FAILED: \(firestoreError.localizedDescription, privacy: .public)")
            self.error = firestoreError.errorDescription ?? "Ошибка"
        } catch {
            shareLog.error("FAILED: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Wishlist ID to track for cleanup on revoke
    private var wishlistID: UUID?
    private var wishlistRef: Wishlist?

    /// Revoke all share/invite-links и удалить shared_wishlists/<wlid>.
    ///
    /// **WIRE-CHECK:** verifies `shared_wishlists.ownerUID == callerUID` через Firestore GET
    /// перед DELETE. Не доверяем local `wl.myRole` — могло быть отравлено старым owner-flip
    /// багом (до 2026-05-10). Destructive operation требует свежей верификации с источника
    /// истины. Если GET упал → отказ (fail-closed).
    func revokeAll(callerUID: String) async {
        guard let wl = wishlistRef, let wid = wishlistID else {
            error = "Списка нет"
            return
        }
        if wl.isShared {
            let actualOwnerUID = try? await firestore.fetchSharedWishlistOwnerUID(wishlistID: wid.uuidString)
            guard let actual = actualOwnerUID else {
                // GET упал — не можем верифицировать; для destructive operation отказываем.
                error = "Не удалось подтвердить права владельца. Проверьте сеть и попробуйте снова."
                return
            }
            guard actual == callerUID else {
                error = "Только владелец списка может отозвать все приглашения"
                return
            }
        }

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
