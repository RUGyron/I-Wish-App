import CloudKit
import Foundation

@Observable
final class CloudKitSharingService {

    // MARK: - Types

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
        let ownerRecordID: String
        let ownerName: String?
        let members: [(recordID: String, role: String)]
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

    enum SharingError: LocalizedError {
        case invalidShareURL
        case shareLinkNotFound
        case wishlistNotFound
        case saveFailed(Error)
        case deleteFailed(Error)
        case fetchFailed(Error)
        case joinFailed(Error)
        case recordConflict

        var errorDescription: String? {
            switch self {
            case .invalidShareURL:
                return "Ссылка на шаринг недействительна."
            case .shareLinkNotFound:
                return "Приглашение не найдено или истекло."
            case .wishlistNotFound:
                return "Список не найден."
            case .saveFailed(let error):
                return "Не удалось сохранить: \(error.localizedDescription)"
            case .deleteFailed(let error):
                return "Не удалось удалить: \(error.localizedDescription)"
            case .fetchFailed(let error):
                return "Не удалось загрузить: \(error.localizedDescription)"
            case .joinFailed(let error):
                return "Не удалось присоединиться: \(error.localizedDescription)"
            case .recordConflict:
                return "Конфликт записи. Попробуйте ещё раз."
            }
        }
    }

    // MARK: - Record Types

    private static let shareLinkRecordType = "ShareLink"
    private static let sharedWishlistRecordType = "SharedWishlist"
    private static let sharedItemRecordType = "SharedItem"
    private static let membershipRecordType = "SharedMembership"

    // MARK: - Properties

    private nonisolated let container = CKContainer(
        identifier: ModelContainerFactory.cloudKitContainerID
    )

    private nonisolated var publicDB: CKDatabase {
        container.publicCloudDatabase
    }

    // MARK: - Publish Wishlist

    /// Creates SharedWishlist + SharedItem records in PublicDB.
    nonisolated func publishWishlist(
        id wishlistID: String,
        name: String,
        emoji: String?,
        ownerRecordID: String,
        ownerName: String?,
        items: [SharedItemInfo],
        role: String
    ) async throws {
        // 1. Build SharedWishlist record
        let wishlistRecordID = CKRecord.ID(recordName: wishlistID)
        let wishlistRecord = CKRecord(
            recordType: Self.sharedWishlistRecordType,
            recordID: wishlistRecordID
        )
        wishlistRecord["wishlistID"] = wishlistID as CKRecordValue
        wishlistRecord["name"] = name as CKRecordValue
        wishlistRecord["coverEmoji"] = (emoji ?? "") as CKRecordValue
        wishlistRecord["ownerRecordID"] = ownerRecordID as CKRecordValue
        wishlistRecord["ownerName"] = (ownerName ?? "") as CKRecordValue
        wishlistRecord["memberRecordIDs"] = [ownerRecordID] as CKRecordValue
        wishlistRecord["memberRoles"] = [role] as CKRecordValue
        wishlistRecord["updatedAt"] = Date.now as CKRecordValue

        // 2. Build SharedItem records
        var recordsToSave: [CKRecord] = [wishlistRecord]

        for item in items {
            let itemRecordID = CKRecord.ID(recordName: item.itemID)
            let itemRecord = CKRecord(
                recordType: Self.sharedItemRecordType,
                recordID: itemRecordID
            )
            itemRecord["itemID"] = item.itemID as CKRecordValue
            itemRecord["wishlistID"] = wishlistID as CKRecordValue
            itemRecord["name"] = item.name as CKRecordValue
            itemRecord["tier"] = item.tier as CKRecordValue
            if let price = item.price {
                itemRecord["price"] = price as CKRecordValue
            }
            itemRecord["currency"] = item.currency as CKRecordValue
            itemRecord["url"] = (item.url ?? "") as CKRecordValue
            itemRecord["coverEmoji"] = (item.coverEmoji ?? "") as CKRecordValue
            itemRecord["sortIndex"] = item.sortIndex as CKRecordValue
            itemRecord["isArchived"] = (item.isArchived ? 1 : 0) as CKRecordValue
            itemRecord["updatedAt"] = Date.now as CKRecordValue

            recordsToSave.append(itemRecord)
        }

        // 3. Save all records
        do {
            let (saveResults, _) = try await publicDB.modifyRecords(
                saving: recordsToSave,
                deleting: [],
                savePolicy: .allKeys
            )
            for (_, result) in saveResults {
                _ = try result.get()
            }
        } catch {
            throw SharingError.saveFailed(error)
        }
    }

    // MARK: - Fetch Shared Wishlist

    /// Fetches a SharedWishlist and its SharedItems from PublicDB.
    nonisolated func fetchSharedWishlist(
        wishlistID: String
    ) async throws -> SharedWishlistInfo {
        // 1. Fetch the SharedWishlist record by recordName
        let wishlistRecordID = CKRecord.ID(recordName: wishlistID)
        let wishlistRecord: CKRecord
        do {
            wishlistRecord = try await publicDB.record(for: wishlistRecordID)
        } catch {
            throw SharingError.wishlistNotFound
        }

        // 2. Fetch all SharedItems for this wishlistID
        let predicate = NSPredicate(format: "wishlistID == %@", wishlistID)
        let query = CKQuery(recordType: Self.sharedItemRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: true)]

        var allItems: [SharedItemInfo] = []
        var cursor: CKQueryOperation.Cursor?

        let (firstResults, firstCursor) = try await publicDB.records(matching: query)
        for (_, result) in firstResults {
            if let record = try? result.get() {
                allItems.append(sharedItemInfo(from: record))
            }
        }
        cursor = firstCursor

        while let activeCursor = cursor {
            let (moreResults, nextCursor) = try await publicDB.records(
                continuingMatchFrom: activeCursor
            )
            for (_, result) in moreResults {
                if let record = try? result.get() {
                    allItems.append(sharedItemInfo(from: record))
                }
            }
            cursor = nextCursor
        }

        // 3. Build members from SharedMembership records
        let memberPredicate = NSPredicate(format: "wishlistID == %@", wishlistID)
        let memberQuery = CKQuery(recordType: Self.membershipRecordType, predicate: memberPredicate)
        var members: [(recordID: String, role: String)] = []
        if let (memberResults, _) = try? await publicDB.records(matching: memberQuery) {
            for (_, result) in memberResults {
                if let rec = try? result.get() {
                    let uid = rec["userRecordID"] as? String ?? ""
                    let role = rec["role"] as? String ?? "viewer"
                    if !uid.isEmpty { members.append((recordID: uid, role: role)) }
                }
            }
        }

        let name = wishlistRecord["name"] as? String ?? ""
        let emoji = wishlistRecord["coverEmoji"] as? String
        let ownerRecordID = wishlistRecord["ownerRecordID"] as? String ?? ""
        let ownerName = wishlistRecord["ownerName"] as? String

        return SharedWishlistInfo(
            wishlistID: wishlistID,
            name: name,
            coverEmoji: emoji?.isEmpty == true ? nil : emoji,
            ownerRecordID: ownerRecordID,
            ownerName: ownerName?.isEmpty == true ? nil : ownerName,
            members: members,
            items: allItems
        )
    }

    // MARK: - Join Wishlist

    /// Adds userRecordID to memberRecordIDs array of the SharedWishlist.
    /// Joins a shared wishlist by creating a SharedMembership record owned by the receiver.
    /// This avoids PublicDB permission issues (only creator can modify their own records).
    nonisolated func joinWishlist(
        wishlistID: String,
        userRecordID: String,
        role: String = "viewer"
    ) async throws {
        // Each user creates their own membership record — no permission conflict
        let membershipID = CKRecord.ID(recordName: "\(wishlistID)_\(userRecordID)")
        let record = CKRecord(recordType: Self.membershipRecordType, recordID: membershipID)
        record["wishlistID"] = wishlistID as CKRecordValue
        record["userRecordID"] = userRecordID as CKRecordValue
        record["role"] = role as CKRecordValue
        record["joinedAt"] = Date.now as CKRecordValue

        do {
            _ = try await publicDB.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Already joined — no-op
        } catch {
            throw SharingError.joinFailed(error)
        }
    }

    // MARK: - Update Shared Items

    /// Updates SharedItem records in PublicDB (creates new ones, updates existing).
    nonisolated func updateSharedItems(
        wishlistID: String,
        items: [SharedItemInfo]
    ) async throws {
        // 1. Fetch existing SharedItems for this wishlist
        let predicate = NSPredicate(format: "wishlistID == %@", wishlistID)
        let query = CKQuery(recordType: Self.sharedItemRecordType, predicate: predicate)

        var existingRecordIDs: [CKRecord.ID] = []
        let (results, _) = try await publicDB.records(matching: query)
        for (recordID, _) in results {
            existingRecordIDs.append(recordID)
        }

        // 2. Build set of new item IDs
        let newItemIDs = Set(items.map(\.itemID))

        // 3. Determine which existing records to delete (no longer in items list)
        let recordIDsToDelete = existingRecordIDs.filter { !newItemIDs.contains($0.recordName) }

        // 4. Build records to save
        var recordsToSave: [CKRecord] = []
        for item in items {
            let itemRecordID = CKRecord.ID(recordName: item.itemID)
            let itemRecord = CKRecord(
                recordType: Self.sharedItemRecordType,
                recordID: itemRecordID
            )
            itemRecord["itemID"] = item.itemID as CKRecordValue
            itemRecord["wishlistID"] = wishlistID as CKRecordValue
            itemRecord["name"] = item.name as CKRecordValue
            itemRecord["tier"] = item.tier as CKRecordValue
            if let price = item.price {
                itemRecord["price"] = price as CKRecordValue
            }
            itemRecord["currency"] = item.currency as CKRecordValue
            itemRecord["url"] = (item.url ?? "") as CKRecordValue
            itemRecord["coverEmoji"] = (item.coverEmoji ?? "") as CKRecordValue
            itemRecord["sortIndex"] = item.sortIndex as CKRecordValue
            itemRecord["isArchived"] = (item.isArchived ? 1 : 0) as CKRecordValue
            itemRecord["updatedAt"] = Date.now as CKRecordValue

            recordsToSave.append(itemRecord)
        }

        // 5. Save + delete in one batch
        do {
            let (saveResults, _) = try await publicDB.modifyRecords(
                saving: recordsToSave,
                deleting: recordIDsToDelete,
                savePolicy: .allKeys
            )
            for (_, result) in saveResults {
                _ = try result.get()
            }
        } catch {
            throw SharingError.saveFailed(error)
        }
    }

    // MARK: - Fetch My Shared Wishlists

    /// Returns all SharedWishlists where userRecordID is in memberRecordIDs.
    /// Fetches wishlists where the user is a member (via SharedMembership records).
    nonisolated func fetchMySharedWishlists(
        userRecordID: String
    ) async throws -> [SharedWishlistInfo] {
        // 1. Find all SharedMembership records for this user
        let predicate = NSPredicate(format: "userRecordID == %@", userRecordID)
        let query = CKQuery(recordType: Self.membershipRecordType, predicate: predicate)

        var wishlistIDs: [(id: String, role: String)] = []
        let (membershipResults, _) = try await publicDB.records(matching: query)
        for (_, result) in membershipResults {
            if let record = try? result.get() {
                let wID = record["wishlistID"] as? String ?? ""
                let role = record["role"] as? String ?? "viewer"
                if !wID.isEmpty { wishlistIDs.append((id: wID, role: role)) }
            }
        }

        // 2. For each wishlist, fetch the SharedWishlist + items
        var results: [SharedWishlistInfo] = []
        for membership in wishlistIDs {
            guard let info = try? await fetchSharedWishlist(wishlistID: membership.id) else {
                continue
            }
            results.append(info)
        }

        return results
    }

    // MARK: - Remove From Shared Wishlist

    /// Removes a member from the SharedWishlist's memberRecordIDs array.
    nonisolated func removeFromSharedWishlist(
        wishlistID: String,
        userRecordID: String
    ) async throws {
        try await retryOnConflict { [self] in
            let recordID = CKRecord.ID(recordName: wishlistID)
            let record: CKRecord
            do {
                record = try await publicDB.record(for: recordID)
            } catch {
                throw SharingError.wishlistNotFound
            }

            var memberIDs = record["memberRecordIDs"] as? [String] ?? []
            var memberRoles = record["memberRoles"] as? [String] ?? []

            guard let index = memberIDs.firstIndex(of: userRecordID) else { return }

            memberIDs.remove(at: index)
            if index < memberRoles.count {
                memberRoles.remove(at: index)
            }

            record["memberRecordIDs"] = memberIDs as CKRecordValue
            record["memberRoles"] = memberRoles as CKRecordValue
            record["updatedAt"] = Date.now as CKRecordValue

            do {
                let (saveResults, _) = try await publicDB.modifyRecords(
                    saving: [record],
                    deleting: [],
                    savePolicy: .changedKeys
                )
                for (_, result) in saveResults {
                    _ = try result.get()
                }
            } catch {
                throw SharingError.saveFailed(error)
            }
        }
    }

    // MARK: - Delete Shared Wishlist

    /// Deletes the SharedWishlist + all its SharedItems from PublicDB.
    nonisolated func deleteSharedWishlist(wishlistID: String) async throws {
        // 1. Collect item record IDs
        let predicate = NSPredicate(format: "wishlistID == %@", wishlistID)
        let query = CKQuery(recordType: Self.sharedItemRecordType, predicate: predicate)

        var recordIDsToDelete: [CKRecord.ID] = []

        var cursor: CKQueryOperation.Cursor?
        let (firstResults, firstCursor) = try await publicDB.records(matching: query)
        for (recordID, _) in firstResults {
            recordIDsToDelete.append(recordID)
        }
        cursor = firstCursor

        while let activeCursor = cursor {
            let (moreResults, nextCursor) = try await publicDB.records(
                continuingMatchFrom: activeCursor
            )
            for (recordID, _) in moreResults {
                recordIDsToDelete.append(recordID)
            }
            cursor = nextCursor
        }

        // 2. Add the wishlist record itself
        let wishlistRecordID = CKRecord.ID(recordName: wishlistID)
        recordIDsToDelete.append(wishlistRecordID)

        // 3. Delete all in one batch
        do {
            try await publicDB.modifyRecords(
                saving: [],
                deleting: recordIDsToDelete
            )
        } catch {
            throw SharingError.deleteFailed(error)
        }
    }

    // MARK: - ShareLink CRUD (Public DB)

    nonisolated func createShareLink(
        shortID: String,
        wishlistID: String,
        wishlistName: String,
        wishlistEmoji: String?,
        ownerName: String?,
        role: ShareRole,
        itemCount: Int,
        expiresAt: Date
    ) async throws {
        let recordID = CKRecord.ID(recordName: shortID)
        let record = CKRecord(recordType: Self.shareLinkRecordType, recordID: recordID)
        record["shortID"] = shortID as CKRecordValue
        record["wishlistID"] = wishlistID as CKRecordValue
        record["wishlistName"] = wishlistName as CKRecordValue
        record["wishlistEmoji"] = (wishlistEmoji ?? "") as CKRecordValue
        record["ownerName"] = (ownerName ?? "") as CKRecordValue
        record["role"] = role.rawValue as CKRecordValue
        record["itemCount"] = Int64(itemCount) as CKRecordValue
        record["expiresAt"] = expiresAt as CKRecordValue

        do {
            _ = try await publicDB.save(record)
        } catch {
            throw SharingError.saveFailed(error)
        }
    }

    nonisolated func resolveShareLink(shortID: String) async throws -> ShareLinkInfo? {
        let predicate = NSPredicate(format: "shortID == %@", shortID)
        let query = CKQuery(recordType: Self.shareLinkRecordType, predicate: predicate)

        let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)

        guard let (_, result) = results.first else { return nil }

        let record = try result.get()

        // Check expiration
        if let expiresAt = record["expiresAt"] as? Date, expiresAt < Date.now {
            try? await publicDB.deleteRecord(withID: record.recordID)
            return nil
        }

        let wishlistID = record["wishlistID"] as? String ?? ""
        let wishlistName = record["wishlistName"] as? String ?? ""
        let emoji = record["wishlistEmoji"] as? String
        let owner = record["ownerName"] as? String
        let role = record["role"] as? String ?? ShareRole.viewer.rawValue
        let count = record["itemCount"] as? Int64 ?? 0

        return ShareLinkInfo(
            wishlistID: wishlistID,
            wishlistName: wishlistName,
            wishlistEmoji: emoji?.isEmpty == true ? nil : emoji,
            ownerName: owner?.isEmpty == true ? nil : owner,
            role: role,
            itemCount: Int(count)
        )
    }

    nonisolated func deleteShareLink(shortID: String) async throws {
        let recordID = CKRecord.ID(recordName: shortID)
        do {
            try await publicDB.deleteRecord(withID: recordID)
        } catch {
            throw SharingError.deleteFailed(error)
        }
    }

    nonisolated func deleteExpiredShareLinks() async {
        do {
            let predicate = NSPredicate(format: "expiresAt < %@", Date.now as NSDate)
            let query = CKQuery(recordType: Self.shareLinkRecordType, predicate: predicate)

            let (results, _) = try await publicDB.records(matching: query)

            let recordIDs = results.compactMap { recordID, _ in recordID }

            guard !recordIDs.isEmpty else { return }

            try await publicDB.modifyRecords(
                saving: [],
                deleting: recordIDs
            )
        } catch {
            // Best-effort -- silently ignore
        }
    }

    // MARK: - Private Helpers

    private nonisolated func sharedItemInfo(from record: CKRecord) -> SharedItemInfo {
        let itemID = record["itemID"] as? String ?? record.recordID.recordName
        let name = record["name"] as? String ?? ""
        let tier = record["tier"] as? String ?? "idea"
        let price = record["price"] as? Double
        let currency = record["currency"] as? String ?? "RUB"
        let url = record["url"] as? String
        let coverEmoji = record["coverEmoji"] as? String
        let sortIndex = record["sortIndex"] as? Double ?? 0
        let isArchived = (record["isArchived"] as? Int64 ?? 0) != 0

        return SharedItemInfo(
            itemID: itemID,
            name: name,
            tier: tier,
            price: price,
            currency: currency,
            url: url?.isEmpty == true ? nil : url,
            coverEmoji: coverEmoji?.isEmpty == true ? nil : coverEmoji,
            sortIndex: sortIndex,
            isArchived: isArchived
        )
    }

    /// Retries an operation up to 3 times on CKError.serverRecordChanged (conflict).
    private nonisolated func retryOnConflict(
        maxAttempts: Int = 3,
        operation: @Sendable () async throws -> Void
    ) async throws {
        for attempt in 1...maxAttempts {
            do {
                try await operation()
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                if attempt == maxAttempts {
                    throw SharingError.recordConflict
                }
                // Brief pause before retry
                try await Task.sleep(for: .milliseconds(200 * attempt))
            }
        }
    }
}
