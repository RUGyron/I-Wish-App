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

    /// Throttle для refreshWishlists — auto-polling не чаще раз в N сек.
    private var lastRefreshWishlistsAt: Date?
    /// Throttle для refreshItems(for:) — per wishlistID.
    private var lastRefreshItemsAt: [String: Date] = [:]

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

    // MARK: - Debug seed (только для подготовки скриншотов в App Store)

    #if DEBUG
    /// Создаёт реалистичный набор тестовых данных: 4 wishlist'а с items.
    /// Идёт через обычные create-методы — генерируются ключи, шифруется payload,
    /// всё видно в Firestore как нормальные encrypted documents.
    func seedMockDataForScreenshots() async {
        let lists: [(name: String, emoji: String, items: [(String, ItemTier, Double?, String, String?)])] = [
            ("День рождения", "🎂", [
                ("Apple Watch Ultra 2", .must, 89_990, "RUB", "https://apple.com/watch-ultra"),
                ("Книга «Атомные привычки»", .must, 890, "RUB", "https://wildberries.ru/book"),
                ("Букет тюльпанов", .maybe, 1_500, "RUB", "https://flowwow.com/tulips"),
                ("Мини-проектор", .idea, 12_990, "RUB", nil),
                ("Подарочная карта Steam", .idea, 3_000, "RUB", nil),
            ]),
            ("Хотелки", "🎁", [
                ("Кофемашина De'Longhi", .must, 89_990, "RUB", "https://wildberries.ru/coffee"),
                ("Кроссовки Nike Pegasus", .maybe, 12_490, "RUB", "https://nike.com/pegasus"),
                ("AirPods Pro 2", .maybe, 24_990, "RUB", "https://apple.com/airpods"),
                ("Стикеры с котиками", .idea, nil, "RUB", nil),
                ("Мини-холодильник", .idea, 7_990, "RUB", nil),
            ]),
            ("Путешествия", "✈️", [
                ("Билеты в Стамбул", .must, 35_000, "RUB", "https://aviasales.ru/istanbul"),
                ("Чемодан Samsonite", .maybe, 25_000, "RUB", "https://samsonite.com"),
                ("Travel-адаптер", .idea, 800, "RUB", nil),
                ("Путеводитель по Азии", .idea, 1_200, "RUB", "https://ozon.ru/guide-asia"),
            ]),
            ("Книги", "📚", [
                ("«Дюна» Фрэнк Герберт", .must, 1_500, "RUB", "https://ozon.ru/dune"),
                ("«Сапиенс» Юваль Харари", .maybe, 1_200, "RUB", nil),
                ("«1984» Оруэлл", .idea, 750, "RUB", nil),
            ]),
        ]

        for (idx, list) in lists.enumerated() {
            do {
                let wl = try await createWishlist(name: list.name, emoji: list.emoji)
                for (i, item) in list.items.enumerated() {
                    let sortIndex = Double((i + 1) * 1000)
                    _ = try await addItem(
                        to: wl.id.uuidString,
                        name: item.0,
                        tier: item.1,
                        price: item.2,
                        currency: item.3,
                        url: item.4,
                        emoji: nil,
                        sortIndex: sortIndex
                    )
                }
                dsLog.info("seed: list #\(idx) '\(list.name, privacy: .public)' done")
            } catch {
                dsLog.error("seed: list '\(list.name, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Удаляет всё локально + чистит Keychain. Firestore docs остаются orphaned (не критично).
    func wipeAllLocal() {
        if let allWishlists = try? modelContext.fetch(FetchDescriptor<Wishlist>()) {
            for wl in allWishlists { modelContext.delete(wl) }
        }
        if let allItems = try? modelContext.fetch(FetchDescriptor<Item>()) {
            for item in allItems { modelContext.delete(item) }
        }
        try? modelContext.save()
        KeychainService.deleteAll()
    }
    #endif

    // MARK: - One-shot Migration

    /// v1.0 миграция на E2E-схему завершена для всех существующих юзеров (v1.0 уже в App Store).
    /// В v1.1 этот метод — no-op: KeychainService.deleteAll() стирал ключи через iCloud Keychain
    /// синхронно на всех устройствах юзера, что приводило к потере доступа к зашифрованным
    /// wishlists в Firestore при reinstall app. Поскольку UserDefaults стирается при удалении
    /// app, флаг сбрасывался → wipe повторно стирал Keychain.
    /// Метод оставлен для обратной совместимости callsite в RootView; ничего не делает.
    func wipeLocalIfNeeded() {
        let v11Key = "iwish_v11_wipe_skip_done"
        guard !UserDefaults.standard.bool(forKey: v11Key) else { return }
        UserDefaults.standard.set(true, forKey: v11Key)
        dsLog.info("wipeLocalIfNeeded: skipped — v1.1 keeps Keychain intact")
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

    func createWishlist(name: String, emoji: String?, coverImageData: Data? = nil, gradientHue: Double? = nil) async throws -> Wishlist {
        let currentUID = try uid

        // Лимит на количество активных (не-архивных) wishlist'ов на юзера.
        // Чек локальный: SwiftData отражает Firestore после refresh.
        let allDescriptor = FetchDescriptor<Wishlist>()
        let allLocal = (try? modelContext.fetch(allDescriptor)) ?? []
        let activeCount = allLocal.filter { !$0.isArchived }.count
        guard activeCount < InputLimits.maxWishlistsPerUser else {
            throw FirestoreService.FirestoreError.requestFailed(
                "Достигнут лимит — \(InputLimits.maxWishlistsPerUser) активных списков. Удалите или архивируйте старые."
            )
        }

        let wishlist = Wishlist(
            name: name,
            coverImageData: coverImageData,
            coverEmoji: emoji,
            gradientSeed: 0,
            gradientHue: gradientHue
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
                gradientHue: gradientHue,
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

    func updateWishlist(id: String, name: String, emoji: String?, coverImageData: Data? = nil, gradientHue: Double? = nil) async throws {
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

        guard let key = KeychainService.load(for: id) else {
            isSyncing = false
            throw FirestoreService.FirestoreError.requestFailed("Ключ шифрования не найден")
        }

        do {
            if wishlistIsShared(wishlist), let sharedID = wishlist.sharedWishlistID {
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
                    gradientHue: gradientHue,
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
                    gradientHue: gradientHue,
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
        if let gradientHue { wishlist.gradientHue = gradientHue }
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

    func addItem(
        to wishlistID: String,
        name: String,
        tier: ItemTier,
        price: Double?,
        priceMax: Double? = nil,
        currency: String,
        url: String?,
        emoji: String?,
        sortIndex: Double,
        descriptionText: String? = nil,
        probationEndAt: Date? = nil,
        coverImageData: Data? = nil,
        linkMetadataData: Data? = nil
    ) async throws -> Item {
        let currentUID = try uid
        // Имя автора фиксируем на момент добавления. bestDisplayName() добирает имя
        // из Keychain → Firebase displayName → email-prefix, чтобы атрибуция работала
        // даже если Apple credential не передал name на повторном sign-in.
        let currentUserName = auth.bestDisplayName()

        let item = Item(
            name: name,
            tier: tier,
            sortIndex: sortIndex,
            currency: currency,
            price: price,
            priceMax: priceMax,
            descriptionText: descriptionText,
            url: url,
            coverImageData: coverImageData,
            coverEmoji: emoji,
            addedByUID: currentUID,
            addedByName: currentUserName
        )
        item.linkMetadataData = linkMetadataData
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

        // Лимит на количество активных items в одном wishlist.
        let activeItemsCount = (wishlist.items ?? []).filter { !$0.isArchived }.count
        guard activeItemsCount < InputLimits.maxItemsPerWishlist else {
            isSyncing = false
            throw FirestoreService.FirestoreError.requestFailed(
                "В списке достигнут лимит — \(InputLimits.maxItemsPerWishlist) желаний. Удалите ненужные."
            )
        }

        // Все items в одном wishlist шифруются одним ключом — берём его по wishlistID (parent).
        guard let key = KeychainService.load(for: wishlistID) else {
            isSyncing = false
            throw FirestoreService.FirestoreError.requestFailed("Ключ шифрования не найден")
        }

        do {
            if wishlistIsShared(wishlist), let sharedID = wishlist.sharedWishlistID {
                try await verifyEditorRole(wishlistID: sharedID)
                try await firestore.createSharedItem(
                    wishlistID: sharedID,
                    itemID: itemID,
                    name: name,
                    tier: tier.rawValue,
                    price: price,
                    priceMax: priceMax,
                    currency: currency,
                    url: url,
                    emoji: emoji,
                    sortIndex: sortIndex,
                    descriptionText: descriptionText,
                    coverImageData: coverImageData,
                    linkMetadataData: linkMetadataData,
                    probationEndAt: probationEndAt,
                    addedByUID: currentUID,
                    addedByName: currentUserName,
                    key: key
                )
            } else {
                try await firestore.createPersonalItem(
                    uid: currentUID,
                    wishlistID: wishlistID,
                    itemID: itemID,
                    name: name,
                    tier: tier.rawValue,
                    price: price,
                    priceMax: priceMax,
                    currency: currency,
                    url: url,
                    emoji: emoji,
                    sortIndex: sortIndex,
                    descriptionText: descriptionText,
                    coverImageData: coverImageData,
                    linkMetadataData: linkMetadataData,
                    probationEndAt: probationEndAt,
                    addedByUID: currentUID,
                    addedByName: currentUserName,
                    key: key
                )
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

    func updateItem(
        id: String,
        wishlistID: String,
        name: String,
        tier: ItemTier,
        price: Double?,
        priceMax: Double? = nil,
        currency: String,
        url: String?,
        emoji: String?,
        sortIndex: Double,
        isArchived: Bool,
        descriptionText: String? = nil,
        coverImageData: Data? = nil,
        linkMetadataData: Data? = nil,
        probationEndAt: Date? = nil
    ) async throws {
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

        guard let key = KeychainService.load(for: wishlistID) else {
            isSyncing = false
            throw FirestoreService.FirestoreError.requestFailed("Ключ шифрования не найден")
        }

        // preserve-unknown-keys паттерн в FirestoreService.updateXxxItem делает GET → merge →
        // re-encrypt, поэтому addedBy* и любые будущие keys сохраняются автоматически. Передаём
        // их явно из локального Item чтобы не зависеть только от remote state.
        let preservedAddedByUID = item.addedByUID
        let preservedAddedByName = item.addedByName

        do {
            if isShared, let sharedID {
                try await verifyEditorRole(wishlistID: sharedID)
                try await firestore.updateSharedItem(
                    wishlistID: sharedID,
                    itemID: id,
                    name: name,
                    tier: tier.rawValue,
                    price: price,
                    priceMax: priceMax,
                    currency: currency,
                    url: url,
                    emoji: emoji,
                    sortIndex: sortIndex,
                    isArchived: isArchived,
                    descriptionText: descriptionText,
                    coverImageData: coverImageData,
                    linkMetadataData: linkMetadataData,
                    probationEndAt: probationEndAt,
                    addedByUID: preservedAddedByUID,
                    addedByName: preservedAddedByName,
                    key: key
                )
            } else {
                try await firestore.updatePersonalItem(
                    uid: currentUID,
                    wishlistID: wishlistID,
                    itemID: id,
                    name: name,
                    tier: tier.rawValue,
                    price: price,
                    priceMax: priceMax,
                    currency: currency,
                    url: url,
                    emoji: emoji,
                    sortIndex: sortIndex,
                    isArchived: isArchived,
                    descriptionText: descriptionText,
                    coverImageData: coverImageData,
                    linkMetadataData: linkMetadataData,
                    probationEndAt: probationEndAt,
                    addedByUID: preservedAddedByUID,
                    addedByName: preservedAddedByName,
                    key: key
                )
            }
        } catch {
            isSyncing = false
            throw error
        }

        item.name = name
        item.tier = tier
        item.priceValue = price
        item.priceMaxValue = priceMax
        item.currency = currency
        item.url = url
        item.coverEmoji = emoji
        item.sortIndex = sortIndex
        item.isArchived = isArchived
        item.descriptionText = descriptionText
        item.coverImageData = coverImageData
        item.linkMetadataData = linkMetadataData
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
                try await firestore.updateSharedItem(
                    wishlistID: sharedID,
                    itemID: id,
                    name: item.name,
                    tier: item.tier.rawValue,
                    price: item.priceValue,
                    priceMax: item.priceMaxValue,
                    currency: item.currency,
                    url: item.url,
                    emoji: item.coverEmoji,
                    sortIndex: item.sortIndex,
                    isArchived: true,
                    descriptionText: item.descriptionText,
                    coverImageData: item.coverImageData,
                    linkMetadataData: item.linkMetadataData,
                    probationEndAt: item.probationEndAt,
                    addedByUID: item.addedByUID,
                    addedByName: item.addedByName,
                    key: key
                )
            } else {
                try await firestore.updatePersonalItem(
                    uid: currentUID,
                    wishlistID: wishlistID,
                    itemID: id,
                    name: item.name,
                    tier: item.tier.rawValue,
                    price: item.priceValue,
                    priceMax: item.priceMaxValue,
                    currency: item.currency,
                    url: item.url,
                    emoji: item.coverEmoji,
                    sortIndex: item.sortIndex,
                    isArchived: true,
                    descriptionText: item.descriptionText,
                    coverImageData: item.coverImageData,
                    linkMetadataData: item.linkMetadataData,
                    probationEndAt: item.probationEndAt,
                    addedByUID: item.addedByUID,
                    addedByName: item.addedByName,
                    key: key
                )
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

        // Throttle: не чаще раз в N сек, иначе быстро вышибаем дневную квоту Firestore.
        if let last = lastRefreshWishlistsAt,
           Date().timeIntervalSince(last) < InputLimits.minWishlistsRefreshInterval {
            return
        }

        guard tryAcquireLock() else { return } // Skip if busy
        defer { releaseLock() }

        lastRefreshWishlistsAt = Date()
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
                    local.gradientHue = r.gradientHue
                    local.isArchived = r.isArchived
                    local.updatedAt = .now
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
                        gradientSeed: r.gradientSeed,
                        gradientHue: r.gradientHue
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
                        local.gradientHue = info.gradientHue
                        local.isArchived = info.isArchived
                        local.ownerRecordID = info.ownerUID
                        local.myRole = membership.role
                        local.canInvite = membership.canInvite
                        local.memberCount = info.members.count
                        local.isShared = true
                        local.sharedWishlistID = info.wishlistID
                        local.updatedAt = .now
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
                            gradientSeed: info.gradientSeed,
                            gradientHue: info.gradientHue
                        )
                        newWL.myRole = membership.role
                        newWL.canInvite = membership.canInvite
                        newWL.memberCount = info.members.count
                        newWL.id = uuid
                        modelContext.insert(newWL)

                        for sharedItem in info.items {
                            let item = Item(
                                name: sharedItem.name,
                                tier: ItemTier(rawValue: sharedItem.tier) ?? .maybe,
                                sortIndex: sharedItem.sortIndex,
                                currency: sharedItem.currency,
                                price: sharedItem.price,
                                priceMax: sharedItem.priceMax,
                                descriptionText: sharedItem.descriptionText,
                                url: sharedItem.url,
                                coverImageData: sharedItem.coverImageData,
                                coverEmoji: sharedItem.coverEmoji,
                                addedByUID: sharedItem.addedByUID,
                                addedByName: sharedItem.addedByName
                            )
                            item.linkMetadataData = sharedItem.linkMetadataData
                            item.probationEndAt = sharedItem.probationEndAt
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

        // Throttle per-wishlist: не чаще раз в N сек.
        if let last = lastRefreshItemsAt[wishlistID],
           Date().timeIntervalSince(last) < InputLimits.minItemsRefreshInterval {
            return
        }

        guard tryAcquireLock() else { return } // Skip if busy
        defer { releaseLock() }

        lastRefreshItemsAt[wishlistID] = Date()
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

        for local in localItems {
            if !remoteIDs.contains(local.id.uuidString) {
                modelContext.delete(local)
            }
        }

        for remote in remoteItems {
            let tier = ItemTier(rawValue: remote.tier) ?? .maybe

            if let local = localByID[remote.itemID] {
                local.name = remote.name
                local.tier = tier
                local.priceValue = remote.price
                local.priceMaxValue = remote.priceMax
                local.currency = remote.currency
                local.url = remote.url
                local.coverEmoji = remote.coverEmoji
                local.sortIndex = remote.sortIndex
                local.isArchived = remote.isArchived
                // Поля у legacy items могут отсутствовать в payload — не затираем local
                // если remote вернулся без значения (старая версия писала payload без них).
                if let uid = remote.addedByUID { local.addedByUID = uid }
                if let nm = remote.addedByName { local.addedByName = nm }
                if let img = remote.coverImageData { local.coverImageData = img }
                if let lm = remote.linkMetadataData { local.linkMetadataData = lm }
                if let desc = remote.descriptionText { local.descriptionText = desc }
                if let prob = remote.probationEndAt { local.probationEndAt = prob }
                local.updatedAt = .now
            } else {
                let item = Item(
                    name: remote.name,
                    tier: tier,
                    sortIndex: remote.sortIndex,
                    currency: remote.currency,
                    price: remote.price,
                    priceMax: remote.priceMax,
                    descriptionText: remote.descriptionText,
                    url: remote.url,
                    coverImageData: remote.coverImageData,
                    coverEmoji: remote.coverEmoji,
                    addedByUID: remote.addedByUID,
                    addedByName: remote.addedByName
                )
                item.linkMetadataData = remote.linkMetadataData
                item.probationEndAt = remote.probationEndAt
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

    // MARK: - Owner: Member role management
    //
    // Permission-модель (CLIENT-SIDE only):
    //  - Только owner shared wishlist'а может менять роли и кикать участников.
    //  - newRole ∈ {"editor", "viewer"} — менять роль на "owner" нельзя.
    //  - Кикнуть самого owner'а нельзя (используйте deleteWishlist).
    //
    // FIXME (security): сейчас Firestore Security Rules не настроены, поэтому проверка
    // owner-а только клиентская. Любой залогиненный юзер с REST-токеном может обойти и
    // PATCH/DELETE membership напрямую. Запланировано: написать Firestore Rules,
    // которые проверяют request.auth.uid == shared_wishlists/{wid}.ownerUID.
    // См. /Users/rugyron/ObsidianVault/projects/iwish/решения/2026-05-04-owner-role-management.md

    /// Owner меняет роль participant'а. Acquires lock, валидирует owner-а через локальный
    /// `wishlist.ownerRecordID`. После успешного PATCH локально обновляет `wishlist.memberCount`
    /// (число не меняется, но триггерит SwiftData update — UI рефрешнётся).
    func changeMemberRole(wishlistID: String, memberUID: String, newRole: String) async throws {
        let currentUID = try uid

        // Whitelist допустимых ролей. "owner" сюда не входит.
        guard newRole == "editor" || newRole == "viewer" else {
            throw FirestoreService.FirestoreError.requestFailed("Недопустимая роль")
        }

        // Найти локальный shared wishlist по sharedWishlistID
        let descriptor = FetchDescriptor<Wishlist>()
        let allLocal = (try? modelContext.fetch(descriptor)) ?? []
        guard let wishlist = allLocal.first(where: { $0.sharedWishlistID == wishlistID }) else {
            throw FirestoreService.FirestoreError.notFound
        }

        // Owner-check: ownerRecordID хранит UID владельца. Если по какой-то причине его нет —
        // fallback на myRole == "owner".
        let isOwner: Bool = {
            if let owner = wishlist.ownerRecordID { return owner == currentUID }
            return wishlist.myRole == "owner"
        }()
        guard isOwner else {
            throw FirestoreService.FirestoreError.requestFailed("Только владелец может изменять роли")
        }

        // Запретить менять роль самому себе через этот метод (нет смысла — owner не может стать viewer).
        guard memberUID != currentUID else {
            throw FirestoreService.FirestoreError.requestFailed("Нельзя изменить собственную роль")
        }

        await acquireLock()
        isSyncing = true
        syncError = nil
        defer { releaseLock() }

        do {
            try await firestore.updateMembershipRole(
                wishlistID: wishlistID,
                userUID: memberUID,
                role: newRole
            )
        } catch {
            isSyncing = false
            throw error
        }

        // Локальный wishlist не хранит список members — только memberCount + myRole для текущего юзера.
        // Поэтому ничего не меняем в SwiftData; ParticipantsView сам перезапросит fetchMembers().
        wishlist.updatedAt = .now
        try? modelContext.save()
        isSyncing = false
    }

    /// Owner кикает participant'а. Acquires lock, валидирует owner-а через локальный
    /// `wishlist.ownerRecordID`, удаляет membership document.
    func kickMember(wishlistID: String, memberUID: String) async throws {
        let currentUID = try uid

        // Найти локальный shared wishlist
        let descriptor = FetchDescriptor<Wishlist>()
        let allLocal = (try? modelContext.fetch(descriptor)) ?? []
        guard let wishlist = allLocal.first(where: { $0.sharedWishlistID == wishlistID }) else {
            throw FirestoreService.FirestoreError.notFound
        }

        // Owner-check
        let isOwner: Bool = {
            if let owner = wishlist.ownerRecordID { return owner == currentUID }
            return wishlist.myRole == "owner"
        }()
        guard isOwner else {
            throw FirestoreService.FirestoreError.requestFailed("Только владелец может удалять участников")
        }

        // Нельзя кикнуть самого owner'а — для удаления списка есть deleteWishlist.
        guard memberUID != currentUID else {
            throw FirestoreService.FirestoreError.requestFailed("Владелец не может удалить себя — удалите список целиком")
        }

        await acquireLock()
        isSyncing = true
        syncError = nil
        defer { releaseLock() }

        do {
            try await firestore.kickMember(wishlistID: wishlistID, userUID: memberUID)
        } catch {
            isSyncing = false
            throw error
        }

        // Декремент memberCount; реальный список members перезапросится из ParticipantsView.
        if wishlist.memberCount > 1 {
            wishlist.memberCount -= 1
        }
        wishlist.updatedAt = .now
        try? modelContext.save()
        isSyncing = false
    }

    // MARK: - v1.1 Migration backfill

    /// One-time backfill при первом старте v1.1: пройти по local items с непустыми
    /// "missing" полями (description/coverImageData/linkMeta/probationEndAt) и переслать
    /// в Firestore чтобы они попали в encryptedPayload. Также backfill memberships userName.
    /// Идемпотентно. Маркер UserDefaults; при partial failure повторим в следующем старте.
    func runV11BackfillIfNeeded() async {
        let backfillKey = "iwish_v11_backfill_done"
        let ownerHealKey = "iwish_v11_owner_heal_done"
        let backfillDone = UserDefaults.standard.bool(forKey: backfillKey)
        let healDone = UserDefaults.standard.bool(forKey: ownerHealKey)
        guard !backfillDone || !healDone else { return }
        guard auth.uid != nil else { return }

        var allOK = true
        let runFullBackfill = !backfillDone

        if runFullBackfill {
            let items = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
            for item in items {
                let needsBackfill = (item.descriptionText?.isEmpty == false)
                    || item.coverImageData != nil
                    || item.linkMetadataData != nil
                    || item.probationEndAt != nil
                guard needsBackfill else { continue }
                guard let wishlist = item.wishlist else { continue }

                do {
                    try await updateItem(
                        id: item.id.uuidString,
                        wishlistID: wishlist.id.uuidString,
                        name: item.name,
                        tier: item.tier,
                        price: item.priceValue,
                        priceMax: item.priceMaxValue,
                        currency: item.currency,
                        url: item.url,
                        emoji: item.coverEmoji,
                        sortIndex: item.sortIndex,
                        isArchived: item.isArchived,
                        descriptionText: item.descriptionText,
                        coverImageData: item.coverImageData,
                        linkMetadataData: item.linkMetadataData,
                        probationEndAt: item.probationEndAt
                    )
                } catch {
                    dsLog.warning("v1.1 backfill: failed for item \(item.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    allOK = false
                }
            }

            // Backfill memberships userName — у меня могут быть memberships без userName.
            if let myUID = auth.uid, let myName = auth.userName, !myName.isEmpty, myName != "Пользователь" {
                do {
                    let memberships = try await firestore.fetchMyMemberships(userUID: myUID)
                    for m in memberships {
                        do {
                            try await firestore.updateMembershipUserName(wishlistID: m.wishlistID, userUID: myUID, userName: myName)
                        } catch {
                            dsLog.warning("v1.1 backfill: membership userName failed: \(error.localizedDescription, privacy: .public)")
                            allOK = false
                        }
                    }
                } catch {
                    dsLog.warning("v1.1 backfill: fetchMyMemberships failed: \(error.localizedDescription, privacy: .public)")
                    allOK = false
                }
            }
        }

        // Backfill ownerName в shared wishlist'ах где я owner — старые версии шифровали
        // в payload буквальное "Пользователь" если не было реального имени.
        // Заодно self-heal: убеждаемся что моя membership.role == "owner" для своих wishlist'ов.
        // Legacy bug v1.0: у некоторых owner'ов membership создавалась с role != "owner",
        // что приводило к isEditable=false и блокировке управления своим же списком.
        if let myUID = auth.uid {
            let allWishlists = (try? modelContext.fetch(FetchDescriptor<Wishlist>())) ?? []
            for wl in allWishlists where wl.isShared && wl.ownerRecordID == myUID {
                guard let sharedID = wl.sharedWishlistID else { continue }

                // 1. Self-heal owner-role: PATCH membership.role="owner" если она другая.
                if wl.myRole != "owner" {
                    do {
                        try await firestore.updateMembershipRole(
                            wishlistID: sharedID,
                            userUID: myUID,
                            role: "owner"
                        )
                        wl.myRole = "owner"
                        wl.canInvite = true
                        dsLog.info("v1.1 self-heal: restored owner role for \(sharedID, privacy: .public)")
                    } catch {
                        dsLog.warning("v1.1 self-heal: owner role for \(sharedID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        allOK = false
                    }
                }

                // 2. Backfill ownerName в encrypted payload.
                if let myName = auth.userName, !myName.isEmpty, myName != "Пользователь",
                   let key = KeychainService.load(for: wl.id.uuidString) {
                    do {
                        try await firestore.updateSharedWishlist(
                            wishlistID: sharedID,
                            name: wl.name,
                            emoji: wl.coverEmoji,
                            coverImageData: wl.coverImageData,
                            gradientHue: wl.gradientHue,
                            ownerName: myName,
                            key: key
                        )
                    } catch {
                        dsLog.warning("v1.1 backfill: ownerName for shared \(sharedID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        allOK = false
                    }
                }
            }
            try? modelContext.save()
        }

        if allOK {
            UserDefaults.standard.set(true, forKey: backfillKey)
            UserDefaults.standard.set(true, forKey: ownerHealKey)
            dsLog.info("v1.1 backfill: completed and marked done")
        } else {
            dsLog.info("v1.1 backfill: partial — will retry on next start")
        }
    }
}
