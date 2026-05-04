import Foundation
import SwiftData
import CryptoKit
import os.log

private let dsLog = Logger(subsystem: "RUGyron.IWish", category: "DataService")

@Observable
@MainActor
final class DataService {
    let firestore: FirestoreService
    let modelContext: ModelContext
    let auth: AuthService

    var isSyncing: Bool = false
    var syncError: String?
    /// Set to true when refreshItems detects wishlist was deleted remotely
    var wishlistDeleted: Bool = false
    /// Serializes all Firestore operations — no parallel mutations/polls
    private var operationLock = false

    /// Wait for any running operation to finish, then acquire lock
    func acquireLock() async {
        while operationLock {
            try? await Task.sleep(for: .milliseconds(100))
        }
        operationLock = true
    }

    func releaseLock() {
        operationLock = false
    }

    /// Non-blocking: returns false if lock is taken (poll should skip)
    func tryAcquireLock() -> Bool {
        guard !operationLock else { return false }
        operationLock = true
        return true
    }

    /// Public wrappers for external callers (ShareManager)
    func acquireLockPublic() async { await acquireLock() }
    func releaseLockPublic() { releaseLock() }

    init(firestore: FirestoreService, modelContext: ModelContext, auth: AuthService) {
        self.firestore = firestore
        self.modelContext = modelContext
        self.auth = auth
    }

    // MARK: - One-shot Migration

    /// Однократный wipe локального стора + Keychain после перехода на E2E-шифрование.
    /// Старые незашифрованные данные в Firestore будут стёрты сервером, а локальные wishlists
    /// без ключей в Keychain не смогут синхронизироваться, поэтому логика — снести всё локально
    /// при первом запуске новой версии и подтянуть только то, что есть в новом формате.
    func wipeLocalIfNeeded() {
        let migrationKey = "iwish_encrypted_v1_migration_done"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        dsLog.info("wipeLocalIfNeeded: performing one-time wipe for E2E migration")

        if let allWishlists = try? modelContext.fetch(FetchDescriptor<Wishlist>()) {
            for wl in allWishlists { modelContext.delete(wl) }
        }
        if let allItems = try? modelContext.fetch(FetchDescriptor<Item>()) {
            for item in allItems { modelContext.delete(item) }
        }
        try? modelContext.save()

        // Также почистим Keychain — там могли остаться тестовые ключи от предыдущих сборок.
        KeychainService.deleteAll()

        defaults.set(true, forKey: migrationKey)
        dsLog.info("wipeLocalIfNeeded: done")
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

    func createWishlist(name: String, emoji: String?, coverImageData: Data? = nil) async throws -> Wishlist {
        let currentUID = try uid
        let wishlist = Wishlist(
            name: name,
            coverImageData: coverImageData,
            coverEmoji: emoji,
            gradientSeed: 0
        )
        let seed = DefaultCoverGenerator.stableHash(wishlist.id.uuidString)
        wishlist.gradientSeed = seed
        let wishlistID = wishlist.id.uuidString

        await acquireLock()
        isSyncing = true
        syncError = nil
        defer { releaseLock() }

        // 1. Сгенерировать ключ шифрования и сохранить в iCloud Keychain.
        // Если запись в Keychain упала — НЕ создаём документ в Firestore (иначе будет orphan,
        // который никто не сможет расшифровать).
        let key = EncryptionService.generateKey()
        do {
            try KeychainService.save(key: key, for: wishlistID)
        } catch {
            isSyncing = false
            throw error
        }

        do {
            try await firestore.createPersonalWishlist(
                uid: currentUID,
                wishlistID: wishlistID,
                name: name,
                emoji: emoji,
                gradientSeed: seed,
                coverImageData: coverImageData,
                key: key
            )
        } catch {
            // Откатываем Keychain — orphan-ключ без документа тоже не нужен.
            KeychainService.delete(for: wishlistID)
            isSyncing = false
            throw error
        }

        // SwiftData on success
        modelContext.insert(wishlist)
        try? modelContext.save()
        isSyncing = false
        return wishlist
    }

    func updateWishlist(id: String, name: String, emoji: String?, coverImageData: Data? = nil) async throws {
        let currentUID = try uid

        await acquireLock()
        isSyncing = true
        syncError = nil
        defer { releaseLock() }

        // Find local wishlist
        guard let uuid = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        // E2E-ключ берётся по wishlistID. sharedWishlistID == id.uuidString после share, поэтому
        // для shared/personal ключ хранится под одним и тем же account'ом в Keychain.
        guard let key = KeychainService.load(for: id) else {
            isSyncing = false
            throw FirestoreService.FirestoreError.requestFailed("Ключ шифрования не найден")
        }

        do {
            if wishlistIsShared(wishlist), let sharedID = wishlist.sharedWishlistID {
                // Owner-check без обращения к Firestore: используем локально сохранённый ownerRecordID.
                // Если по какой-то причине его нет — fallback на myRole == "owner".
                let isOwner: Bool = {
                    if let owner = wishlist.ownerRecordID { return owner == currentUID }
                    return wishlist.myRole == "owner"
                }()
                guard isOwner else {
                    isSyncing = false
                    throw FirestoreService.FirestoreError.requestFailed("Только владелец может изменить название")
                }
                try await firestore.updateSharedWishlist(
                    wishlistID: sharedID,
                    name: name,
                    emoji: emoji,
                    coverImageData: coverImageData,
                    ownerName: auth.userName,
                    key: key
                )
            } else {
                try await firestore.updatePersonalWishlist(
                    uid: currentUID,
                    wishlistID: id,
                    name: name,
                    emoji: emoji,
                    coverImageData: coverImageData,
                    key: key
                )
            }
        } catch {
            isSyncing = false
            throw error
        }

        wishlist.name = name
        wishlist.coverEmoji = emoji
        wishlist.coverImageData = coverImageData
        wishlist.updatedAt = .now
        try? modelContext.save()
        isSyncing = false
    }

    func deleteWishlist(id: String) async throws {
        let currentUID = try uid

        await acquireLock()
        isSyncing = true
        syncError = nil
        defer {
            releaseLock()
            isSyncing = false
        }

        guard let uuid = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try modelContext.fetch(descriptor).first else {
            throw FirestoreService.FirestoreError.notFound
        }

        // 1. Delete from Firestore FIRST
        if wishlistIsShared(wishlist), let sharedID = wishlist.sharedWishlistID {
            let isOwner = wishlist.ownerRecordID == currentUID || wishlist.ownerRecordID == nil
            dsLog.info("deleteWishlist: shared=\(sharedID), uid=\(currentUID), ownerRecordID=\(wishlist.ownerRecordID ?? "nil"), isOwner=\(isOwner)")
            if isOwner {
                try await firestore.deleteSharedWishlistFull(wishlistID: sharedID)
                // Also delete personal copy that was kept during share
                try? await firestore.deletePersonalWishlist(uid: currentUID, wishlistID: id)
            } else {
                try await firestore.leaveWishlist(wishlistID: sharedID, userUID: currentUID)
            }
        } else {
            try await firestore.deletePersonalWishlist(uid: currentUID, wishlistID: id)
        }

        // 2. Only delete locally AFTER Firestore confirmed
        modelContext.delete(wishlist)
        try? modelContext.save()

        // 3. Удаляем ключ из iCloud Keychain — данные уже удалены в Firestore.
        // Для leaver (не-owner) тоже чистим: ключ больше не нужен на этом Apple ID.
        // Для owner — синхронно с iCloud Keychain удалится со всех его девайсов.
        KeychainService.delete(for: id)
    }

    // MARK: - Archive / Unarchive Wishlist

    func archiveWishlist(id: String) async throws {
        let currentUID = try uid

        await acquireLock()
        isSyncing = true
        syncError = nil
        defer { releaseLock() }

        guard let uuid = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        do {
            if wishlistIsShared(wishlist), let sharedID = wishlist.sharedWishlistID {
                // Archive shared → make private: kick all members, delete invites
                // 1. Delete all memberships except owner.
                //    fetchSharedWishlist теперь требует ключ для расшифровки payload'а.
                //    Если ключа нет — просто пропускаем kick (membership-cleanup произойдёт лениво).
                if let sharedKey = KeychainService.load(for: id),
                   let info = try? await firestore.fetchSharedWishlist(wishlistID: sharedID, key: sharedKey) {
                    for member in info.members where member.userUID != currentUID {
                        try? await firestore.leaveWishlist(wishlistID: sharedID, userUID: member.userUID)
                    }
                }
                // 2. Delete invite links
                await firestore.deleteAllInviteLinks(forWishlistID: sharedID)
                // 3. Archive in Firestore
                try await firestore.archiveSharedWishlist(wishlistID: sharedID, isArchived: true)
            } else {
                try await firestore.archivePersonalWishlist(uid: currentUID, wishlistID: id, isArchived: true)
            }
        } catch {
            isSyncing = false
            throw error
        }

        wishlist.isArchived = true
        wishlist.memberCount = 1
        wishlist.updatedAt = .now
        try? modelContext.save()
        isSyncing = false
    }

    func unarchiveWishlist(id: String) async throws {
        let currentUID = try uid

        await acquireLock()
        isSyncing = true
        syncError = nil
        defer { releaseLock() }

        guard let uuid = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        do {
            if wishlistIsShared(wishlist), let sharedID = wishlist.sharedWishlistID {
                try await firestore.archiveSharedWishlist(wishlistID: sharedID, isArchived: false)
            } else {
                try await firestore.archivePersonalWishlist(uid: currentUID, wishlistID: id, isArchived: false)
            }
        } catch {
            isSyncing = false
            throw error
        }

        wishlist.isArchived = false
        wishlist.updatedAt = .now
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
        guard let wishlist = try modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        // Все items в одном wishlist шифруются одним ключом — берём его по wishlistID (parent).
        guard let key = KeychainService.load(for: wishlistID) else {
            isSyncing = false
            throw FirestoreService.FirestoreError.requestFailed("Ключ шифрования не найден")
        }

        do {
            if wishlistIsShared(wishlist), let sharedID = wishlist.sharedWishlistID {
                try await verifyEditorRole(wishlistID: sharedID)
                try await firestore.createSharedItem(wishlistID: sharedID, itemID: itemID, name: name, tier: tier.rawValue, price: price, currency: currency, url: url, emoji: emoji, sortIndex: sortIndex, key: key)
            } else {
                try await firestore.createPersonalItem(uid: currentUID, wishlistID: wishlistID, itemID: itemID, name: name, tier: tier.rawValue, price: price, currency: currency, url: url, emoji: emoji, sortIndex: sortIndex, key: key)
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

        await acquireLock()
        isSyncing = true
        syncError = nil
        defer { releaseLock() }

        guard let itemUUID = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemUUID })
        guard let item = try modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        let wishlist = item.wishlist
        let isShared = wishlist.map { wishlistIsShared($0) } ?? false
        let sharedID = wishlist?.sharedWishlistID

        // Ключ берётся по wishlistID — все items в одном wishlist шифруются одним ключом.
        guard let key = KeychainService.load(for: wishlistID) else {
            isSyncing = false
            throw FirestoreService.FirestoreError.requestFailed("Ключ шифрования не найден")
        }

        do {
            if isShared, let sharedID {
                try await verifyEditorRole(wishlistID: sharedID)
                try await firestore.updateSharedItem(wishlistID: sharedID, itemID: id, name: name, tier: tier.rawValue, price: price, currency: currency, url: url, emoji: emoji, sortIndex: sortIndex, isArchived: isArchived, key: key)
            } else {
                try await firestore.updatePersonalItem(uid: currentUID, wishlistID: wishlistID, itemID: id, name: name, tier: tier.rawValue, price: price, currency: currency, url: url, emoji: emoji, sortIndex: sortIndex, isArchived: isArchived, key: key)
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

        await acquireLock()
        isSyncing = true
        syncError = nil
        defer { releaseLock() }

        guard let itemUUID = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemUUID })
        guard let item = try modelContext.fetch(descriptor).first else {
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

        await acquireLock()
        isSyncing = true
        syncError = nil
        defer { releaseLock() }

        guard let itemUUID = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemUUID })
        guard let item = try modelContext.fetch(descriptor).first else {
            isSyncing = false
            throw FirestoreService.FirestoreError.notFound
        }

        let wishlist = item.wishlist
        let isShared = wishlist.map { wishlistIsShared($0) } ?? false
        let sharedID = wishlist?.sharedWishlistID

        // Archive — это update isArchived=true, поэтому шифруем содержимое заново тем же ключом.
        guard let key = KeychainService.load(for: wishlistID) else {
            isSyncing = false
            throw FirestoreService.FirestoreError.requestFailed("Ключ шифрования не найден")
        }

        do {
            if isShared, let sharedID {
                try await verifyEditorRole(wishlistID: sharedID)
                try await firestore.updateSharedItem(wishlistID: sharedID, itemID: id, name: item.name, tier: item.tier.rawValue, price: item.price, currency: item.currency, url: item.url, emoji: item.coverEmoji, sortIndex: item.sortIndex, isArchived: true, key: key)
            } else {
                try await firestore.updatePersonalItem(uid: currentUID, wishlistID: wishlistID, itemID: id, name: item.name, tier: item.tier.rawValue, price: item.price, currency: item.currency, url: item.url, emoji: item.coverEmoji, sortIndex: item.sortIndex, isArchived: true, key: key)
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
        guard tryAcquireLock() else { return } // Skip if busy
        defer { releaseLock() }

        isSyncing = true
        syncError = nil

        do {
            // 1. Fetch personal wishlists. Расшифровка происходит внутри fetchPersonalWishlists
            // через keyProvider — wishlists без ключа в Keychain автоматически отбрасываются.
            let keyProvider: (String) -> SymmetricKey? = { wlID in
                KeychainService.load(for: wlID)
            }
            let remote = try await firestore.fetchPersonalWishlists(uid: currentUID, keyProvider: keyProvider)

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
            // Pre-fetch memberships to detect orphaned personal copies
            let membershipsForCheck = try await firestore.fetchMyMemberships(userUID: currentUID)
            let memberWishlistIDs = Set(membershipsForCheck.map(\.wishlistID))

            for r in remote {
                // Skip personal wishlists that are managed as shared (have membership)
                if memberWishlistIDs.contains(r.id) {
                    continue
                }

                if let local = localByID[r.id] {
                    local.name = r.name
                    local.coverEmoji = r.emoji
                    if local.coverImageData == nil, let remoteImage = r.coverImageData {
                        local.coverImageData = remoteImage
                    }
                    local.gradientSeed = r.gradientSeed
                    local.isArchived = r.isArchived
                    local.updatedAt = .now
                    // items в этом wishlist шифруются ключом самого wishlist'а
                    if let itemKey = KeychainService.load(for: r.id) {
                        let personalItems = try await firestore.fetchPersonalItems(uid: currentUID, wishlistID: r.id, key: itemKey)
                        mergeItems(personalItems, into: local)
                    }
                } else {
                    guard let uuid = UUID(uuidString: r.id) else { continue }
                    let newWL = Wishlist(
                        name: r.name,
                        coverImageData: r.coverImageData,
                        coverEmoji: r.emoji,
                        isArchived: r.isArchived,
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
                // Без ключа из Keychain shared wishlist расшифровать нельзя — пропускаем.
                // Обычно ключ был сохранён при acceptInvite (JoinWishlistSheet), либо синкнут из iCloud.
                guard let sharedKey = KeychainService.load(for: membership.wishlistID) else {
                    dsLog.debug("refreshWishlists: no key for shared \(membership.wishlistID, privacy: .public), skipping")
                    continue
                }
                guard let info = try? await firestore.fetchSharedWishlist(wishlistID: membership.wishlistID, key: sharedKey) else {
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
                        if local.coverImageData == nil, let remoteImage = info.coverImageData {
                            local.coverImageData = remoteImage
                        }
                        local.gradientSeed = info.gradientSeed
                        local.isArchived = info.isArchived
                        local.ownerRecordID = info.ownerUID
                        local.myRole = membership.role
                        local.canInvite = membership.canInvite
                        local.memberCount = info.members.count
                        local.isShared = true
                        local.sharedWishlistID = info.wishlistID
                        local.updatedAt = .now
                        // Merge remote items into existing shared wishlist
                        mergeItems(info.items, into: local)
                    } else if let uuid = UUID(uuidString: info.wishlistID) {
                        let newWL = Wishlist(
                            name: info.name,
                            coverImageData: info.coverImageData,
                            coverEmoji: info.coverEmoji,
                            ownerRecordID: info.ownerUID,
                            isShared: true,
                            isArchived: info.isArchived,
                            sharedWishlistID: info.wishlistID,
                            gradientSeed: info.gradientSeed
                        )
                        newWL.myRole = membership.role
                        newWL.canInvite = membership.canInvite
                        newWL.memberCount = info.members.count
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
        guard tryAcquireLock() else { return } // Skip if busy
        defer { releaseLock() }

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

        // Ключ wishlist'а нужен для расшифровки items (одного на всех — wishlist-level key).
        guard let key = KeychainService.load(for: wishlistID) else {
            dsLog.debug("refreshItems: no key for \(wishlistID, privacy: .public), skip")
            isSyncing = false
            return
        }

        do {
            let remoteItems: [FirestoreService.SharedItemInfo]
            if wishlistIsShared(wishlist), let sharedID = wishlist.sharedWishlistID {
                // Verify wishlist still exists (key required for decryption check inside)
                let _ = try await firestore.fetchSharedWishlist(wishlistID: sharedID, key: key)
                // Verify we're still a member (might have been kicked)
                let memberships = try await firestore.fetchMyMemberships(userUID: currentUID)
                if !memberships.contains(where: { $0.wishlistID == sharedID }) {
                    // Kicked — remove local copy
                    modelContext.delete(wishlist)
                    try? modelContext.save()
                    wishlistDeleted = true
                    isSyncing = false
                    return
                }
                remoteItems = try await firestore.fetchSharedWishlistItems(wishlistID: sharedID, key: key)
            } else {
                remoteItems = try await firestore.fetchPersonalItems(uid: currentUID, wishlistID: wishlistID, key: key)
            }

            mergeItems(remoteItems, into: wishlist)
            wishlistDeleted = false
        } catch {
            // If shared wishlist not found — it was deleted remotely
            if wishlistIsShared(wishlist) {
                modelContext.delete(wishlist)
                try? modelContext.save()
                wishlistDeleted = true
            }
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
        for local in localItems {
            if !remoteIDs.contains(local.id.uuidString) {
                modelContext.delete(local)
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

    // MARK: - Share / Accept Invite
    //
    // Legacy `shareWishlist(...)` и `acceptInvite(...)` удалены — UI работает через
    // ShareManager (генерация шары) и JoinWishlistSheet (приём). Дублирование убрано,
    // чтобы не дрейфовать сигнатуры между двумя реализациями.
}
