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
    let sync: SyncEngine

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

    init(firestore: FirestoreService, modelContext: ModelContext, auth: AuthService, sync: SyncEngine) {
        self.firestore = firestore
        self.modelContext = modelContext
        self.auth = auth
        self.sync = sync
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
                throw FirestoreService.FirestoreError.requestFailed(statusCode: 0, body: String(localized: "Only an editor can modify the list"))
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
                statusCode: 0,
                body: String(format: String(localized: "Limit reached — %lld active lists. Delete or archive older ones."), InputLimits.maxWishlistsPerUser)
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

    /// Offline-first update: применяем изменения локально (optimistic), затем enqueue в SyncEngine.
    /// На validation errors (нет ключа / not owner / not found) throws; на network — нет, op уйдёт в очередь.
    func updateWishlist(id: String, name: String, emoji: String?, coverImageData: Data? = nil, gradientHue: Double? = nil) async throws {
        _ = try uid  // ensure authenticated
        guard let uuid = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try modelContext.fetch(descriptor).first else {
            throw FirestoreService.FirestoreError.notFound
        }

        // Capability check — editor ИЛИ owner для shared wishlists. Зеркалит Wishlist.isEditable
        // и UI-гейт в WishlistDetailView ("Edit list" виден editor'у). Раньше тут был owner-only
        // guard → sheet открывался, но Save падал у редактора (баг #1 от Влада). Проверка
        // локальная по myRole — offline-first, без сетевого запроса. Управление членством остаётся
        // owner-only (changeMemberRole/changeMemberCanInvite/kickMember имеют свой isOwner-guard — не трогаем).
        if wishlistIsShared(wishlist), wishlist.sharedWishlistID != nil {
            let canEdit: Bool = {
                guard let role = wishlist.myRole else { return true } // legacy / pending sync
                return role == "owner" || role == "editor"
            }()
            guard canEdit else {
                throw FirestoreService.FirestoreError.requestFailed(statusCode: 0, body: String(localized: "Only an editor can modify the list"))
            }
        }

        // Проверка наличия ключа — без него SyncEngine не сможет зашифровать на пуше.
        guard KeychainService.load(for: id) != nil else {
            throw FirestoreService.FirestoreError.requestFailed(statusCode: 0, body: String(localized: "Encryption key not found"))
        }

        let now = Date()
        var touched: [String] = []

        // 1. Apply changes to local SwiftData (optimistic) + touch field timestamps.
        if wishlist.name != name { wishlist.name = name; touched.append("name") }
        if wishlist.coverEmoji != emoji { wishlist.coverEmoji = emoji; touched.append("coverEmoji") }
        if wishlist.coverImageData != coverImageData { wishlist.coverImageData = coverImageData; touched.append("coverImageData") }
        if let gradientHue, wishlist.gradientHue != gradientHue { wishlist.gradientHue = gradientHue; touched.append("gradientHue") }
        wishlist.updatedAt = now
        wishlist.fieldTimestampsJSON = FieldTimestamps.touch(wishlist.fieldTimestampsJSON, fields: touched, at: now)
        try? modelContext.save()

        guard !touched.isEmpty else { return }  // nothing to push

        // 2. Build payload + enqueue.
        var fields: [String: Any] = [:]
        if touched.contains("name") { fields["name"] = name }
        if touched.contains("coverEmoji") { fields["coverEmoji"] = emoji ?? NSNull() }
        if touched.contains("coverImageData") { fields["coverImageData"] = coverImageData ?? NSNull() }
        if touched.contains("gradientHue") { fields["gradientHue"] = gradientHue as Any }

        var timestamps: [String: Date] = [:]
        for f in touched { timestamps[f] = now }

        let sharedID = wishlistIsShared(wishlist) ? wishlist.sharedWishlistID : nil
        let payload = SyncPayload.encode(fields: fields, timestamps: timestamps, sharedID: sharedID)
        sync.enqueue(PendingOperation(
            entityType: "wishlist",
            entityID: id,
            operationType: "update",
            payloadJSON: payload
        ))
    }

    /// Offline-first soft-delete: помечаем wishlist isDeleted=true локально, enqueue в SyncEngine.
    /// Реальное удаление из Firestore (или leaveWishlist для не-owner'а) делается асинхронно.
    /// Local SwiftData запись остаётся — UI фильтрует по isDeleted; CF cleanup через 30 дней.
    func deleteWishlist(id: String) async throws {
        _ = try uid  // ensure auth
        guard let uuid = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try modelContext.fetch(descriptor).first else {
            throw FirestoreService.FirestoreError.notFound
        }

        let now = Date()

        // 1. Local soft-delete (optimistic). UI скрывает по isDeleted.
        wishlist.isTombstoned = true
        wishlist.deletedAt = now
        wishlist.updatedAt = now
        wishlist.fieldTimestampsJSON = FieldTimestamps.touch(wishlist.fieldTimestampsJSON, fields: ["isDeleted"], at: now)
        try? modelContext.save()

        // 2. Enqueue delete для server-side cleanup.
        let sharedID = wishlistIsShared(wishlist) ? wishlist.sharedWishlistID : nil
        let payload = SyncPayload.encode(
            fields: ["deletedAt": now],
            timestamps: ["isDeleted": now],
            sharedID: sharedID
        )
        sync.enqueue(PendingOperation(
            entityType: "wishlist",
            entityID: id,
            operationType: "delete",
            payloadJSON: payload
        ))
    }

    // MARK: - Archive / Unarchive Wishlist

    /// Offline-first archive: ставит isArchived=true локально, enqueue в SyncEngine.
    /// Для shared wishlist архивирование в server-side также делает kick всех участников и
    /// удаление invites — это runs внутри SyncEngine при flush'е (через syncWishlistArchive).
    func archiveWishlist(id: String) async throws {
        _ = try uid
        guard let uuid = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try modelContext.fetch(descriptor).first else {
            throw FirestoreService.FirestoreError.notFound
        }

        let now = Date()

        // 1. Local optimistic update.
        wishlist.isArchived = true
        wishlist.memberCount = 1
        wishlist.updatedAt = now
        wishlist.fieldTimestampsJSON = FieldTimestamps.touch(wishlist.fieldTimestampsJSON, fields: ["isArchived"], at: now)
        try? modelContext.save()

        // 2. Enqueue archive op.
        let sharedID = wishlistIsShared(wishlist) ? wishlist.sharedWishlistID : nil
        let payload = SyncPayload.encode(
            fields: ["isArchived": true],
            timestamps: ["isArchived": now],
            sharedID: sharedID
        )
        sync.enqueue(PendingOperation(
            entityType: "wishlist",
            entityID: id,
            operationType: "archive",
            payloadJSON: payload
        ))
    }

    func unarchiveWishlist(id: String) async throws {
        _ = try uid
        guard let uuid = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try modelContext.fetch(descriptor).first else {
            throw FirestoreService.FirestoreError.notFound
        }

        let now = Date()

        wishlist.isArchived = false
        wishlist.updatedAt = now
        wishlist.fieldTimestampsJSON = FieldTimestamps.touch(wishlist.fieldTimestampsJSON, fields: ["isArchived"], at: now)
        try? modelContext.save()

        let sharedID = wishlistIsShared(wishlist) ? wishlist.sharedWishlistID : nil
        let payload = SyncPayload.encode(
            fields: ["isArchived": false],
            timestamps: ["isArchived": now],
            sharedID: sharedID
        )
        sync.enqueue(PendingOperation(
            entityType: "wishlist",
            entityID: id,
            operationType: "unarchive",
            payloadJSON: payload
        ))
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
        linkMetadataData: Data? = nil,
        gradientHue: Double? = nil
    ) async throws -> Item {
        let currentUID = try uid
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
            gradientHue: gradientHue,
            addedByUID: currentUID,
            addedByName: currentUserName
        )
        item.linkMetadataData = linkMetadataData
        if let probationEndAt { item.probationEndAt = probationEndAt }
        let itemID = item.id.uuidString

        guard let uuid = UUID(uuidString: wishlistID) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try modelContext.fetch(descriptor).first else {
            throw FirestoreService.FirestoreError.notFound
        }

        let activeItemsCount = (wishlist.items ?? []).filter { !$0.isArchived && !$0.isTombstoned }.count
        guard activeItemsCount < InputLimits.maxItemsPerWishlist else {
            throw FirestoreService.FirestoreError.requestFailed(
                statusCode: 0,
                body: String(format: String(localized: "Limit reached in this list — %lld wishes. Delete unused ones."), InputLimits.maxItemsPerWishlist)
            )
        }

        guard KeychainService.load(for: wishlistID) != nil else {
            throw FirestoreService.FirestoreError.requestFailed(statusCode: 0, body: String(localized: "Encryption key not found"))
        }

        let now = Date()
        let touched = ["name", "tierRaw", "priceValue", "priceMaxValue", "currency", "url", "coverEmoji", "coverImageData", "descriptionText", "linkMeta", "probationEndAt", "gradientHue", "addedByUID", "addedByName", "sortIndex"]
        item.fieldTimestampsJSON = FieldTimestamps.touch(item.fieldTimestampsJSON, fields: touched, at: now)

        item.wishlist = wishlist
        modelContext.insert(item)
        try? modelContext.save()

        // Build payload со всеми полями для server create.
        var fields: [String: Any] = [
            "name": name,
            "tier": tier.rawValue,
            "currency": currency,
            "sortIndex": sortIndex,
            "isArchived": false
        ]
        if let price { fields["price"] = price }
        if let priceMax { fields["priceMax"] = priceMax }
        if let url { fields["url"] = url }
        if let emoji { fields["coverEmoji"] = emoji }
        if let descriptionText { fields["description"] = descriptionText }
        if let coverImageData { fields["coverImageData"] = coverImageData }
        if let linkMetadataData { fields["linkMeta"] = linkMetadataData }
        if let probationEndAt { fields["probationEndAt"] = probationEndAt }
        if let gradientHue { fields["gradientHue"] = gradientHue }
        fields["addedByUID"] = currentUID
        if let n = currentUserName { fields["addedByName"] = n }

        var timestamps: [String: Date] = [:]
        for f in touched { timestamps[f] = now }

        let sharedID = wishlistIsShared(wishlist) ? wishlist.sharedWishlistID : nil
        let payload = SyncPayload.encode(
            fields: fields,
            timestamps: timestamps,
            parentID: wishlistID,
            sharedID: sharedID
        )
        sync.enqueue(PendingOperation(
            entityType: "item",
            entityID: itemID,
            operationType: "create",
            payloadJSON: payload
        ))

        return item
    }

    /// Offline-first item update: применяем изменения локально (optimistic), enqueue в SyncEngine.
    /// Поле-by-поле сравниваем с текущим Item — пушим только touched fields.
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
        probationEndAt: Date? = nil,
        gradientHue: Double? = nil
    ) async throws {
        let currentUID = try uid
        guard let itemUUID = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemUUID })
        guard let item = try modelContext.fetch(descriptor).first else {
            throw FirestoreService.FirestoreError.notFound
        }

        let wishlist = item.wishlist
        let isShared = wishlist.map { wishlistIsShared($0) } ?? false
        let sharedID = wishlist?.sharedWishlistID

        // Без ключа SyncEngine не сможет зашифровать на пуше.
        guard KeychainService.load(for: wishlistID) != nil else {
            throw FirestoreService.FirestoreError.requestFailed(statusCode: 0, body: String(localized: "Encryption key not found"))
        }

        let now = Date()
        var touched: [String] = []

        // 1. Per-field diff + apply optimistically.
        if item.name != name { item.name = name; touched.append("name") }
        if item.tier != tier { item.tier = tier; touched.append("tierRaw") }
        if item.priceValue != price { item.priceValue = price; touched.append("priceValue") }
        if item.priceMaxValue != priceMax { item.priceMaxValue = priceMax; touched.append("priceMaxValue") }
        if item.currency != currency { item.currency = currency; touched.append("currency") }
        if item.url != url { item.url = url; touched.append("url") }
        if item.coverEmoji != emoji { item.coverEmoji = emoji; touched.append("coverEmoji") }
        if item.sortIndex != sortIndex { item.sortIndex = sortIndex; touched.append("sortIndex") }
        if item.isArchived != isArchived { item.isArchived = isArchived; touched.append("isArchived") }
        if item.descriptionText != descriptionText { item.descriptionText = descriptionText; touched.append("descriptionText") }
        if item.coverImageData != coverImageData { item.coverImageData = coverImageData; touched.append("coverImageData") }
        // Имя поля в payload — "linkMeta" (как в createItem и в FirestoreService при чтении).
        // Раньше здесь было "linkMetadataData", которое никто не читает → правка меты не доезжала.
        if item.linkMetadataData != linkMetadataData { item.linkMetadataData = linkMetadataData; touched.append("linkMeta") }
        if item.probationEndAt != probationEndAt { item.probationEndAt = probationEndAt; touched.append("probationEndAt") }
        if item.gradientHue != gradientHue { item.gradientHue = gradientHue; touched.append("gradientHue") }
        item.updatedAt = now
        item.fieldTimestampsJSON = FieldTimestamps.touch(item.fieldTimestampsJSON, fields: touched, at: now)
        try? modelContext.save()

        guard !touched.isEmpty else { return }

        // 2. Build payload — мапим имена локальных полей в имена payload-полей, которые ждёт FirestoreService.
        var fields: [String: Any] = [:]
        if touched.contains("name") { fields["name"] = name }
        if touched.contains("tierRaw") { fields["tier"] = tier.rawValue }
        if touched.contains("priceValue") { fields["price"] = price as Any }
        if touched.contains("priceMaxValue") { fields["priceMax"] = priceMax as Any }
        if touched.contains("currency") { fields["currency"] = currency }
        if touched.contains("url") { fields["url"] = url as Any }
        if touched.contains("coverEmoji") { fields["coverEmoji"] = emoji as Any }
        if touched.contains("sortIndex") { fields["sortIndex"] = sortIndex }
        if touched.contains("isArchived") { fields["isArchived"] = isArchived }
        if touched.contains("descriptionText") { fields["descriptionText"] = descriptionText as Any }
        if touched.contains("coverImageData") { fields["coverImageData"] = coverImageData as Any }
        if touched.contains("linkMeta") { fields["linkMeta"] = linkMetadataData as Any }
        if touched.contains("probationEndAt") { fields["probationEndAt"] = probationEndAt as Any }
        if touched.contains("gradientHue") { fields["gradientHue"] = gradientHue as Any }
        // Author всегда пушим — auto-heal addedBy* при первом offline edit'е (raw payload merge сохранит).
        fields["lastModifiedByUID"] = currentUID

        var timestamps: [String: Date] = [:]
        for f in touched { timestamps[f] = now }

        let payload = SyncPayload.encode(
            fields: fields,
            timestamps: timestamps,
            parentID: wishlistID,
            sharedID: isShared ? sharedID : nil
        )
        sync.enqueue(PendingOperation(
            entityType: "item",
            entityID: id,
            operationType: "update",
            payloadJSON: payload
        ))
    }

    /// Bulk reorder — один lock, один isSyncing toggle. Каждый item PATCH'ит только sortIndex
    /// (через updateMask) — encrypted payload не трогаем, ускоряет 5-10×.
    func reorderItemsBulk(wishlistID: String, items: [Item]) async throws {
        guard !items.isEmpty else { return }
        let currentUID = try uid

        await acquireLock()
        isSyncing = true
        syncError = nil
        defer { releaseLock(); isSyncing = false }

        guard let uuid = UUID(uuidString: wishlistID) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Wishlist>(predicate: #Predicate { $0.id == uuid })
        guard let wishlist = try modelContext.fetch(descriptor).first else {
            throw FirestoreService.FirestoreError.notFound
        }

        let isShared = wishlistIsShared(wishlist)
        let sharedID = wishlist.sharedWishlistID
        let pairs = items.map { ($0.id.uuidString, $0.sortIndex) }

        if isShared, let sharedID {
            try await verifyEditorRole(wishlistID: sharedID)
            // Проставляем lastModifiedByUID=актор reorder'а на каждый сдвинутый item: корректная
            // атрибуция + auto-heal legacy items с null-полем. CF при этом push НЕ шлёт (encryptedPayload
            // не менялся) → reorder полностью тихий, но автор для будущих смысловых edit'ов верный.
            try await firestore.bulkReorderSharedItems(wishlistID: sharedID, items: pairs, lastModifiedByUID: currentUID)
        } else {
            try await firestore.bulkReorderPersonalItems(uid: currentUID, wishlistID: wishlistID, items: pairs)
        }
    }

    func deleteItem(id: String, wishlistID: String) async throws {
        _ = try uid

        guard let itemUUID = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemUUID })
        guard let item = try modelContext.fetch(descriptor).first else {
            throw FirestoreService.FirestoreError.notFound
        }

        let wishlist = item.wishlist
        let isShared = wishlist.map { wishlistIsShared($0) } ?? false
        let sharedID = wishlist?.sharedWishlistID

        if isShared, let sharedID {
            try await verifyEditorRole(wishlistID: sharedID)
            _ = sharedID
        }

        // Soft-delete локально (tombstone). UI фильтрует isDeleted=true. SyncEngine разворачивает
        // в hard-delete на сервере при наличии сети.
        let now = Date()
        item.isTombstoned = true
        item.deletedAt = now
        item.updatedAt = now
        item.fieldTimestampsJSON = FieldTimestamps.touch(item.fieldTimestampsJSON, fields: ["isDeleted"], at: now)
        try? modelContext.save()

        let payload = SyncPayload.encode(
            fields: ["deletedAt": now],
            timestamps: ["isDeleted": now],
            parentID: wishlistID,
            sharedID: sharedID
        )
        sync.enqueue(PendingOperation(
            entityType: "item",
            entityID: id,
            operationType: "delete",
            payloadJSON: payload
        ))
    }

    func archiveItem(id: String, wishlistID: String) async throws {
        _ = try uid

        guard let itemUUID = UUID(uuidString: id) else { throw FirestoreService.FirestoreError.notFound }
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemUUID })
        guard let item = try modelContext.fetch(descriptor).first else {
            throw FirestoreService.FirestoreError.notFound
        }

        let wishlist = item.wishlist
        let isShared = wishlist.map { wishlistIsShared($0) } ?? false
        let sharedID = wishlist?.sharedWishlistID

        if isShared, let sharedID {
            try await verifyEditorRole(wishlistID: sharedID)
            _ = sharedID
        }

        let now = Date()
        item.isArchived = true
        item.updatedAt = now
        item.fieldTimestampsJSON = FieldTimestamps.touch(item.fieldTimestampsJSON, fields: ["isArchived"], at: now)
        try? modelContext.save()

        let payload = SyncPayload.encode(
            fields: ["isArchived": true],
            timestamps: ["isArchived": now],
            parentID: wishlistID,
            sharedID: sharedID
        )
        sync.enqueue(PendingOperation(
            entityType: "item",
            entityID: id,
            operationType: "archive",
            payloadJSON: payload
        ))
    }

    // MARK: - Sync

    func refreshWishlists(force: Bool = false) async {
        guard let currentUID = auth.uid else { return }

        // Throttle: не чаще раз в N сек, иначе быстро вышибаем дневную квоту Firestore.
        // force=true (deep-link резолв свежеприсоединённого списка) обходит throttle, но не lock.
        if !force, let last = lastRefreshWishlistsAt,
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
            // Pre-fetch memberships ОДИН раз (раньше дублировался на line 867 → quota waste).
            let allMemberships = try await firestore.fetchMyMemberships(userUID: currentUID)
            let memberWishlistIDs = Set(allMemberships.map(\.wishlistID))

            for local in localPersonal {
                // SAFETY на reinstall: если local wishlist помечен как НЕ имеющий ключа,
                // и в remote его не видно — НЕ удаляем (вероятно iCloud Keychain ещё не догнал,
                // remote.fetchPersonalWishlists пропустил его). Иначе юзер увидит пропавшие списки.
                let hasKey = KeychainService.load(for: local.id.uuidString) != nil
                let isInMembership = memberWishlistIDs.contains(local.id.uuidString)
                if !remoteIDs.contains(local.id.uuidString) && (hasKey || isInMembership) {
                    modelContext.delete(local)
                }
            }

            // 4. Add new or update existing

            for r in remote {
                // Skip personal wishlists that are managed as shared (have membership)
                if memberWishlistIDs.contains(r.id) {
                    continue
                }

                if let local = localByID[r.id] {
                    // name/emoji/cover применяем как единый блок "remote wins", но не затираем
                    // локальные несинхронизированные правки (pending в outbox). Раньше обложка имела
                    // лишний guard `== nil` → чужие/новые обложки не доходили. Write-side per-field LWW
                    // уже разрулил конфликт на сервере; read-side просто отражает истину.
                    // hasAnyPendingSync (а не hasPendingSync) — чтобы poll в окне ~0.7с после локальной
                    // правки не затёр её stale-снапшотом (freshlyEnqueued-фильтр только для UI-чипа).
                    if !sync.hasAnyPendingSync(entityType: "wishlist", entityID: r.id) {
                        local.name = r.name
                        local.coverEmoji = r.emoji
                        local.coverImageData = r.coverImageData
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

            // 5. Also fetch shared wishlists via memberships (используем pre-fetched выше).
            let memberships = allMemberships

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
                let info: FirestoreService.SharedWishlistInfo
                do {
                    info = try await firestore.fetchSharedWishlist(wishlistID: membership.wishlistID, key: sharedKey)
                } catch {
                    // Различаем сеть и реальное удаление. Старый `try?` глотал любые ошибки →
                    // юзер при network glitch'е терял membership (leaveWishlist!) + local copy
                    // чужого шаренного вишлиста — баг #5 от Влада 2026-05-16. Network → оставляем
                    // всё как есть, при возврате сети refreshWishlists повторится и догрузит.
                    if NetworkMonitor.isNetworkError(error) {
                        dsLog.debug("refreshWishlists: network error fetching shared \(membership.wishlistID, privacy: .public), keeping local + membership")
                        continue
                    }
                    // Non-network (404 / decryption / ownerMismatch) — wishlist реально недоступен,
                    // чистим membership и local copy как раньше.
                    try? await firestore.leaveWishlist(wishlistID: membership.wishlistID, userUID: currentUID)
                    if let local = localBySharedID[membership.wishlistID] {
                        modelContext.delete(local)
                    }
                    continue
                }

                // Auto-heal ownerName в encrypted payload: если я owner и payload содержит
                // legacy "Пользователь" или пусто — переписываю на актуальное userName.
                // Без флагов — на каждом refresh, идемпотентно (PATCH PATCH с тем же значением no-op).
                if info.ownerUID == currentUID,
                   let myName = auth.userName, !myName.isEmpty, myName != "Пользователь",
                   info.ownerName != myName {
                    try? await firestore.updateSharedWishlist(
                        wishlistID: membership.wishlistID,
                        name: info.name,
                        emoji: info.coverEmoji,
                        coverImageData: info.coverImageData,
                        gradientHue: info.gradientHue,
                        ownerName: myName,
                        key: sharedKey
                    )
                    dsLog.info("auto-heal ownerName for \(membership.wishlistID, privacy: .public): \(info.ownerName ?? "nil", privacy: .public) → \(myName, privacy: .public)")
                }
                if true {
                    // Re-fetch local list after deletions
                    let currentLocal = (try? modelContext.fetch(FetchDescriptor<Wishlist>())) ?? []
                    let currentBySharedID = Dictionary(currentLocal.compactMap { wl -> (String, Wishlist)? in
                        guard let sid = wl.sharedWishlistID else { return nil }
                        return (sid, wl)
                    }, uniquingKeysWith: { _, new in new })
                    if let local = currentBySharedID[info.wishlistID] {
                        // Protect: если этот wishlist в outbox (название/обложка ждут sync), skip overwrite.
                        // hasAnyPendingSync — учитываем и свежие op (<0.7с), чтобы poll не затёр правку.
                        let hasPending = sync.hasAnyPendingSync(entityType: "wishlist", entityID: local.id.uuidString)
                        if !hasPending {
                            local.name = info.name
                            local.coverEmoji = info.coverEmoji
                            // Обложка применяется как name/emoji (remote wins при отсутствии local pending).
                            // Раньше тут был guard `== nil` → обновлённая Настей обложка не доходила,
                            // если у участника уже была обложка (баг #3 от Влада).
                            local.coverImageData = info.coverImageData
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
            dsLog.error("refreshWishlists error: \(error.localizedDescription, privacy: .public)")
        }

        isSyncing = false
    }

    func refreshItems(for wishlistID: String, force: Bool = false) async {
        guard let currentUID = auth.uid else { return }

        // Throttle per-wishlist: не чаще раз в N сек. force=true (deep-link открытие карточки
        // свежесозданного item'а) обходит throttle, но не lock.
        if !force, let last = lastRefreshItemsAt[wishlistID],
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
            // Различаем сетевой сбой и реальное удаление wishlist'а в Firestore.
            // Network error (URLError/5xx/408) — оставляем local: NetworkMonitor покажет banner,
            // при возврате сети polling повторит refreshItems. Иначе при любой плохой сети
            // юзера выбрасывает из открытого вишлиста на главный — баг #5 от Влада 2026-05-16.
            // 404 / decryptionFailed — wishlist реально удалён или ключ ротирован, чистим local.
            let isNetwork = NetworkMonitor.isNetworkError(error)
            if !isNetwork, wishlistIsShared(wishlist) {
                modelContext.delete(wishlist)
                try? modelContext.save()
                wishlistDeleted = true
            }
            syncError = error.localizedDescription
            dsLog.error("refreshItems error (network=\(isNetwork, privacy: .public)): \(error.localizedDescription, privacy: .public)")
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
                // Не удалять item который ещё ждёт server-create (op в outbox).
                // hasAnyPendingSync — включая свежие op (<0.7с), иначе poll успеет удалить локально
                // созданный item до его server-create.
                if sync.hasAnyPendingSync(entityType: "item", entityID: local.id.uuidString) {
                    continue
                }
                modelContext.delete(local)
            }
        }

        for remote in remoteItems {
            let tier = ItemTier(rawValue: remote.tier) ?? .maybe

            if let local = localByID[remote.itemID] {
                // Protect local items с pending sync: server-state ещё не содержит наших последних
                // изменений (они в outbox), нельзя overwrite'ить локалные значения. Skip apply
                // remote-state до тех пор пока pending op'a не уйдёт в Firestore.
                // hasAnyPendingSync — включая свежие op (<0.7с), чтобы poll не откатил правку item'а.
                if sync.hasAnyPendingSync(entityType: "item", entityID: remote.itemID) {
                    continue
                }
                // Diff-guard: переписываем поле ТОЛЬКО если remote реально отличается от local,
                // и трогаем updatedAt лишь когда что-то изменилось. Раньше всё переприсваивалось
                // безусловно каждый poll (15с), updatedAt=.now дёргал объект → список переанимировался
                // под открытым шитом (баг #2 «скролл прыгает», ложно списанный на фотопикер).
                var changed = false
                if local.name != remote.name { local.name = remote.name; changed = true }
                if local.tier != tier { local.tier = tier; changed = true }
                if local.priceValue != remote.price { local.priceValue = remote.price; changed = true }
                if local.priceMaxValue != remote.priceMax { local.priceMaxValue = remote.priceMax; changed = true }
                if local.currency != remote.currency { local.currency = remote.currency; changed = true }
                if local.url != remote.url { local.url = remote.url; changed = true }
                if local.coverEmoji != remote.coverEmoji { local.coverEmoji = remote.coverEmoji; changed = true }
                if local.sortIndex != remote.sortIndex { local.sortIndex = remote.sortIndex; changed = true }
                if local.isArchived != remote.isArchived { local.isArchived = remote.isArchived; changed = true }
                // Поля у legacy items могут отсутствовать в payload — не затираем local
                // если remote вернулся без значения (старая версия писала payload без них).
                if let uid = remote.addedByUID, local.addedByUID != uid { local.addedByUID = uid; changed = true }
                if let nm = remote.addedByName, local.addedByName != nm { local.addedByName = nm; changed = true }
                if let img = remote.coverImageData, local.coverImageData != img { local.coverImageData = img; changed = true }
                if let lm = remote.linkMetadataData, local.linkMetadataData != lm { local.linkMetadataData = lm; changed = true }
                if let desc = remote.descriptionText, local.descriptionText != desc { local.descriptionText = desc; changed = true }
                if let prob = remote.probationEndAt, local.probationEndAt != prob { local.probationEndAt = prob; changed = true }
                if let hue = remote.gradientHue, local.gradientHue != hue { local.gradientHue = hue; changed = true }
                if changed { local.updatedAt = .now }
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
                    gradientHue: remote.gradientHue,
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
            throw FirestoreService.FirestoreError.requestFailed(statusCode: 0, body: String(localized: "Invalid role"))
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
            throw FirestoreService.FirestoreError.requestFailed(statusCode: 0, body: String(localized: "Only the owner can change roles"))
        }

        // Запретить менять роль самому себе через этот метод (нет смысла — owner не может стать viewer).
        guard memberUID != currentUID else {
            throw FirestoreService.FirestoreError.requestFailed(statusCode: 0, body: String(localized: "You can’t change your own role"))
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

    /// Owner меняет флаг canInvite у участника.
    func changeMemberCanInvite(wishlistID: String, memberUID: String, canInvite: Bool) async throws {
        let currentUID = try uid

        let descriptor = FetchDescriptor<Wishlist>()
        let allLocal = (try? modelContext.fetch(descriptor)) ?? []
        guard let wishlist = allLocal.first(where: { $0.sharedWishlistID == wishlistID }) else {
            throw FirestoreService.FirestoreError.notFound
        }

        let isOwner: Bool = {
            if let owner = wishlist.ownerRecordID { return owner == currentUID }
            return wishlist.myRole == "owner"
        }()
        guard isOwner else {
            throw FirestoreService.FirestoreError.requestFailed(statusCode: 0, body: String(localized: "Only the owner can change invitation rights"))
        }

        guard memberUID != currentUID else {
            throw FirestoreService.FirestoreError.requestFailed(statusCode: 0, body: String(localized: "You can’t change your own rights"))
        }

        await acquireLock()
        isSyncing = true
        syncError = nil
        defer { releaseLock() }

        do {
            try await firestore.updateMembershipCanInvite(
                wishlistID: wishlistID,
                userUID: memberUID,
                canInvite: canInvite
            )
        } catch {
            isSyncing = false
            throw error
        }

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
            throw FirestoreService.FirestoreError.requestFailed(statusCode: 0, body: String(localized: "Only the owner can remove participants"))
        }

        // Нельзя кикнуть самого owner'а — для удаления списка есть deleteWishlist.
        guard memberUID != currentUID else {
            throw FirestoreService.FirestoreError.requestFailed(statusCode: 0, body: String(localized: "The owner can’t remove themselves — delete the list instead"))
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

    // MARK: - NSE shared-keychain migration

    /// One-time: копирует ключи существующих wishlist'ов в shared keychain access group, чтобы
    /// NotificationServiceExtension мог расшифровать имя желания и для списков, созданных до NSE.
    /// Аддитивно (оригиналы не трогаются). Новые/принятые списки покрываются автоматически в
    /// KeychainService.save. Идемпотентно; флаг ставим только когда реально было что мигрировать.
    func migrateSharedKeychainIfNeeded() {
        let flag = "iwish_nse_shared_keychain_migrated_v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        let wishlists = (try? modelContext.fetch(FetchDescriptor<Wishlist>())) ?? []
        // ВАЖНО: ключ shared-списка хранится в Keychain под sharedWishlistID (Firestore doc id),
        // а personal — под локальным UUID. Мигрируем по реальным account'ам, иначе ключи shared-
        // списков (а именно для них работают push/NSE) не скопируются в shared group.
        let ids = wishlists.flatMap { wl -> [String] in
            if let sid = wl.sharedWishlistID, !sid.isEmpty { return [sid] }
            return [wl.id.uuidString]
        }
        guard !ids.isEmpty else { return } // store ещё пуст — повторим при следующем запуске
        // Флаг ставим ТОЛЬКО если shared group реально доступна (NSE-entitlement уже в билде).
        // Иначе (entitlement появится в будущем билде) — повторим миграцию при следующем запуске.
        let ok = KeychainService.migrateKeysToSharedGroup(wishlistIDs: ids)
        if ok {
            UserDefaults.standard.set(true, forKey: flag)
            dsLog.info("NSE shared-keychain migration done for \(ids.count, privacy: .public) wishlists")
        } else {
            dsLog.debug("NSE shared-keychain migration deferred — access group not yet entitled")
        }
    }

    // MARK: - v1.1 Migration backfill

    /// One-time backfill при первом старте v1.1: пройти по local items с непустыми
    /// "missing" полями (description/coverImageData/linkMeta/probationEndAt) и переслать
    /// в Firestore чтобы они попали в encryptedPayload. Также backfill memberships userName.
    /// Идемпотентно. Маркер UserDefaults; при partial failure повторим в следующем старте.
    func runV11BackfillIfNeeded() async {
        let backfillKey = "iwish_v11_backfill_done"
        // v2 ключ — расширили self-heal на wishlists с ownerRecordID == nil (resolve через GET).
        let ownerHealKey = "iwish_v11_owner_heal_v2_done"
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
                        probationEndAt: item.probationEndAt,
                        gradientHue: item.gradientHue
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
            for wl in allWishlists where wl.isShared {
                guard let sharedID = wl.sharedWishlistID else { continue }

                // SECURITY: всегда верифицируем ownerUID через wire (не доверяем локальному
                // wl.ownerRecordID — он мог быть отравлен старым owner-flip багом до 2026-05-10).
                // Если wire-GET не получился — пропускаем self-heal, чтобы случайно никого не
                // повысить на основе stale данных.
                var resolvedOwnerUID: String? = nil
                if let doc = try? await firestore.fetchSharedWishlistOwnerUID(wishlistID: sharedID) {
                    resolvedOwnerUID = doc
                    // Заодно лечим locally — кейс где локальное значение отстаёт от Firestore.
                    if wl.ownerRecordID != doc {
                        wl.ownerRecordID = doc
                    }
                }

                guard let resolved = resolvedOwnerUID, resolved == myUID else { continue }

                // 1. Self-heal owner-role: PATCH membership.role="owner" если она другая.
                //    ДОПОЛНИТЕЛЬНАЯ ЗАЩИТА: перед повышением себя в owner проверяем что
                //    нет другой active membership с role="owner" для того же wishlist'а.
                //    Если есть — что-то странное (двойной owner после bug); abort и log.
                if wl.myRole != "owner" {
                    // FAIL-CLOSED: если fetchAllMemberships упал — пропускаем self-heal этого wishlist'а
                    // (не доверяем "пустому" результату, чтобы случайно не повысить себя при двойном owner).
                    let memberships: [(userUID: String, role: String, canInvite: Bool)]
                    do {
                        memberships = try await firestore.fetchAllMemberships(wishlistID: sharedID)
                    } catch {
                        dsLog.warning("v1.1 self-heal: SKIP for \(sharedID, privacy: .public) — fetchAllMemberships failed: \(error.localizedDescription, privacy: .public)")
                        allOK = false
                        continue
                    }
                    let hasOtherOwner = memberships.contains { $0.userUID != myUID && $0.role == "owner" }
                    guard !hasOtherOwner else {
                        dsLog.warning("v1.1 self-heal: ABORT for \(sharedID, privacy: .public) — another owner membership exists")
                        continue
                    }
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
