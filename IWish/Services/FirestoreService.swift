import Foundation
import FirebaseAuth

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
        let ownerName: String?
        let role: String
        let itemCount: Int
        let gradientSeed: Int
    }

    struct SharedWishlistInfo {
        let wishlistID: String
        let name: String
        let coverEmoji: String?
        let ownerUID: String
        let ownerName: String?
        let gradientSeed: Int
        let members: [(userUID: String, role: String)]
        let items: [SharedItemInfo]
    }

    struct SharedItemInfo {
        let itemID: String
        let name: String
        let tier: String
        let price: Double?
        let currency: String
        let url: String?
        let coverEmoji: String?
        let sortIndex: Double
        let isArchived: Bool
    }

    enum FirestoreError: LocalizedError {
        case notFound
        case notAuthenticated
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "Документ не найден"
            case .notAuthenticated:
                return "Необходима авторизация"
            case .requestFailed(let msg):
                return "Ошибка запроса: \(msg)"
            }
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
        let token = try await getAuthToken()
        var urlString = path.hasPrefix("http") ? path : "\(baseURL)/\(path)"
        // Trim trailing slash
        if urlString.hasSuffix("/") { urlString = String(urlString.dropLast()) }
        guard let url = URL(string: urlString) else {
            throw FirestoreError.requestFailed("Invalid URL: \(urlString)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
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
        let token = try await getAuthToken()
        let urlString = path.hasPrefix("http") ? path : "\(baseURL)/\(path)"
        guard let url = URL(string: urlString) else {
            throw FirestoreError.requestFailed("Invalid URL: \(urlString)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
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

    func createPersonalWishlist(uid: String, wishlistID: String, name: String, emoji: String?, gradientSeed: Int) async throws {
        let fields = toFields([
            "name": name,
            "coverEmoji": emoji ?? "",
            "gradientSeed": gradientSeed as Any,
            "createdAt": Date() as Any,
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "users/\(uid)/wishlists/\(wishlistID)", body: ["fields": fields])
    }

    func updatePersonalWishlist(uid: String, wishlistID: String, name: String, emoji: String?) async throws {
        let fields = toFields([
            "name": name,
            "coverEmoji": emoji ?? "",
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "users/\(uid)/wishlists/\(wishlistID)?updateMask.fieldPaths=name&updateMask.fieldPaths=coverEmoji&updateMask.fieldPaths=updatedAt", body: ["fields": fields])
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

    func fetchPersonalWishlists(uid: String) async throws -> [(id: String, name: String, emoji: String?, gradientSeed: Int)] {
        let docs = try await listDocuments(parentPath: "users/\(uid)/wishlists")
        return docs.compactMap { doc -> (id: String, name: String, emoji: String?, gradientSeed: Int)? in
            guard let name = doc["name"] as? String else { return nil }
            let docID = documentID(from: name)
            guard let fields = doc["fields"] as? [String: Any] else { return nil }
            let data = parseFields(fields)
            let emoji = (data["coverEmoji"] as? String)?.isEmpty == true ? nil : data["coverEmoji"] as? String
            let seed: Int
            if let s = data["gradientSeed"] as? Int {
                seed = s
            } else {
                seed = 0
            }
            return (id: docID, name: data["name"] as? String ?? "", emoji: emoji, gradientSeed: seed)
        }
    }

    // MARK: - Personal Items (users/{uid}/wishlists/{wid}/items)

    func createPersonalItem(uid: String, wishlistID: String, itemID: String, name: String, tier: String, price: Double?, currency: String, url: String?, emoji: String?, sortIndex: Double) async throws {
        let fields = toFields([
            "name": name,
            "tier": tier,
            "price": price as Any?,
            "currency": currency,
            "url": url ?? "",
            "coverEmoji": emoji ?? "",
            "sortIndex": sortIndex as Any,
            "isArchived": false as Any,
            "createdAt": Date() as Any,
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "users/\(uid)/wishlists/\(wishlistID)/items/\(itemID)", body: ["fields": fields])
    }

    func updatePersonalItem(uid: String, wishlistID: String, itemID: String, name: String, tier: String, price: Double?, currency: String, url: String?, emoji: String?, sortIndex: Double, isArchived: Bool) async throws {
        let fields = toFields([
            "name": name,
            "tier": tier,
            "price": price as Any?,
            "currency": currency,
            "url": url ?? "",
            "coverEmoji": emoji ?? "",
            "sortIndex": sortIndex as Any,
            "isArchived": isArchived as Any,
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "users/\(uid)/wishlists/\(wishlistID)/items/\(itemID)", body: ["fields": fields])
    }

    func deletePersonalItem(uid: String, wishlistID: String, itemID: String) async throws {
        let _ = try await request("DELETE", path: "users/\(uid)/wishlists/\(wishlistID)/items/\(itemID)")
    }

    func fetchPersonalItems(uid: String, wishlistID: String) async throws -> [SharedItemInfo] {
        let docs = try await listDocuments(parentPath: "users/\(uid)/wishlists/\(wishlistID)/items")
        return docs.map { parseItemFromDoc($0) }.sorted { $0.sortIndex < $1.sortIndex }
    }

    // MARK: - Shared Wishlists (shared_wishlists/)

    func createSharedWishlist(wishlistID: String, name: String, emoji: String?, gradientSeed: Int, ownerUID: String, ownerName: String?, items: [SharedItemInfo]) async throws {
        // 1. Write the wishlist document
        let wishlistFields = toFields([
            "name": name,
            "coverEmoji": emoji ?? "",
            "gradientSeed": gradientSeed as Any,
            "ownerUID": ownerUID,
            "ownerName": ownerName ?? "",
            "createdAt": Date() as Any,
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "shared_wishlists/\(wishlistID)", body: ["fields": wishlistFields])

        // 2. Batch write all items
        if !items.isEmpty {
            var writes: [[String: Any]] = []
            for item in items {
                let itemFields = toFields([
                    "name": item.name,
                    "tier": item.tier,
                    "price": item.price as Any?,
                    "currency": item.currency,
                    "url": item.url ?? "",
                    "coverEmoji": item.coverEmoji ?? "",
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

    func updateSharedWishlist(wishlistID: String, name: String, emoji: String?) async throws {
        let fields = toFields([
            "name": name,
            "coverEmoji": emoji ?? "",
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "shared_wishlists/\(wishlistID)?updateMask.fieldPaths=name&updateMask.fieldPaths=coverEmoji&updateMask.fieldPaths=updatedAt", body: ["fields": fields])
    }

    func fetchSharedWishlistItems(wishlistID: String) async throws -> [SharedItemInfo] {
        let docs = try await listDocuments(parentPath: "shared_wishlists/\(wishlistID)/items")
        return docs.map { parseItemFromDoc($0) }.sorted { $0.sortIndex < $1.sortIndex }
    }

    // MARK: - Shared Items CRUD (shared_wishlists/{wid}/items)

    func createSharedItem(wishlistID: String, itemID: String, name: String, tier: String, price: Double?, currency: String, url: String?, emoji: String?, sortIndex: Double) async throws {
        let fields = toFields([
            "name": name,
            "tier": tier,
            "price": price as Any?,
            "currency": currency,
            "url": url ?? "",
            "coverEmoji": emoji ?? "",
            "sortIndex": sortIndex as Any,
            "isArchived": false as Any,
            "createdAt": Date() as Any,
            "updatedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "shared_wishlists/\(wishlistID)/items/\(itemID)", body: ["fields": fields])
    }

    func updateSharedItem(wishlistID: String, itemID: String, name: String, tier: String, price: Double?, currency: String, url: String?, emoji: String?, sortIndex: Double, isArchived: Bool) async throws {
        let fields = toFields([
            "name": name,
            "tier": tier,
            "price": price as Any?,
            "currency": currency,
            "url": url ?? "",
            "coverEmoji": emoji ?? "",
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
        // 1. Delete items + wishlist
        let itemsDocs = try await listDocuments(parentPath: "shared_wishlists/\(wishlistID)/items")
        var writes: [[String: Any]] = []
        for itemDoc in itemsDocs {
            if let name = itemDoc["name"] as? String {
                writes.append(["delete": name])
            }
        }
        writes.append(["delete": fullDocName("shared_wishlists/\(wishlistID)")])
        if !writes.isEmpty {
            let commitURL = "\(baseURL):commit"
            let _ = try await request("POST", path: commitURL, body: ["writes": writes])
        }

        // 2. Delete memberships
        let memberResults = try await runQuery(collectionId: "memberships", field: "wishlistID", op: "EQUAL", value: wishlistID)
        for entry in memberResults {
            if let doc = entry["document"] as? [String: Any], let name = doc["name"] as? String {
                let docID = documentID(from: name)
                let _ = try? await request("DELETE", path: "memberships/\(docID)")
            }
        }

        // 3. Delete invite links referencing this wishlist
        let inviteResults = try await runQuery(collectionId: "inviteLinks", field: "wishlistID", op: "EQUAL", value: wishlistID)
        for entry in inviteResults {
            if let doc = entry["document"] as? [String: Any], let name = doc["name"] as? String {
                let docID = documentID(from: name)
                let _ = try? await request("DELETE", path: "inviteLinks/\(docID)")
            }
        }
    }

    // MARK: - Fetch Shared Wishlist

    func fetchSharedWishlist(wishlistID: String) async throws -> SharedWishlistInfo {
        // 1. Get wishlist document from shared_wishlists
        let doc = try await request("GET", path: "shared_wishlists/\(wishlistID)")
        guard let fields = doc["fields"] as? [String: Any] else {
            throw FirestoreError.notFound
        }
        let data = parseFields(fields)

        // 2. List items subcollection
        let itemsDocs = try await listDocuments(parentPath: "shared_wishlists/\(wishlistID)/items")
        let items = itemsDocs.map { parseItemFromDoc($0) }.sorted { $0.sortIndex < $1.sortIndex }

        // 3. Query memberships where wishlistID == wishlistID
        let membersResults = try await runQuery(collectionId: "memberships", field: "wishlistID", op: "EQUAL", value: wishlistID)
        let members = membersResults.compactMap { entry -> (userUID: String, role: String)? in
            guard let doc = entry["document"] as? [String: Any],
                  let f = doc["fields"] as? [String: Any] else { return nil }
            let d = parseFields(f)
            return (d["userUID"] as? String ?? "", d["role"] as? String ?? "viewer")
        }

        return SharedWishlistInfo(
            wishlistID: wishlistID,
            name: data["name"] as? String ?? "",
            coverEmoji: (data["coverEmoji"] as? String)?.isEmpty == true ? nil : data["coverEmoji"] as? String,
            ownerUID: data["ownerUID"] as? String ?? "",
            ownerName: (data["ownerName"] as? String)?.isEmpty == true ? nil : data["ownerName"] as? String,
            gradientSeed: data["gradientSeed"] as? Int ?? 0,
            members: members,
            items: items
        )
    }

    // MARK: - Fetch My Shared Wishlists

    func fetchMySharedWishlists(userUID: String) async throws -> [SharedWishlistInfo] {
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
            guard let info = try? await fetchSharedWishlist(wishlistID: membership.wishlistID) else { continue }
            list.append(info)
        }
        return list
    }

    // MARK: - Memberships

    func joinWishlist(wishlistID: String, userUID: String, role: String) async throws {
        let membershipID = "\(userUID)_\(wishlistID)"
        let fields = toFields([
            "wishlistID": wishlistID,
            "userUID": userUID,
            "role": role,
            "joinedAt": Date() as Any
        ])
        let _ = try await request("PATCH", path: "memberships/\(membershipID)", body: ["fields": fields])
    }

    func fetchMyMemberships(userUID: String) async throws -> [(wishlistID: String, role: String)] {
        let results = try await runQuery(collectionId: "memberships", field: "userUID", op: "EQUAL", value: userUID)
        return results.compactMap { entry in
            guard let doc = entry["document"] as? [String: Any],
                  let f = doc["fields"] as? [String: Any] else { return nil }
            let d = parseFields(f)
            guard let wID = d["wishlistID"] as? String else { return nil }
            let role = d["role"] as? String ?? "viewer"
            return (wishlistID: wID, role: role)
        }
    }

    // MARK: - Invite Links

    func createInviteLink(
        shortID: String,
        wishlistID: String,
        wishlistName: String,
        wishlistEmoji: String?,
        ownerName: String?,
        role: String,
        itemCount: Int,
        gradientSeed: Int,
        expiresAt: Date?
    ) async throws {
        var data: [String: Any?] = [
            "wishlistID": wishlistID,
            "wishlistName": wishlistName,
            "wishlistEmoji": wishlistEmoji ?? "",
            "ownerName": ownerName ?? "",
            "role": role,
            "itemCount": itemCount,
            "gradientSeed": gradientSeed as Any,
            "createdAt": Date() as Any
        ]
        if let expiresAt {
            data["expiresAt"] = expiresAt
        }
        let fields = toFields(data)
        let _ = try await request("PATCH", path: "inviteLinks/\(shortID)", body: ["fields": fields])
    }

    func resolveInviteLink(shortID: String) async throws -> ShareLinkInfo? {
        let doc: [String: Any]
        do {
            doc = try await request("GET", path: "inviteLinks/\(shortID)")
        } catch let error as FirestoreError {
            // NOT_FOUND returns 404 which becomes requestFailed
            if case .requestFailed(let msg) = error, msg.contains("NOT_FOUND") { return nil }
            throw error
        }
        guard let fields = doc["fields"] as? [String: Any] else { return nil }
        let data = parseFields(fields)

        // Check expiry
        if let tsString = data["expiresAt"] as? String {
            let formatter = ISO8601DateFormatter()
            if let expiryDate = formatter.date(from: tsString), expiryDate < .now {
                try? await request("DELETE", path: "inviteLinks/\(shortID)")
                return nil
            }
        }

        return ShareLinkInfo(
            wishlistID: data["wishlistID"] as? String ?? "",
            wishlistName: data["wishlistName"] as? String ?? "",
            wishlistEmoji: (data["wishlistEmoji"] as? String)?.isEmpty == true ? nil : data["wishlistEmoji"] as? String,
            ownerName: (data["ownerName"] as? String)?.isEmpty == true ? nil : data["ownerName"] as? String,
            role: data["role"] as? String ?? "viewer",
            itemCount: data["itemCount"] as? Int ?? 0,
            gradientSeed: data["gradientSeed"] as? Int ?? 0
        )
    }

    func deleteInviteLink(shortID: String) async throws {
        let _ = try await request("DELETE", path: "inviteLinks/\(shortID)")
    }

    // MARK: - Leave Wishlist

    func leaveWishlist(wishlistID: String, userUID: String) async throws {
        let membershipID = "\(userUID)_\(wishlistID)"
        let _ = try await request("DELETE", path: "memberships/\(membershipID)")
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

    func fetchUserName(uid: String) async -> String? {
        guard let doc = try? await request("GET", path: "users/\(uid)"),
              let fields = doc["fields"] as? [String: Any] else { return nil }
        let data = parseFields(fields)
        let name = data["name"] as? String
        return (name?.isEmpty == true) ? nil : name
    }

    /// Parse a Firestore REST document dict into SharedItemInfo.
    private func parseItemFromDoc(_ doc: [String: Any]) -> SharedItemInfo {
        let docName = doc["name"] as? String ?? ""
        let docID = documentID(from: docName)
        let fields = doc["fields"] as? [String: Any] ?? [:]
        let data = parseFields(fields)
        let rawPrice = data["price"]
        let price: Double?
        if let d = rawPrice as? Double {
            price = d
        } else if let i = rawPrice as? Int {
            price = Double(i)
        } else {
            price = nil
        }
        return SharedItemInfo(
            itemID: docID,
            name: data["name"] as? String ?? "",
            tier: data["tier"] as? String ?? "idea",
            price: price,
            currency: data["currency"] as? String ?? "RUB",
            url: (data["url"] as? String)?.isEmpty == true ? nil : data["url"] as? String,
            coverEmoji: (data["coverEmoji"] as? String)?.isEmpty == true ? nil : data["coverEmoji"] as? String,
            sortIndex: data["sortIndex"] as? Double ?? 0,
            isArchived: data["isArchived"] as? Bool ?? false
        )
    }
}
