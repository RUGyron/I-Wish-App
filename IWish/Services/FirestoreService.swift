import Foundation
import CryptoKit
import FirebaseAuth
import os.log

private let logger = Logger(subsystem: "RUGyron.IWish", category: "Firestore")

/// REST-клиент Firestore с E2E-шифрованием content-полей.
///
/// Privacy-модель:
/// - Все user-facing поля (name, emoji, photo, price, url, description, ownerName) пакуются в JSON,
///   шифруются AES-GCM-256 ключом конкретного wishlist'а и пишутся в одно поле `encryptedPayload` (bytesValue).
/// - Plaintext остаётся только то, что нужно для индексации/permissions:
///   IDs, gradientSeed, isArchived, sortIndex, timestamps, role, canInvite, joinedAt.
/// - Ключи живут в iCloud Keychain (см. `KeychainService`). Разраб с доступом к Firebase Console
///   видит только зашифрованные блобы и метаданные.
@Observable
final class FirestoreService {

    // MARK: - Constants

    private let projectPath = "projects/rewardpierwebpush/databases/(default)/documents"
    private let baseURL = "https://firestore.googleapis.com/v1/projects/rewardpierwebpush/databases/(default)/documents"

    // MARK: - Types (same as old CloudKitSharingService for compat)

    struct ShareLinkInfo {
        let wishlistID: String
        let wishlistName: String
        let wishlistEmoji: String?
        let coverImageData: Data?
        let ownerName: String?
        let role: String
        let itemCount: Int
        let gradientSeed: Int
        let canInvite: Bool
    }

    struct SharedWishlistInfo {
        let wishlistID: String
        let name: String
        let coverEmoji: String?
        let coverImageData: Data?
        let ownerUID: String
        let ownerName: String?
        let gradientSeed: Int
        let gradientHue: Double?
        let isArchived: Bool
        let members: [(userUID: String, role: String, userName: String?)]
        let items: [SharedItemInfo]
    }

    struct SharedItemInfo {
        let itemID: String
        let name: String
        let tier: String
        let price: Double?
        let priceMax: Double?
        let currency: String
        let url: String?
        let coverEmoji: String?
        let coverImageData: Data?
        let linkMetadataData: Data?
        let descriptionText: String?
        let probationEndAt: Date?
        let sortIndex: Double
        let isArchived: Bool
        /// UID юзера, который добавил item. Хранится в зашифрованном payload.
        let addedByUID: String?
        /// displayName юзера на момент добавления. Хранится в зашифрованном payload.
        let addedByName: String?
    }

    enum FirestoreError: LocalizedError {
        case notFound
        case notAuthenticated
        case requestFailed(String)
        case decryptionFailed
        case rateLimited

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "Документ не найден"
            case .notAuthenticated:
                return "Необходима авторизация"
            case .requestFailed(let msg):
                return "Ошибка запроса: \(msg)"
            case .decryptionFailed:
                return "Не удалось расшифровать данные"
            case .rateLimited:
                return "Слишком много запросов. Попробуйте через минуту."
            }
        }
    }

    // MARK: - Rate limiter

    /// Скользящее окно последних 60 секунд — отсекает burst'ы и runaway loops,
    /// чтобы не выйти за пределы Spark plan (50K reads/day).
    private var recentRequestTimestamps: [Date] = []
    private let rateLimiterQueue = DispatchQueue(label: "RUGyron.IWish.firestore.ratelimit")

    private func checkRateLimit() throws {
        try rateLimiterQueue.sync {
            let now = Date()
            recentRequestTimestamps.removeAll { now.timeIntervalSince($0) >= 60 }
            guard recentRequestTimestamps.count < InputLimits.maxFirestoreRequestsPerMinute else {
                logger.warning("[Firestore] Rate limit hit: \(self.recentRequestTimestamps.count) reqs in last 60s")
                throw FirestoreError.rateLimited
            }
            recentRequestTimestamps.append(now)
        }
    }

    // MARK: - Auth

    private func getAuthToken() async throws -> String {
        // Try REST-based token first (works through VPN)
        if let token = await AppServices.shared.auth.getIDToken() {
            return token
        }
        // Fallback: SDK
        if let user = Auth.auth().currentUser,
           let token = try? await user.getIDToken() {
            return token
        }
        throw FirestoreError.notAuthenticated
    }

    // MARK: - HTTP helpers

    /// Generic request: sends HTTP method to `baseURL/path`, returns decoded JSON dict.
    private func request(_ method: String, path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        try checkRateLimit()
        let token = try await getAuthToken()
        var urlString = path.hasPrefix("http") ? path : "\(baseURL)/\(path)"
        // Trim trailing slash
        if urlString.hasSuffix("/") { urlString = String(urlString.dropLast()) }
        guard let url = URL(string: urlString) else {
            throw FirestoreError.requestFailed("Invalid URL: \(urlString)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw FirestoreError.requestFailed(errorText)
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// POST to a URL that returns an array (e.g. runQuery).
    private func requestArray(_ path: String, body: [String: Any]) async throws -> [[String: Any]] {
        try checkRateLimit()
        let token = try await getAuthToken()
        let urlString = path.hasPrefix("http") ? path : "\(baseURL)/\(path)"
        guard let url = URL(string: urlString) else {
            throw FirestoreError.requestFailed("Invalid URL: \(urlString)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw FirestoreError.requestFailed(errorText)
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    // MARK: - Field conversion helpers

    /// Convert Firestore REST "fields" dict to simple Swift values.
    private func parseFields(_ fields: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in fields {
            guard let fieldValue = value as? [String: Any] else { continue }
            if let s = fieldValue["stringValue"] as? String { result[key] = s }
            else if let d = fieldValue["doubleValue"] as? Double { result[key] = d }
            else if let d = fieldValue["doubleValue"] as? Int { result[key] = Double(d) }
            else if let i = fieldValue["integerValue"] as? String { result[key] = Int(i) ?? 0 }
            else if let i = fieldValue["integerValue"] as? Int { result[key] = i }
            else if let b = fieldValue["booleanValue"] as? Bool { result[key] = b }
            else if let t = fieldValue["timestampValue"] as? String { result[key] = t }
            else if let b = fieldValue["bytesValue"] as? String { result[key] = Data(base64Encoded: b) as Any }
            else if fieldValue["nullValue"] != nil { result[key] = NSNull() }
        }
        return result
    }

    /// Convert Swift values to Firestore REST field format.
    private func toFields(_ data: [String: Any?]) -> [String: Any] {
        var fields: [String: Any] = [:]
        for (key, value) in data {
            if let s = value as? String { fields[key] = ["stringValue": s] }
            else if let d = value as? Double { fields[key] = ["doubleValue": d] }
            else if let i = value as? Int { fields[key] = ["integerValue": String(i)] }
            else if let b = value as? Bool { fields[key] = ["booleanValue": b] }
            else if let data = value as? Data { fields[key] = ["bytesValue": data.base64EncodedString()] }
            else if let date = value as? Date {
                let formatter = ISO8601DateFormatter()
                fields[key] = ["timestampValue": formatter.string(from: date)]
            }
            else if value == nil || value is NSNull { fields[key] = ["nullValue": NSNull()] }
        }
        return fields
    }

    /// Extract document ID from full Firestore document "name" path.
    private func documentID(from name: String) -> String {
        // "projects/.../documents/collection/DOC_ID"
        name.components(separatedBy: "/").last ?? name
    }

    /// Build full document name for batch writes.
    private func fullDocName(_ collectionPath: String) -> String {
        "\(projectPath)/\(collectionPath)"
    }

    // MARK: - Personal Wishlists (users/{uid}/wishlists)

    func createPersonalWishlist(
        uid: String,
        wishlistID: String,
        name: String,
        emoji: String?,
        gradientSeed: Int,
        gradientHue: Double? = nil,
        coverImageData: Data? = nil,
        key: SymmetricKey
    ) async throws {
        let payload = EncryptionService.packPayload([
            "name": name,
            "coverEmoji": emoji,
            "coverImageData": coverImageData
        ])
        let encrypted = try EncryptionService.encrypt(payload, using: key)

        var data: [String: Any?] = [
            "encryptedPayload": encrypted,
            "gradientSeed": gradientSeed as Any,
            "isArchived": false as Any,
            "createdAt": Date() as Any,
            "updatedAt": Date() as Any
        ]
        if let gradientHue { data["gradientHue"] = gradientHue }
        let fields = toFields(data)
        let _ = try await request("PATCH", path: "users/\(uid)/wishlists/\(wishlistID)", body: ["fields": fields])
    }

    func updatePersonalWishlist(
        uid: String,
        wishlistID: String,
        name: String,
        emoji: String?,
        coverImageData: Data? = nil,
        gradientHue: Double? = nil,
        key: SymmetricKey
    ) async throws {
        var existingPayload: [String: Any] = [:]
        if let existingDoc = try? await request("GET", path: "users/\(uid)/wishlists/\(wishlistID)"),
           let fields = existingDoc["fields"] as? [String: Any],
           let encryptedData = parseFields(fields)["encryptedPayload"] as? Data,
           let decrypted = try? EncryptionService.decrypt(encryptedData, using: key) {
            existingPayload = decrypted
        }

        let updates: [String: Any?] = [
            "name": name,
            "coverEmoji": emoji,
            "coverImageData": coverImageData
        ]

        var merged = existingPayload
        for (k, v) in updates {
            if let v {
                if let d = v as? Data { merged[k] = d.base64EncodedString() } else { merged[k] = v }
            } else {
                merged.removeValue(forKey: k)
            }
        }

        let encrypted = try EncryptionService.encrypt(merged, using: key)

        var data: [String: Any?] = [
            "encryptedPayload": encrypted,
            "updatedAt": Date() as Any
        ]
        var maskFields = ["encryptedPayload", "updatedAt"]
        if let gradientHue {
            data["gradientHue"] = gradientHue
            maskFields.append("gradientHue")
        }
        let maskPaths = maskFields.map { "updateMask.fieldPaths=\($0)" }.joined(separator: "&")
        let fields = toFields(data)
        let _ = try await request("PATCH", path: "users/\(uid)/wishlists/\(wishlistID)?\(maskPaths)", body: ["fields": fields])
    }

    func archivePersonalWishlist(uid: String, wishlistID: String, isArchived: Bool) async throws {
        let fields = toFields([
            "isArchived": isArchived as Any,
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "users/\(uid)/wishlists/\(wishlistID)?updateMask.fieldPaths=isArchived&updateMask.fieldPaths=updatedAt", body: ["fields": fields])
    }

    func archiveSharedWishlist(wishlistID: String, isArchived: Bool) async throws {
        let fields = toFields([
            "isArchived": isArchived as Any,
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "shared_wishlists/\(wishlistID)?updateMask.fieldPaths=isArchived&updateMask.fieldPaths=updatedAt", body: ["fields": fields])
    }

    func deletePersonalWishlist(uid: String, wishlistID: String) async throws {
        // Delete items first
        let itemsDocs = try await listDocuments(parentPath: "users/\(uid)/wishlists/\(wishlistID)/items")
        if !itemsDocs.isEmpty {
            var writes: [[String: Any]] = []
            for doc in itemsDocs {
                if let name = doc["name"] as? String {
                    writes.append(["delete": name])
                }
            }
            let commitURL = "\(baseURL):commit"
            let _ = try await request("POST", path: commitURL, body: ["writes": writes])
        }
        // Delete wishlist
        let _ = try await request("DELETE", path: "users/\(uid)/wishlists/\(wishlistID)")
    }

    /// Возвращает personal-вишлисты пользователя. Для расшифровки содержимого каждого
    /// вишлиста запрашивает ключ через `keyProvider(wishlistID)`. Если ключ не найден или
    /// расшифровка не удалась — wishlist пропускается (зашифрованные данные без ключа бесполезны).
    func fetchPersonalWishlists(uid: String, keyProvider: (String) -> SymmetricKey?) async throws -> [(id: String, name: String, emoji: String?, coverImageData: Data?, gradientSeed: Int, gradientHue: Double?, isArchived: Bool)] {
        let docs = try await listDocuments(parentPath: "users/\(uid)/wishlists")
        var results: [(id: String, name: String, emoji: String?, coverImageData: Data?, gradientSeed: Int, gradientHue: Double?, isArchived: Bool)] = []
        for doc in docs {
            guard let docName = doc["name"] as? String else { continue }
            let docID = documentID(from: docName)
            guard let fields = doc["fields"] as? [String: Any] else { continue }
            let parsed = parseFields(fields)

            guard let key = keyProvider(docID) else {
                logger.debug("[Firestore] No key for personal wishlist \(docID, privacy: .public), skipping")
                continue
            }
            guard let payloadData = parsed["encryptedPayload"] as? Data else {
                logger.debug("[Firestore] No encryptedPayload for personal wishlist \(docID, privacy: .public), skipping")
                continue
            }
            guard let content = try? EncryptionService.decrypt(payloadData, using: key) else {
                logger.error("[Firestore] Failed to decrypt personal wishlist \(docID, privacy: .public)")
                continue
            }

            let name = content["name"] as? String ?? ""
            let emojiRaw = content["coverEmoji"] as? String
            let emoji: String? = (emojiRaw?.isEmpty == false) ? emojiRaw : nil
            let coverImageData = EncryptionService.dataField(content, "coverImageData")
            let seed = parsed["gradientSeed"] as? Int ?? 0
            let hue = parsed["gradientHue"] as? Double
            let isArchived = parsed["isArchived"] as? Bool ?? false

            results.append((id: docID, name: name, emoji: emoji, coverImageData: coverImageData, gradientSeed: seed, gradientHue: hue, isArchived: isArchived))
        }
        return results
    }

    // MARK: - Personal Items (users/{uid}/wishlists/{wid}/items)

    func createPersonalItem(
        uid: String,
        wishlistID: String,
        itemID: String,
        name: String,
        tier: String,
        price: Double?,
        priceMax: Double? = nil,
        currency: String,
        url: String?,
        emoji: String?,
        sortIndex: Double,
        descriptionText: String? = nil,
        coverImageData: Data? = nil,
        linkMetadataData: Data? = nil,
        probationEndAt: Date? = nil,
        addedByUID: String? = nil,
        addedByName: String? = nil,
        key: SymmetricKey
    ) async throws {
        let payload = EncryptionService.packPayload([
            "name": name,
            "tier": tier,
            "price": price,
            "priceMax": priceMax,
            "currency": currency,
            "url": url,
            "coverEmoji": emoji,
            "coverImageData": coverImageData,
            "linkMeta": linkMetadataData,
            "description": descriptionText,
            "probationEndAt": probationEndAt.map { ISO8601DateFormatter().string(from: $0) },
            "addedByUID": addedByUID,
            "addedByName": addedByName
        ])
        let encrypted = try EncryptionService.encrypt(payload, using: key)

        let fields = toFields([
            "encryptedPayload": encrypted as Any,
            "sortIndex": sortIndex as Any,
            "isArchived": false as Any,
            "createdAt": Date() as Any,
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "users/\(uid)/wishlists/\(wishlistID)/items/\(itemID)", body: ["fields": fields])
    }

    /// Update personal item с preserve-unknown-keys: GET → decrypt → merge → re-encrypt + PATCH.
    /// Это защищает forward-compat: если будущие версии добавят новые поля, наш клиент их сохранит.
    func updatePersonalItem(
        uid: String,
        wishlistID: String,
        itemID: String,
        name: String,
        tier: String,
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
        addedByUID: String? = nil,
        addedByName: String? = nil,
        key: SymmetricKey
    ) async throws {
        var existingPayload: [String: Any] = [:]
        if let existingDoc = try? await request("GET", path: "users/\(uid)/wishlists/\(wishlistID)/items/\(itemID)"),
           let fields = existingDoc["fields"] as? [String: Any],
           let encryptedData = parseFields(fields)["encryptedPayload"] as? Data,
           let decrypted = try? EncryptionService.decrypt(encryptedData, using: key) {
            existingPayload = decrypted
        }

        let updates: [String: Any?] = [
            "name": name,
            "tier": tier,
            "price": price,
            "priceMax": priceMax,
            "currency": currency,
            "url": url,
            "coverEmoji": emoji,
            "coverImageData": coverImageData,
            "linkMeta": linkMetadataData,
            "description": descriptionText,
            "probationEndAt": probationEndAt.map { ISO8601DateFormatter().string(from: $0) },
            "addedByUID": addedByUID,
            "addedByName": addedByName
        ]

        var merged = existingPayload
        for (k, v) in updates {
            if let v {
                if let d = v as? Data {
                    merged[k] = d.base64EncodedString()
                } else {
                    merged[k] = v
                }
            } else {
                merged.removeValue(forKey: k)
            }
        }

        let encrypted = try EncryptionService.encrypt(merged, using: key)
        let fields = toFields([
            "encryptedPayload": encrypted as Any,
            "sortIndex": sortIndex as Any,
            "isArchived": isArchived as Any,
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "users/\(uid)/wishlists/\(wishlistID)/items/\(itemID)", body: ["fields": fields])
    }

    func deletePersonalItem(uid: String, wishlistID: String, itemID: String) async throws {
        let _ = try await request("DELETE", path: "users/\(uid)/wishlists/\(wishlistID)/items/\(itemID)")
    }

    func fetchPersonalItems(uid: String, wishlistID: String, key: SymmetricKey) async throws -> [SharedItemInfo] {
        let docs = try await listDocuments(parentPath: "users/\(uid)/wishlists/\(wishlistID)/items")
        var items: [SharedItemInfo] = []
        for doc in docs {
            if let item = try? parseEncryptedItemFromDoc(doc, key: key) {
                items.append(item)
            }
        }
        return items.sorted { $0.sortIndex < $1.sortIndex }
    }

    // MARK: - Shared Wishlists (shared_wishlists/)

    func createSharedWishlist(
        wishlistID: String,
        name: String,
        emoji: String?,
        coverImageData: Data? = nil,
        gradientSeed: Int,
        gradientHue: Double? = nil,
        ownerUID: String,
        ownerName: String?,
        items: [SharedItemInfo],
        key: SymmetricKey
    ) async throws {
        // 1. Write the wishlist document
        let wishlistPayload = EncryptionService.packPayload([
            "name": name,
            "coverEmoji": emoji,
            "coverImageData": coverImageData,
            "ownerName": ownerName
        ])
        let encryptedWishlist = try EncryptionService.encrypt(wishlistPayload, using: key)

        var data: [String: Any?] = [
            "encryptedPayload": encryptedWishlist,
            "gradientSeed": gradientSeed as Any,
            "isArchived": false as Any,
            "ownerUID": ownerUID,
            "createdAt": Date() as Any,
            "updatedAt": Date() as Any
        ]
        if let gradientHue { data["gradientHue"] = gradientHue }
        let wishlistFields = toFields(data)
        let _ = try await request("PATCH", path: "shared_wishlists/\(wishlistID)", body: ["fields": wishlistFields])

        // 2. Batch write all items (each encrypted with the same wishlist key)
        if !items.isEmpty {
            var writes: [[String: Any]] = []
            for item in items {
                let itemPayload = EncryptionService.packPayload([
                    "name": item.name,
                    "tier": item.tier,
                    "price": item.price,
                    "priceMax": item.priceMax,
                    "currency": item.currency,
                    "url": item.url,
                    "coverEmoji": item.coverEmoji,
                    "coverImageData": item.coverImageData,
                    "linkMeta": item.linkMetadataData,
                    "description": item.descriptionText,
                    "probationEndAt": item.probationEndAt.map { ISO8601DateFormatter().string(from: $0) },
                    "addedByUID": item.addedByUID,
                    "addedByName": item.addedByName
                ])
                let encryptedItem = try EncryptionService.encrypt(itemPayload, using: key)

                let itemFields = toFields([
                    "encryptedPayload": encryptedItem as Any,
                    "sortIndex": item.sortIndex as Any,
                    "isArchived": item.isArchived as Any,
                    "createdAt": Date() as Any,
                    "updatedAt": Date() as Any
                ])
                writes.append([
                    "update": [
                        "name": fullDocName("shared_wishlists/\(wishlistID)/items/\(item.itemID)"),
                        "fields": itemFields
                    ]
                ])
            }
            let commitURL = "\(baseURL):commit"
            let _ = try await request("POST", path: commitURL, body: ["writes": writes])
        }
    }

    func updateSharedWishlist(
        wishlistID: String,
        name: String,
        emoji: String?,
        coverImageData: Data? = nil,
        gradientHue: Double? = nil,
        ownerName: String?,
        key: SymmetricKey
    ) async throws {
        var existingPayload: [String: Any] = [:]
        if let existingDoc = try? await request("GET", path: "shared_wishlists/\(wishlistID)"),
           let fields = existingDoc["fields"] as? [String: Any],
           let encryptedData = parseFields(fields)["encryptedPayload"] as? Data,
           let decrypted = try? EncryptionService.decrypt(encryptedData, using: key) {
            existingPayload = decrypted
        }

        let updates: [String: Any?] = [
            "name": name,
            "coverEmoji": emoji,
            "coverImageData": coverImageData,
            "ownerName": ownerName
        ]

        var merged = existingPayload
        for (k, v) in updates {
            if let v {
                if let d = v as? Data { merged[k] = d.base64EncodedString() } else { merged[k] = v }
            } else {
                merged.removeValue(forKey: k)
            }
        }

        let encrypted = try EncryptionService.encrypt(merged, using: key)

        var data: [String: Any?] = [
            "encryptedPayload": encrypted,
            "updatedAt": Date() as Any
        ]
        var maskFields = ["encryptedPayload", "updatedAt"]
        if let gradientHue {
            data["gradientHue"] = gradientHue
            maskFields.append("gradientHue")
        }
        let maskPaths = maskFields.map { "updateMask.fieldPaths=\($0)" }.joined(separator: "&")
        let fields = toFields(data)
        let _ = try await request("PATCH", path: "shared_wishlists/\(wishlistID)?\(maskPaths)", body: ["fields": fields])
    }

    func fetchSharedWishlistItems(wishlistID: String, key: SymmetricKey) async throws -> [SharedItemInfo] {
        let docs = try await listDocuments(parentPath: "shared_wishlists/\(wishlistID)/items")
        var items: [SharedItemInfo] = []
        for doc in docs {
            if let item = try? parseEncryptedItemFromDoc(doc, key: key) {
                items.append(item)
            }
        }
        return items.sorted { $0.sortIndex < $1.sortIndex }
    }

    // MARK: - Shared Items CRUD (shared_wishlists/{wid}/items)

    func createSharedItem(
        wishlistID: String,
        itemID: String,
        name: String,
        tier: String,
        price: Double?,
        priceMax: Double? = nil,
        currency: String,
        url: String?,
        emoji: String?,
        sortIndex: Double,
        descriptionText: String? = nil,
        coverImageData: Data? = nil,
        linkMetadataData: Data? = nil,
        probationEndAt: Date? = nil,
        addedByUID: String? = nil,
        addedByName: String? = nil,
        key: SymmetricKey
    ) async throws {
        let payload = EncryptionService.packPayload([
            "name": name,
            "tier": tier,
            "price": price,
            "priceMax": priceMax,
            "currency": currency,
            "url": url,
            "coverEmoji": emoji,
            "coverImageData": coverImageData,
            "linkMeta": linkMetadataData,
            "description": descriptionText,
            "probationEndAt": probationEndAt.map { ISO8601DateFormatter().string(from: $0) },
            "addedByUID": addedByUID,
            "addedByName": addedByName
        ])
        let encrypted = try EncryptionService.encrypt(payload, using: key)

        let fields = toFields([
            "encryptedPayload": encrypted as Any,
            "sortIndex": sortIndex as Any,
            "isArchived": false as Any,
            "createdAt": Date() as Any,
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "shared_wishlists/\(wishlistID)/items/\(itemID)", body: ["fields": fields])
    }

    /// Update shared item с preserve-unknown-keys: GET → decrypt → merge → re-encrypt.
    /// Защищает forward-compat для будущих версий с новыми payload keys.
    func updateSharedItem(
        wishlistID: String,
        itemID: String,
        name: String,
        tier: String,
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
        addedByUID: String? = nil,
        addedByName: String? = nil,
        key: SymmetricKey
    ) async throws {
        var existingPayload: [String: Any] = [:]
        if let existingDoc = try? await request("GET", path: "shared_wishlists/\(wishlistID)/items/\(itemID)"),
           let fields = existingDoc["fields"] as? [String: Any],
           let encryptedData = parseFields(fields)["encryptedPayload"] as? Data,
           let decrypted = try? EncryptionService.decrypt(encryptedData, using: key) {
            existingPayload = decrypted
        }

        let updates: [String: Any?] = [
            "name": name,
            "tier": tier,
            "price": price,
            "priceMax": priceMax,
            "currency": currency,
            "url": url,
            "coverEmoji": emoji,
            "coverImageData": coverImageData,
            "linkMeta": linkMetadataData,
            "description": descriptionText,
            "probationEndAt": probationEndAt.map { ISO8601DateFormatter().string(from: $0) },
            "addedByUID": addedByUID,
            "addedByName": addedByName
        ]

        var merged = existingPayload
        for (k, v) in updates {
            if let v {
                if let d = v as? Data {
                    merged[k] = d.base64EncodedString()
                } else {
                    merged[k] = v
                }
            } else {
                merged.removeValue(forKey: k)
            }
        }

        let encrypted = try EncryptionService.encrypt(merged, using: key)
        let fields = toFields([
            "encryptedPayload": encrypted as Any,
            "sortIndex": sortIndex as Any,
            "isArchived": isArchived as Any,
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "shared_wishlists/\(wishlistID)/items/\(itemID)", body: ["fields": fields])
    }

    func deleteSharedItem(wishlistID: String, itemID: String) async throws {
        let _ = try await request("DELETE", path: "shared_wishlists/\(wishlistID)/items/\(itemID)")
    }

    func deleteSharedWishlistFull(wishlistID: String) async throws {
        logger.info("[Firestore] deleteSharedWishlistFull: \(wishlistID)")

        // 1. Delete the wishlist document FIRST (critical)
        let _ = try await request("DELETE", path: "shared_wishlists/\(wishlistID)")
        logger.info("[Firestore] Wishlist doc deleted")

        // 2. Cleanup items (best-effort — doc is already gone)
        if let itemsDocs = try? await listDocuments(parentPath: "shared_wishlists/\(wishlistID)/items") {
            for itemDoc in itemsDocs {
                if let name = itemDoc["name"] as? String {
                    let _ = try? await request("DELETE", path: "shared_wishlists/\(wishlistID)/items/\(documentID(from: name))")
                }
            }
        }

        // 3. Cleanup memberships (best-effort)
        if let memberResults = try? await runQuery(collectionId: "memberships", field: "wishlistID", op: "EQUAL", value: wishlistID) {
            for entry in memberResults {
                if let doc = entry["document"] as? [String: Any], let name = doc["name"] as? String {
                    let _ = try? await request("DELETE", path: "memberships/\(documentID(from: name))")
                }
            }
        }

        // 4. Cleanup invite links (best-effort)
        if let inviteResults = try? await runQuery(collectionId: "inviteLinks", field: "wishlistID", op: "EQUAL", value: wishlistID) {
            for entry in inviteResults {
                if let doc = entry["document"] as? [String: Any], let name = doc["name"] as? String {
                    let _ = try? await request("DELETE", path: "inviteLinks/\(documentID(from: name))")
                }
            }
        }

        logger.info("[Firestore] deleteSharedWishlistFull completed")
    }

    // MARK: - Fetch Shared Wishlist

    func fetchSharedWishlist(wishlistID: String, key: SymmetricKey) async throws -> SharedWishlistInfo {
        // 1. Get wishlist document from shared_wishlists
        let doc = try await request("GET", path: "shared_wishlists/\(wishlistID)")
        guard let fields = doc["fields"] as? [String: Any] else {
            throw FirestoreError.notFound
        }
        let parsed = parseFields(fields)

        // 2. Decrypt content
        guard let payloadData = parsed["encryptedPayload"] as? Data else {
            throw FirestoreError.notFound
        }
        let content: [String: Any]
        do {
            content = try EncryptionService.decrypt(payloadData, using: key)
        } catch {
            logger.error("[Firestore] Failed to decrypt shared wishlist \(wishlistID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw FirestoreError.decryptionFailed
        }

        let name = content["name"] as? String ?? ""
        let emojiRaw = content["coverEmoji"] as? String
        let coverEmoji: String? = (emojiRaw?.isEmpty == false) ? emojiRaw : nil
        let coverImageData = EncryptionService.dataField(content, "coverImageData")
        let ownerNameRaw = content["ownerName"] as? String
        let ownerName: String? = (ownerNameRaw?.isEmpty == false) ? ownerNameRaw : nil

        // 3. List & decrypt items subcollection
        let items = try await fetchSharedWishlistItems(wishlistID: wishlistID, key: key)

        // 4. Query memberships where wishlistID == wishlistID (plaintext metadata)
        let membersResults = try await runQuery(collectionId: "memberships", field: "wishlistID", op: "EQUAL", value: wishlistID)
        let members: [(userUID: String, role: String, userName: String?)] = membersResults.compactMap { entry in
            guard let doc = entry["document"] as? [String: Any],
                  let f = doc["fields"] as? [String: Any] else { return nil }
            let d = parseFields(f)
            let userNameRaw = d["userName"] as? String
            return (
                userUID: d["userUID"] as? String ?? "",
                role: d["role"] as? String ?? "viewer",
                userName: (userNameRaw?.isEmpty == false) ? userNameRaw : nil
            )
        }

        return SharedWishlistInfo(
            wishlistID: wishlistID,
            name: name,
            coverEmoji: coverEmoji,
            coverImageData: coverImageData,
            ownerUID: parsed["ownerUID"] as? String ?? "",
            ownerName: ownerName,
            gradientSeed: parsed["gradientSeed"] as? Int ?? 0,
            gradientHue: parsed["gradientHue"] as? Double,
            isArchived: parsed["isArchived"] as? Bool ?? false,
            members: members,
            items: items
        )
    }

    // MARK: - Fetch My Shared Wishlists

    /// Возвращает все shared-вишлисты, где пользователь является участником.
    /// Ключи извлекаются через `keyProvider(wishlistID)`. Вишлисты, для которых нет ключа
    /// или не получилось расшифровать, пропускаются.
    func fetchMySharedWishlists(userUID: String, keyProvider: (String) -> SymmetricKey?) async throws -> [SharedWishlistInfo] {
        let results = try await runQuery(collectionId: "memberships", field: "userUID", op: "EQUAL", value: userUID)

        let memberships = results.compactMap { entry -> (wishlistID: String, role: String)? in
            guard let doc = entry["document"] as? [String: Any],
                  let f = doc["fields"] as? [String: Any] else { return nil }
            let d = parseFields(f)
            guard let wID = d["wishlistID"] as? String else { return nil }
            let role = d["role"] as? String ?? "viewer"
            return (wishlistID: wID, role: role)
        }

        var list: [SharedWishlistInfo] = []
        for membership in memberships {
            guard let key = keyProvider(membership.wishlistID) else {
                logger.debug("[Firestore] No key for shared wishlist \(membership.wishlistID, privacy: .public), skipping")
                continue
            }
            guard let info = try? await fetchSharedWishlist(wishlistID: membership.wishlistID, key: key) else { continue }
            list.append(info)
        }
        return list
    }

    // MARK: - Memberships

    func joinWishlist(wishlistID: String, userUID: String, userName: String, role: String, canInvite: Bool = false) async throws {
        let membershipID = "\(userUID)_\(wishlistID)"
        let fields = toFields([
            "wishlistID": wishlistID,
            "userUID": userUID,
            "userName": userName,
            "role": role,
            "canInvite": canInvite as Any,
            "joinedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "memberships/\(membershipID)", body: ["fields": fields])
    }

    /// Обновить только userName в существующих memberships текущего пользователя.
    /// Используется при backfill после миграции имени.
    func updateMembershipUserName(wishlistID: String, userUID: String, userName: String) async throws {
        let membershipID = "\(userUID)_\(wishlistID)"
        let fields = toFields(["userName": userName])
        let _ = try await request(
            "PATCH",
            path: "memberships/\(membershipID)?updateMask.fieldPaths=userName",
            body: ["fields": fields]
        )
    }

    func fetchMyMemberships(userUID: String) async throws -> [(wishlistID: String, role: String, canInvite: Bool)] {
        let results = try await runQuery(collectionId: "memberships", field: "userUID", op: "EQUAL", value: userUID)
        return results.compactMap { entry in
            guard let doc = entry["document"] as? [String: Any],
                  let f = doc["fields"] as? [String: Any] else { return nil }
            let d = parseFields(f)
            guard let wID = d["wishlistID"] as? String else { return nil }
            let role = d["role"] as? String ?? "viewer"
            let canInvite = d["canInvite"] as? Bool ?? false
            return (wishlistID: wID, role: role, canInvite: canInvite)
        }
    }

    // MARK: - Invite Links

    /// Создаёт invite-link. Все user-facing preview-поля (wishlistName, wishlistEmoji, coverImageData, ownerName, itemCount)
    /// шифруются ключом wishlist'а — увидеть превью можно только применив ключ из URL fragment.
    func createInviteLink(
        shortID: String,
        wishlistID: String,
        wishlistName: String,
        wishlistEmoji: String?,
        wishlistCoverImageData: Data?,
        ownerName: String?,
        role: String,
        itemCount: Int,
        gradientSeed: Int,
        canInvite: Bool,
        expiresAt: Date?,
        key: SymmetricKey
    ) async throws {
        let payload = EncryptionService.packPayload([
            "wishlistName": wishlistName,
            "wishlistEmoji": wishlistEmoji,
            "coverImageData": wishlistCoverImageData,
            "ownerName": ownerName,
            "itemCount": itemCount
        ])
        let encrypted = try EncryptionService.encrypt(payload, using: key)

        var data: [String: Any?] = [
            "encryptedPayload": encrypted,
            "wishlistID": wishlistID,
            "role": role,
            "gradientSeed": gradientSeed as Any,
            "canInvite": canInvite as Any,
            "createdAt": Date() as Any
        ]
        if let expiresAt {
            data["expiresAt"] = expiresAt
        }
        let fields = toFields(data)
        let _ = try await request("PATCH", path: "inviteLinks/\(shortID)", body: ["fields": fields])
    }

    func resolveInviteLink(shortID: String, key: SymmetricKey) async throws -> ShareLinkInfo? {
        let doc: [String: Any]
        do {
            doc = try await request("GET", path: "inviteLinks/\(shortID)")
        } catch let error as FirestoreError {
            // NOT_FOUND returns 404 which becomes requestFailed
            if case .requestFailed(let msg) = error, msg.contains("NOT_FOUND") { return nil }
            throw error
        }
        guard let fields = doc["fields"] as? [String: Any] else { return nil }
        let parsed = parseFields(fields)

        // Check expiry
        if let tsString = parsed["expiresAt"] as? String {
            let formatter = ISO8601DateFormatter()
            if let expiryDate = formatter.date(from: tsString), expiryDate < .now {
                try? await request("DELETE", path: "inviteLinks/\(shortID)")
                return nil
            }
        }

        guard let payloadData = parsed["encryptedPayload"] as? Data else { return nil }
        let content: [String: Any]
        do {
            content = try EncryptionService.decrypt(payloadData, using: key)
        } catch {
            logger.error("[Firestore] Failed to decrypt invite link \(shortID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let wishlistName = content["wishlistName"] as? String ?? ""
        let wishlistEmojiRaw = content["wishlistEmoji"] as? String
        let wishlistEmoji: String? = (wishlistEmojiRaw?.isEmpty == false) ? wishlistEmojiRaw : nil
        let coverImageData = EncryptionService.dataField(content, "coverImageData")
        let ownerNameRaw = content["ownerName"] as? String
        let ownerName: String? = (ownerNameRaw?.isEmpty == false) ? ownerNameRaw : nil
        let itemCount: Int
        if let i = content["itemCount"] as? Int { itemCount = i }
        else if let d = content["itemCount"] as? Double { itemCount = Int(d) }
        else { itemCount = 0 }

        return ShareLinkInfo(
            wishlistID: parsed["wishlistID"] as? String ?? "",
            wishlistName: wishlistName,
            wishlistEmoji: wishlistEmoji,
            coverImageData: coverImageData,
            ownerName: ownerName,
            role: parsed["role"] as? String ?? "viewer",
            itemCount: itemCount,
            gradientSeed: parsed["gradientSeed"] as? Int ?? 0,
            canInvite: parsed["canInvite"] as? Bool ?? false
        )
    }

    func deleteAllInviteLinks(forWishlistID wishlistID: String) async {
        if let results = try? await runQuery(collectionId: "inviteLinks", field: "wishlistID", op: "EQUAL", value: wishlistID) {
            for entry in results {
                if let doc = entry["document"] as? [String: Any], let name = doc["name"] as? String {
                    let _ = try? await request("DELETE", path: "inviteLinks/\(documentID(from: name))")
                }
            }
        }
    }

    func deleteInviteLink(shortID: String) async throws {
        let _ = try await request("DELETE", path: "inviteLinks/\(shortID)")
    }

    // MARK: - Leave Wishlist

    func leaveWishlist(wishlistID: String, userUID: String) async throws {
        let membershipID = "\(userUID)_\(wishlistID)"
        let _ = try await request("DELETE", path: "memberships/\(membershipID)")
    }

    // MARK: - Membership management (owner-only operations)

    /// Обновить роль участника. Permission-check (owner-only) делается на уровне DataService —
    /// здесь только REST-вызов с маской `updateMask.fieldPaths=role`, чтобы не затереть остальные
    /// поля membership (canInvite/joinedAt/wishlistID/userUID).
    /// FIXME: server-side это сейчас не защищено — любой залогиненный юзер может PATCH membership
    /// через REST. См. Obsidian → projects/iwish/решения/2026-05-04-owner-role-management.md.
    func updateMembershipRole(wishlistID: String, userUID: String, role: String) async throws {
        let membershipID = "\(userUID)_\(wishlistID)"
        let fields = toFields([
            "role": role
        ])
        let _ = try await request(
            "PATCH",
            path: "memberships/\(membershipID)?updateMask.fieldPaths=role",
            body: ["fields": fields]
        )
    }

    /// Кикнуть участника из shared wishlist. Технически идентичен `leaveWishlist` —
    /// тот же DELETE на `memberships/{userUID}_{wishlistID}`. Отдельный метод нужен только
    /// для семантической ясности в callsites (kick от лица owner vs. self-leave).
    /// Permission-check (owner-only) выполняется в DataService.
    func kickMember(wishlistID: String, userUID: String) async throws {
        try await leaveWishlist(wishlistID: wishlistID, userUID: userUID)
    }

    // MARK: - Private Query Helpers

    /// Run a structured query on a top-level collection with a single field filter.
    private func runQuery(collectionId: String, field: String, op: String, value: String) async throws -> [[String: Any]] {
        let queryURL = "\(baseURL):runQuery"
        let body: [String: Any] = [
            "structuredQuery": [
                "from": [["collectionId": collectionId]],
                "where": [
                    "fieldFilter": [
                        "field": ["fieldPath": field],
                        "op": op,
                        "value": ["stringValue": value]
                    ]
                ]
            ]
        ]
        return try await requestArray(queryURL, body: body)
    }

    /// List all documents in a collection/subcollection using REST GET with pageToken pagination.
    private func listDocuments(parentPath: String) async throws -> [[String: Any]] {
        var allDocs: [[String: Any]] = []
        var pageToken: String? = nil

        repeat {
            var listURL = "\(baseURL)/\(parentPath)"
            var queryItems: [String] = ["pageSize=300"]
            if let token = pageToken {
                queryItems.append("pageToken=\(token)")
            }
            listURL += "?" + queryItems.joined(separator: "&")

            let result = try await request("GET", path: listURL)
            if let docs = result["documents"] as? [[String: Any]] {
                allDocs.append(contentsOf: docs)
            }
            pageToken = result["nextPageToken"] as? String
        } while pageToken != nil

        return allDocs
    }

    // MARK: - User Profile

    /// DEPRECATED: имя owner теперь хранится зашифрованно в invite link / shared wishlist payload.
    /// Stub оставлен чтобы не сломать существующие callsite'ы (`ParticipantsView`).
    /// TODO: replace callers with local `AuthService.userName` / data из `SharedWishlistInfo.ownerName`.
    func fetchUserName(uid: String) async -> String? {
        nil
    }

    /// Parse a Firestore REST item document with encryptedPayload into SharedItemInfo.
    /// Throws if no encryptedPayload or decryption fails — caller should swallow per-item failures.
    private func parseEncryptedItemFromDoc(_ doc: [String: Any], key: SymmetricKey) throws -> SharedItemInfo {
        let docName = doc["name"] as? String ?? ""
        let docID = documentID(from: docName)
        let fields = doc["fields"] as? [String: Any] ?? [:]
        let parsed = parseFields(fields)

        guard let payloadData = parsed["encryptedPayload"] as? Data else {
            throw FirestoreError.notFound
        }
        let content = try EncryptionService.decrypt(payloadData, using: key)

        func parseDouble(_ raw: Any?) -> Double? {
            if let d = raw as? Double { return d }
            if let i = raw as? Int { return Double(i) }
            return nil
        }
        let price = parseDouble(content["price"])
        let priceMax = parseDouble(content["priceMax"])
        let urlRaw = content["url"] as? String
        let url: String? = (urlRaw?.isEmpty == false) ? urlRaw : nil
        let emojiRaw = content["coverEmoji"] as? String
        let coverEmoji: String? = (emojiRaw?.isEmpty == false) ? emojiRaw : nil
        let addedByUIDRaw = content["addedByUID"] as? String
        let addedByUID: String? = (addedByUIDRaw?.isEmpty == false) ? addedByUIDRaw : nil
        let addedByNameRaw = content["addedByName"] as? String
        let addedByName: String? = (addedByNameRaw?.isEmpty == false) ? addedByNameRaw : nil

        let descRaw = content["description"] as? String
        let descriptionText: String? = (descRaw?.isEmpty == false) ? descRaw : nil
        let coverImageData = EncryptionService.dataField(content, "coverImageData")
        let linkMetadataData = EncryptionService.dataField(content, "linkMeta")
        let probISO = content["probationEndAt"] as? String
        let probationEndAt: Date? = probISO.flatMap { ISO8601DateFormatter().date(from: $0) }

        return SharedItemInfo(
            itemID: docID,
            name: content["name"] as? String ?? "",
            tier: content["tier"] as? String ?? "idea",
            price: price,
            priceMax: priceMax,
            currency: content["currency"] as? String ?? "RUB",
            url: url,
            coverEmoji: coverEmoji,
            coverImageData: coverImageData,
            linkMetadataData: linkMetadataData,
            descriptionText: descriptionText,
            probationEndAt: probationEndAt,
            sortIndex: parsed["sortIndex"] as? Double ?? 0,
            isArchived: parsed["isArchived"] as? Bool ?? false,
            addedByUID: addedByUID,
            addedByName: addedByName
        )
    }
}
