import Foundation
import FirebaseFirestore

@Observable
final class FirestoreService {
    private let db = Firestore.firestore()

    // MARK: - Types (same as old CloudKitSharingService for compat)

    struct ShareLinkInfo {
        let wishlistID: String
        let wishlistName: String
        let wishlistEmoji: String?
        let ownerName: String?
        let role: String
        let itemCount: Int
    }

    struct SharedWishlistInfo {
        let wishlistID: String
        let name: String
        let coverEmoji: String?
        let ownerUID: String
        let ownerName: String?
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
        case saveFailed(Error)
        case deleteFailed(Error)
        case fetchFailed(Error)
        case joinFailed(Error)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "Документ не найден"
            case .saveFailed(let error):
                return "Не удалось сохранить: \(error.localizedDescription)"
            case .deleteFailed(let error):
                return "Не удалось удалить: \(error.localizedDescription)"
            case .fetchFailed(let error):
                return "Не удалось загрузить: \(error.localizedDescription)"
            case .joinFailed(let error):
                return "Не удалось присоединиться: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Publish Wishlist

    func publishWishlist(
        id wishlistID: String,
        name: String,
        emoji: String?,
        ownerUID: String,
        ownerName: String?,
        items: [SharedItemInfo]
    ) async throws {
        let ref = db.collection("wishlists").document(wishlistID)
        try await ref.setData([
            "name": name,
            "coverEmoji": emoji ?? "",
            "ownerUID": ownerUID,
            "ownerName": ownerName ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        // Write items as subcollection
        let batch = db.batch()
        for item in items {
            let itemRef = ref.collection("items").document(item.itemID)
            batch.setData([
                "name": item.name,
                "tier": item.tier,
                "price": item.price as Any,
                "currency": item.currency,
                "url": item.url ?? "",
                "coverEmoji": item.coverEmoji ?? "",
                "sortIndex": item.sortIndex,
                "isArchived": item.isArchived,
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: itemRef, merge: true)
        }
        try await batch.commit()
    }

    // MARK: - Fetch Shared Wishlist

    func fetchSharedWishlist(wishlistID: String) async throws -> SharedWishlistInfo {
        let doc = try await db.collection("wishlists").document(wishlistID).getDocument()
        guard let data = doc.data() else { throw FirestoreError.notFound }

        // Fetch items
        let itemsSnapshot = try await db.collection("wishlists").document(wishlistID)
            .collection("items")
            .order(by: "sortIndex")
            .getDocuments()

        let items = itemsSnapshot.documents.map { parseItem($0) }

        // Fetch memberships
        let membersSnapshot = try await db.collection("memberships")
            .whereField("wishlistID", isEqualTo: wishlistID)
            .getDocuments()

        let members = membersSnapshot.documents.map { doc -> (userUID: String, role: String) in
            (doc.data()["userUID"] as? String ?? "", doc.data()["role"] as? String ?? "viewer")
        }

        return SharedWishlistInfo(
            wishlistID: wishlistID,
            name: data["name"] as? String ?? "",
            coverEmoji: (data["coverEmoji"] as? String)?.isEmpty == true ? nil : data["coverEmoji"] as? String,
            ownerUID: data["ownerUID"] as? String ?? "",
            ownerName: (data["ownerName"] as? String)?.isEmpty == true ? nil : data["ownerName"] as? String,
            members: members,
            items: items
        )
    }

    // MARK: - Update Items

    func updateItems(wishlistID: String, items: [SharedItemInfo]) async throws {
        let collectionRef = db.collection("wishlists").document(wishlistID).collection("items")

        // Get existing items to find deletions
        let existing = try await collectionRef.getDocuments()
        let existingIDs = Set(existing.documents.map(\.documentID))
        let newIDs = Set(items.map(\.itemID))

        let batch = db.batch()

        // Delete removed items
        for doc in existing.documents where !newIDs.contains(doc.documentID) {
            batch.deleteDocument(doc.reference)
        }

        // Upsert current items
        for item in items {
            let ref = collectionRef.document(item.itemID)
            batch.setData([
                "name": item.name,
                "tier": item.tier,
                "price": item.price as Any,
                "currency": item.currency,
                "url": item.url ?? "",
                "coverEmoji": item.coverEmoji ?? "",
                "sortIndex": item.sortIndex,
                "isArchived": item.isArchived,
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: ref, merge: true)
        }

        try await batch.commit()

        // Update wishlist timestamp
        try await db.collection("wishlists").document(wishlistID).updateData([
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Fetch My Shared Wishlists

    func fetchMySharedWishlists(userUID: String) async throws -> [SharedWishlistInfo] {
        let snapshot = try await db.collection("memberships")
            .whereField("userUID", isEqualTo: userUID)
            .getDocuments()

        let memberships = snapshot.documents.compactMap { doc -> (wishlistID: String, role: String)? in
            guard let wID = doc.data()["wishlistID"] as? String else { return nil }
            let role = doc.data()["role"] as? String ?? "viewer"
            return (wishlistID: wID, role: role)
        }

        var results: [SharedWishlistInfo] = []
        for membership in memberships {
            guard let info = try? await fetchSharedWishlist(wishlistID: membership.wishlistID) else {
                continue
            }
            results.append(info)
        }

        return results
    }

    // MARK: - Memberships

    func joinWishlist(wishlistID: String, userUID: String, role: String) async throws {
        let membershipID = "\(userUID)_\(wishlistID)"
        try await db.collection("memberships").document(membershipID).setData([
            "wishlistID": wishlistID,
            "userUID": userUID,
            "role": role,
            "joinedAt": FieldValue.serverTimestamp()
        ])
    }

    func fetchMyMemberships(userUID: String) async throws -> [(wishlistID: String, role: String)] {
        let snapshot = try await db.collection("memberships")
            .whereField("userUID", isEqualTo: userUID)
            .getDocuments()
        return snapshot.documents.compactMap { doc in
            guard let wID = doc.data()["wishlistID"] as? String else { return nil }
            let role = doc.data()["role"] as? String ?? "viewer"
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
        expiresAt: Date?
    ) async throws {
        var data: [String: Any] = [
            "wishlistID": wishlistID,
            "wishlistName": wishlistName,
            "wishlistEmoji": wishlistEmoji ?? "",
            "ownerName": ownerName ?? "",
            "role": role,
            "itemCount": itemCount,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let expiresAt {
            data["expiresAt"] = Timestamp(date: expiresAt)
        }
        try await db.collection("inviteLinks").document(shortID).setData(data)
    }

    func resolveInviteLink(shortID: String) async throws -> ShareLinkInfo? {
        let doc = try await db.collection("inviteLinks").document(shortID).getDocument()
        guard let data = doc.data() else { return nil }

        // Check expiry
        if let ts = data["expiresAt"] as? Timestamp, ts.dateValue() < .now {
            try? await doc.reference.delete()
            return nil
        }

        return ShareLinkInfo(
            wishlistID: data["wishlistID"] as? String ?? "",
            wishlistName: data["wishlistName"] as? String ?? "",
            wishlistEmoji: (data["wishlistEmoji"] as? String)?.isEmpty == true ? nil : data["wishlistEmoji"] as? String,
            ownerName: (data["ownerName"] as? String)?.isEmpty == true ? nil : data["ownerName"] as? String,
            role: data["role"] as? String ?? "viewer",
            itemCount: data["itemCount"] as? Int ?? 0
        )
    }

    func deleteInviteLink(shortID: String) async throws {
        try await db.collection("inviteLinks").document(shortID).delete()
    }

    // MARK: - Real-time Listeners

    func listenToItems(
        wishlistID: String,
        onChange: @escaping ([SharedItemInfo]) -> Void
    ) -> ListenerRegistration {
        return db.collection("wishlists").document(wishlistID).collection("items")
            .order(by: "sortIndex")
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                let items = docs.map { self.parseItem($0) }
                onChange(items)
            }
    }

    func listenToWishlist(
        wishlistID: String,
        onChange: @escaping (SharedWishlistInfo?) -> Void
    ) -> ListenerRegistration {
        return db.collection("wishlists").document(wishlistID)
            .addSnapshotListener { snapshot, error in
                guard let doc = snapshot, let data = doc.data() else {
                    onChange(nil)
                    return
                }
                let info = SharedWishlistInfo(
                    wishlistID: wishlistID,
                    name: data["name"] as? String ?? "",
                    coverEmoji: (data["coverEmoji"] as? String)?.isEmpty == true ? nil : data["coverEmoji"] as? String,
                    ownerUID: data["ownerUID"] as? String ?? "",
                    ownerName: (data["ownerName"] as? String)?.isEmpty == true ? nil : data["ownerName"] as? String,
                    members: [],
                    items: []
                )
                onChange(info)
            }
    }

    // MARK: - Delete

    func deleteSharedWishlist(wishlistID: String) async throws {
        // Delete items subcollection
        let items = try await db.collection("wishlists").document(wishlistID)
            .collection("items")
            .getDocuments()
        let batch = db.batch()
        for doc in items.documents {
            batch.deleteDocument(doc.reference)
        }
        batch.deleteDocument(db.collection("wishlists").document(wishlistID))
        try await batch.commit()

        // Delete memberships
        let memberships = try await db.collection("memberships")
            .whereField("wishlistID", isEqualTo: wishlistID)
            .getDocuments()
        for doc in memberships.documents {
            try await doc.reference.delete()
        }
    }

    // MARK: - Helpers

    private func parseItem(_ doc: DocumentSnapshot) -> SharedItemInfo {
        let data = doc.data() ?? [:]
        return SharedItemInfo(
            itemID: doc.documentID,
            name: data["name"] as? String ?? "",
            tier: data["tier"] as? String ?? "idea",
            price: data["price"] as? Double,
            currency: data["currency"] as? String ?? "RUB",
            url: (data["url"] as? String)?.isEmpty == true ? nil : data["url"] as? String,
            coverEmoji: (data["coverEmoji"] as? String)?.isEmpty == true ? nil : data["coverEmoji"] as? String,
            sortIndex: data["sortIndex"] as? Double ?? 0,
            isArchived: data["isArchived"] as? Bool ?? false
        )
    }
}
