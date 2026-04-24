import Foundation
import SwiftData

@Observable
@MainActor
final class DataService {
    let firestore: FirestoreService
    let modelContext: ModelContext
    let auth: AuthService

    var isSyncing: Bool = false
    var syncError: String?

    init(firestore: FirestoreService, modelContext: ModelContext, auth: AuthService) {
        self.firestore = firestore
        self.modelContext = modelContext
        self.auth = auth
    }

    private var uid: String {
        get throws {
            guard let uid = auth.uid else {
                throw AuthService.AuthError.notAuthenticated
            }
            return uid
        }
    }

    /// Returns the Firestore collection path depending on whether a wishlist is shared.
    private func wishlistIsShared(_ wishlist: Wishlist) -> Bool {
        wishlist.isShared && wishlist.sharedWishlistID != nil
    }

    /// Verifies that the current user has editor role for a shared wishlist.
    /// Owners always pass. Viewers get an error.
    private func verifyEditorRole(wishlistID: String) async throws {
        let currentUID = try uid
        let memberships = try await firestore.fetchMyMemberships(userUID: currentUID)
        if let membership = memberships.first(where: { $0.wishlistID == wishlistID }) {
            guard membership.role == "editor" || membership.role == "owner" else {
                throw FirestoreService.FirestoreError.requestFailed("Только редактор может изменять список")
            }
        }
        // If no membership found, user is the owner — allow
    }

    // MARK: - Wishlists

    func createWishlist(name: String, emoji: String?) async throws -> Wishlist {
        let currentUID = try uid
        let wishlist = Wishlist(
            name: name,
            coverEmoji: emoji,
            gradientSeed: 0 // will be set below
        )
        let seed = DefaultCoverGenerator.stableHash(wishlist.id.uuidString)
        wishlist.gradientSeed = seed
        let wishlistID = wishlist.id.uuidString

        // Firestore first
        isSyncing = true
        syncError = nil
        do {
            try await firestore.createPersonalWishlist(
                uid: currentUID,
                wishlistID: wishlistID,
                name: name,
                emoji: emoji,
                gradientSeed: seed
            )
        } catch {
            isSyncing = false
            throw error
        }

        // SwiftData on success
        modelContext.insert(wishlist)
        try? modelContext.save()
        isSyncing = false
        return wishlist
    }

    func updateWishlist(id: String, name: String, emoji: String?) async throws {
        let currentUID = try uid

        isSyncing = true
        syncError = nil

        // Find local wishlist
        guard let uuid = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try? modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        do {
            if wishlistIsShared(wishlist), let sharedID = wishlist.sharedWishlistID {
                // Only the owner can rename a shared wishlist
                let info = try await firestore.fetchSharedWishlist(wishlistID: sharedID)
                guard info.ownerUID == currentUID else {
                    isSyncing = false
                    throw FirestoreService.FirestoreError.requestFailed("Только владелец может изменить название")
                }
                try await firestore.updateSharedWishlist(wishlistID: sharedID, name: name, emoji: emoji)
            } else {
                try await firestore.updatePersonalWishlist(uid: currentUID, wishlistID: id, name: name, emoji: emoji)
            }
        } catch {
            isSyncing = false
            throw error
        }

        wishlist.name = name
        wishlist.coverEmoji = emoji
        wishlist.updatedAt = .now
        try? modelContext.save()
        isSyncing = false
    }

    func deleteWishlist(id: String) async throws {
        let currentUID = try uid

        isSyncing = true
        syncError = nil

        guard let uuid = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try? modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        do {
            if wishlistIsShared(wishlist), let sharedID = wishlist.sharedWishlistID {
                // Try to check ownership; if fetch fails (already deleted), just clean up locally
                if let info = try? await firestore.fetchSharedWishlist(wishlistID: sharedID) {
                    if info.ownerUID == currentUID {
                        try await firestore.deleteSharedWishlistFull(wishlistID: sharedID)
                    } else {
                        try await firestore.leaveWishlist(wishlistID: sharedID, userUID: currentUID)
                    }
                } else {
                    // Shared wishlist already gone from Firestore — clean up membership
                    try? await firestore.leaveWishlist(wishlistID: sharedID, userUID: currentUID)
                }
            } else {
                try await firestore.deletePersonalWishlist(uid: currentUID, wishlistID: id)
            }
        } catch {
            print("[DataService] deleteWishlist error: \(error)")
            isSyncing = false
            throw error
        }

        modelContext.delete(wishlist)
        try? modelContext.save()
        isSyncing = false
    }

    // MARK: - Items

    func addItem(to wishlistID: String, name: String, tier: ItemTier, price: Double?, currency: String, url: String?, emoji: String?, sortIndex: Double, descriptionText: String? = nil, probationEndAt: Date? = nil, coverImageData: Data? = nil) async throws -> Item {
        let currentUID = try uid

        let item = Item(
            name: name,
            tier: tier,
            sortIndex: sortIndex,
            currency: currency,
            price: price,
            descriptionText: descriptionText,
            url: url,
            coverImageData: coverImageData,
            coverEmoji: emoji
        )
        if let probationEndAt {
            item.probationEndAt = probationEndAt
        }
        let itemID = item.id.uuidString

        isSyncing = true
        syncError = nil

        // Find the wishlist
        guard let uuid = UUID(uuidString: wishlistID) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try? modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        do {
            if wishlistIsShared(wishlist), let sharedID = wishlist.sharedWishlistID {
                try await verifyEditorRole(wishlistID: sharedID)
                try await firestore.createSharedItem(wishlistID: sharedID, itemID: itemID, name: name, tier: tier.rawValue, price: price, currency: currency, url: url, emoji: emoji, sortIndex: sortIndex)
            } else {
                try await firestore.createPersonalItem(uid: currentUID, wishlistID: wishlistID, itemID: itemID, name: name, tier: tier.rawValue, price: price, currency: currency, url: url, emoji: emoji, sortIndex: sortIndex)
            }
        } catch {
            isSyncing = false
            throw error
        }

        item.wishlist = wishlist
        modelContext.insert(item)
        try? modelContext.save()
        isSyncing = false
        return item
    }

    func updateItem(id: String, wishlistID: String, name: String, tier: ItemTier, price: Double?, currency: String, url: String?, emoji: String?, sortIndex: Double, isArchived: Bool, descriptionText: String? = nil, coverImageData: Data? = nil, probationEndAt: Date? = nil) async throws {
        let currentUID = try uid

        isSyncing = true
        syncError = nil

        guard let itemUUID = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemUUID })
        guard let item = try? modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        let wishlist = item.wishlist
        let isShared = wishlist.map { wishlistIsShared($0) } ?? false
        let sharedID = wishlist?.sharedWishlistID

        do {
            if isShared, let sharedID {
                try await verifyEditorRole(wishlistID: sharedID)
                try await firestore.updateSharedItem(wishlistID: sharedID, itemID: id, name: name, tier: tier.rawValue, price: price, currency: currency, url: url, emoji: emoji, sortIndex: sortIndex, isArchived: isArchived)
            } else {
                try await firestore.updatePersonalItem(uid: currentUID, wishlistID: wishlistID, itemID: id, name: name, tier: tier.rawValue, price: price, currency: currency, url: url, emoji: emoji, sortIndex: sortIndex, isArchived: isArchived)
            }
        } catch {
            isSyncing = false
            throw error
        }

        item.name = name
        item.tier = tier
        item.price = price
        item.currency = currency
        item.url = url
        item.coverEmoji = emoji
        item.sortIndex = sortIndex
        item.isArchived = isArchived
        item.descriptionText = descriptionText
        item.coverImageData = coverImageData
        item.probationEndAt = probationEndAt
        item.updatedAt = .now
        try? modelContext.save()
        isSyncing = false
    }

    func deleteItem(id: String, wishlistID: String) async throws {
        let currentUID = try uid

        isSyncing = true
        syncError = nil

        guard let itemUUID = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemUUID })
        guard let item = try? modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        let wishlist = item.wishlist
        let isShared = wishlist.map { wishlistIsShared($0) } ?? false
        let sharedID = wishlist?.sharedWishlistID

        do {
            if isShared, let sharedID {
                try await verifyEditorRole(wishlistID: sharedID)
                try await firestore.deleteSharedItem(wishlistID: sharedID, itemID: id)
            } else {
                try await firestore.deletePersonalItem(uid: currentUID, wishlistID: wishlistID, itemID: id)
            }
        } catch {
            isSyncing = false
            throw error
        }

        modelContext.delete(item)
        try? modelContext.save()
        isSyncing = false
    }

    func archiveItem(id: String, wishlistID: String) async throws {
        let currentUID = try uid

        isSyncing = true
        syncError = nil

        guard let itemUUID = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemUUID })
        guard let item = try? modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        let wishlist = item.wishlist
        let isShared = wishlist.map { wishlistIsShared($0) } ?? false
        let sharedID = wishlist?.sharedWishlistID

        do {
            if isShared, let sharedID {
                try await verifyEditorRole(wishlistID: sharedID)
                try await firestore.updateSharedItem(wishlistID: sharedID, itemID: id, name: item.name, tier: item.tier.rawValue, price: item.price, currency: item.currency, url: item.url, emoji: item.coverEmoji, sortIndex: item.sortIndex, isArchived: true)
            } else {
                try await firestore.updatePersonalItem(uid: currentUID, wishlistID: wishlistID, itemID: id, name: item.name, tier: item.tier.rawValue, price: item.price, currency: item.currency, url: item.url, emoji: item.coverEmoji, sortIndex: item.sortIndex, isArchived: true)
            }
        } catch {
            isSyncing = false
            throw error
        }

        item.isArchived = true
        item.updatedAt = .now
        try? modelContext.save()
        isSyncing = false
    }

    // MARK: - Sync

    func refreshWishlists() async {
        guard let currentUID = auth.uid else { return }

        isSyncing = true
        syncError = nil

        do {
            // 1. Fetch personal wishlists
            let remote = try await firestore.fetchPersonalWishlists(uid: currentUID)

            // 2. Fetch all local wishlists
            let localDescriptor = FetchDescriptor<Wishlist>()
            let allLocal = (try? modelContext.fetch(localDescriptor)) ?? []
            let localByID = Dictionary(allLocal.compactMap { wl -> (String, Wishlist)? in
                (wl.id.uuidString, wl)
            }, uniquingKeysWith: { _, new in new })

            let remoteIDs = Set(remote.map(\.id))

            // 3. Delete local wishlists not in remote (only personal, non-shared)
            let localPersonal = allLocal.filter { !$0.isShared }
            for local in localPersonal {
                if !remoteIDs.contains(local.id.uuidString) {
                    modelContext.delete(local)
                }
            }

            // 4. Add new or update existing
            for r in remote {
                if let local = localByID[r.id] {
                    local.name = r.name
                    local.coverEmoji = r.emoji
                    local.gradientSeed = r.gradientSeed
                    local.updatedAt = .now
                } else {
                    guard let uuid = UUID(uuidString: r.id) else { continue }
                    let newWL = Wishlist(
                        name: r.name,
                        coverEmoji: r.emoji,
                        gradientSeed: r.gradientSeed
                    )
                    newWL.id = uuid
                    modelContext.insert(newWL)
                }
            }

            // 5. Also fetch shared wishlists via memberships
            let memberships = try await firestore.fetchMyMemberships(userUID: currentUID)

            // Build a set of sharedWishlistIDs already present locally to prevent duplicates
            let allLocalRefreshed = (try? modelContext.fetch(FetchDescriptor<Wishlist>())) ?? []

            // Deduplicate: if multiple local wishlists share the same sharedWishlistID, keep one and delete the rest
            var localBySharedID: [String: Wishlist] = [:]
            for wl in allLocalRefreshed {
                guard let sid = wl.sharedWishlistID else { continue }
                if let existing = localBySharedID[sid] {
                    // Duplicate — delete the older one
                    if wl.updatedAt > existing.updatedAt {
                        modelContext.delete(existing)
                        localBySharedID[sid] = wl
                    } else {
                        modelContext.delete(wl)
                    }
                } else {
                    localBySharedID[sid] = wl
                }
            }

            // 5a. Delete shared wishlists not in memberships
            let remoteMembershipIDs = Set(memberships.map(\.wishlistID))
            let localShared = allLocalRefreshed.filter { $0.isShared }
            for local in localShared {
                if let sid = local.sharedWishlistID, !remoteMembershipIDs.contains(sid) {
                    modelContext.delete(local)
                }
            }

            for membership in memberships {
                guard let info = try? await firestore.fetchSharedWishlist(wishlistID: membership.wishlistID) else {
                    // Shared wishlist deleted — clean up stale membership
                    try? await firestore.leaveWishlist(wishlistID: membership.wishlistID, userUID: currentUID)
                    // Delete local copy if exists
                    if let local = localBySharedID[membership.wishlistID] {
                        modelContext.delete(local)
                    }
                    continue
                }
                if true {
                    // Re-fetch local list after deletions
                    let currentLocal = (try? modelContext.fetch(FetchDescriptor<Wishlist>())) ?? []
                    let currentBySharedID = Dictionary(currentLocal.compactMap { wl -> (String, Wishlist)? in
                        guard let sid = wl.sharedWishlistID else { return nil }
                        return (sid, wl)
                    }, uniquingKeysWith: { _, new in new })
                    if let local = currentBySharedID[info.wishlistID] {
                        local.name = info.name
                        local.coverEmoji = info.coverEmoji
                        local.gradientSeed = info.gradientSeed
                        local.isShared = true
                        local.sharedWishlistID = info.wishlistID
                        local.updatedAt = .now
                    } else if let uuid = UUID(uuidString: info.wishlistID) {
                        let newWL = Wishlist(
                            name: info.name,
                            coverEmoji: info.coverEmoji,
                            isShared: true,
                            sharedWishlistID: info.wishlistID,
                            gradientSeed: info.gradientSeed
                        )
                        newWL.id = uuid
                        modelContext.insert(newWL)

                        // Also insert items
                        for sharedItem in info.items {
                            let item = Item(
                                name: sharedItem.name,
                                tier: ItemTier(rawValue: sharedItem.tier) ?? .maybe,
                                sortIndex: sharedItem.sortIndex,
                                currency: sharedItem.currency,
                                price: sharedItem.price,
                                url: sharedItem.url,
                                coverEmoji: sharedItem.coverEmoji
                            )
                            item.isArchived = sharedItem.isArchived
                            item.wishlist = newWL
                            if let itemUUID = UUID(uuidString: sharedItem.itemID) {
                                item.id = itemUUID
                            }
                            modelContext.insert(item)
                        }
                    }
                }
            }

            try? modelContext.save()
        } catch {
            syncError = error.localizedDescription
            print("[DataService] refreshWishlists error: \(error)")
        }

        isSyncing = false
    }

    func refreshItems(for wishlistID: String) async {
        guard let currentUID = auth.uid else { return }

        isSyncing = true
        syncError = nil

        guard let uuid = UUID(uuidString: wishlistID) else {
            isSyncing = false
            return
        }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try? modelContext.fetch(descriptor).first else {
            isSyncing = false
            return
        }

        do {
            let remoteItems: [FirestoreService.SharedItemInfo]
            if wishlistIsShared(wishlist), let sharedID = wishlist.sharedWishlistID {
                remoteItems = try await firestore.fetchSharedWishlistItems(wishlistID: sharedID)
            } else {
                remoteItems = try await firestore.fetchPersonalItems(uid: currentUID, wishlistID: wishlistID)
            }

            mergeItems(remoteItems, into: wishlist)
        } catch {
            syncError = error.localizedDescription
            print("[DataService] refreshItems error: \(error)")
        }

        isSyncing = false
    }

    private func mergeItems(_ remoteItems: [FirestoreService.SharedItemInfo], into wishlist: Wishlist) {
        let localItems = wishlist.items ?? []
        let localByID = Dictionary(localItems.compactMap { item -> (String, Item)? in
            (item.id.uuidString, item)
        }, uniquingKeysWith: { _, new in new })
        let remoteIDs = Set(remoteItems.map(\.itemID))

        // Delete items that no longer exist remotely
        // Safety: if remote returned empty but local has items, assume network issue and skip deletion
        if !remoteItems.isEmpty || localItems.isEmpty {
            for local in localItems {
                if !remoteIDs.contains(local.id.uuidString) {
                    modelContext.delete(local)
                }
            }
        }

        // Add new or update changed items
        for remote in remoteItems {
            let tier = ItemTier(rawValue: remote.tier) ?? .maybe

            if let local = localByID[remote.itemID] {
                local.name = remote.name
                local.tier = tier
                local.price = remote.price
                local.currency = remote.currency
                local.url = remote.url
                local.coverEmoji = remote.coverEmoji
                local.sortIndex = remote.sortIndex
                local.isArchived = remote.isArchived
                local.updatedAt = .now
            } else {
                let item = Item(
                    name: remote.name,
                    tier: tier,
                    sortIndex: remote.sortIndex,
                    currency: remote.currency,
                    price: remote.price,
                    url: remote.url,
                    coverEmoji: remote.coverEmoji
                )
                item.isArchived = remote.isArchived
                item.wishlist = wishlist
                if let itemUUID = UUID(uuidString: remote.itemID) {
                    item.id = itemUUID
                }
                modelContext.insert(item)
            }
        }

        try? modelContext.save()
    }

    // MARK: - Share

    func shareWishlist(id: String, role: ShareRole, ttl: InviteTTL, ownerName: String?) async throws -> URL {
        let currentUID = try uid

        isSyncing = true
        syncError = nil

        guard let uuid = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try? modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        do {
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

            // 1. Copy to shared_wishlists
            try await firestore.createSharedWishlist(
                wishlistID: id,
                name: wishlist.name,
                emoji: wishlist.coverEmoji,
                gradientSeed: wishlist.gradientSeed,
                ownerUID: currentUID,
                ownerName: ownerName,
                items: sharedItems
            )

            // 2. Create invite link
            let shortID = String(
                id.replacingOccurrences(of: "-", with: "")
                    .prefix(12)
                    .lowercased()
            )
            // Delete existing invite first
            try? await firestore.deleteInviteLink(shortID: shortID)

            let expiry = ttl.duration.map { Date.now.addingTimeInterval($0) }
            try await firestore.createInviteLink(
                shortID: shortID,
                wishlistID: id,
                wishlistName: wishlist.name,
                wishlistEmoji: wishlist.coverEmoji,
                ownerName: ownerName,
                role: role.rawValue,
                itemCount: localItems.count,
                gradientSeed: wishlist.gradientSeed,
                expiresAt: expiry
            )

            // 3. Create owner membership
            try await firestore.joinWishlist(wishlistID: id, userUID: currentUID, role: "owner")

            // 4. Delete from personal collection
            try? await firestore.deletePersonalWishlist(uid: currentUID, wishlistID: id)

            // 5. Update local SwiftData
            wishlist.isShared = true
            wishlist.sharedWishlistID = id
            wishlist.updatedAt = .now
            try? modelContext.save()

            let url = URL(string: "https://rugyron.github.io/I-Wish-App/j/\(shortID)")!
            isSyncing = false
            return url
        } catch {
            isSyncing = false
            throw error
        }
    }

    // MARK: - Accept Invite

    func acceptInvite(shortID: String) async throws -> String {
        guard let currentUID = auth.uid else {
            throw AuthService.AuthError.notAuthenticated
        }

        isSyncing = true
        syncError = nil

        do {
            // 1. Resolve invite link
            guard let info = try await firestore.resolveInviteLink(shortID: shortID) else {
                isSyncing = false
                throw FirestoreService.FirestoreError.notFound
            }

            // 2. Create membership
            try await firestore.joinWishlist(wishlistID: info.wishlistID, userUID: currentUID, role: info.role)

            // 3. Fetch shared wishlist + items
            let sharedData = try await firestore.fetchSharedWishlist(wishlistID: info.wishlistID)

            // 4. Create local copy in SwiftData
            let wishlist = Wishlist(
                name: sharedData.name,
                coverEmoji: sharedData.coverEmoji,
                isShared: true,
                sharedWishlistID: info.wishlistID,
                gradientSeed: sharedData.gradientSeed
            )
            if let uuid = UUID(uuidString: info.wishlistID) {
                wishlist.id = uuid
            }
            modelContext.insert(wishlist)

            for sharedItem in sharedData.items {
                let item = Item(
                    name: sharedItem.name,
                    tier: ItemTier(rawValue: sharedItem.tier) ?? .maybe,
                    sortIndex: sharedItem.sortIndex,
                    currency: sharedItem.currency,
                    price: sharedItem.price,
                    url: sharedItem.url,
                    coverEmoji: sharedItem.coverEmoji
                )
                item.isArchived = sharedItem.isArchived
                item.wishlist = wishlist
                if let itemUUID = UUID(uuidString: sharedItem.itemID) {
                    item.id = itemUUID
                }
                modelContext.insert(item)
            }

            try? modelContext.save()
            isSyncing = false
            return info.wishlistID
        } catch {
            isSyncing = false
            throw error
        }
    }
}
