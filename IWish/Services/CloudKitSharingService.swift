import CloudKit
import Foundation

@Observable
final class CloudKitSharingService {

    // MARK: - Types

    struct ShareLinkInfo {
        let ckShareURL: URL
        let wishlistName: String
        let wishlistEmoji: String?
        let ownerName: String?
        let role: String
        let itemCount: Int
    }

    enum SharingError: LocalizedError {
        case invalidShareURL
        case shareLinkNotFound
        case wishlistRecordNotFound
        case shareCreationFailed(Error)
        case metadataFetchFailed(Error)
        case acceptFailed(Error)
        case saveFailed(Error)
        case deleteFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidShareURL:
                return "Ссылка на шаринг недействительна."
            case .shareLinkNotFound:
                return "Приглашение не найдено или истекло."
            case .wishlistRecordNotFound:
                return "Список не найден в CloudKit. Дождитесь синхронизации и попробуйте снова."
            case .shareCreationFailed(let error):
                return "Не удалось создать приглашение: \(error.localizedDescription)"
            case .metadataFetchFailed(let error):
                return "Не удалось получить метаданные шаринга: \(error.localizedDescription)"
            case .acceptFailed(let error):
                return "Не удалось принять приглашение: \(error.localizedDescription)"
            case .saveFailed(let error):
                return "Не удалось сохранить ссылку: \(error.localizedDescription)"
            case .deleteFailed(let error):
                return "Не удалось удалить ссылку: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Private

    private static let recordType = "ShareLink"

    private nonisolated let container = CKContainer(
        identifier: ModelContainerFactory.cloudKitContainerID
    )

    private nonisolated var publicDB: CKDatabase {
        container.publicCloudDatabase
    }

    private nonisolated var privateDB: CKDatabase {
        container.privateCloudDatabase
    }

    /// The default SwiftData CloudKit zone
    private static let swiftDataZoneName = "com.apple.coredata.cloudkit.zone"

    // MARK: - CKShare: Create real share for a Wishlist

    /// Creates a real CKShare in the private DB for the given wishlist UUID.
    /// Returns the CKShare URL that can be used by receivers to accept the share.
    nonisolated func createCKShare(
        for wishlistID: UUID,
        role: ShareRole
    ) async throws -> URL {
        let zone = CKRecordZone(zoneName: Self.swiftDataZoneName)

        // 1. Find the CD_Wishlist record in the private DB
        let rootRecord = try await fetchWishlistRecord(wishlistID: wishlistID, in: zone)

        // 2. Check if there's already a share for this record and delete it
        if let existingShareRef = rootRecord.share {
            try? await deleteExistingShare(existingShareRef, in: zone)
            // Re-fetch after deletion so the record's share ref is cleared
            // (CKModifyRecordsOperation might have updated the server)
        }

        // 3. Create a new CKShare rooted on this record
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = rootRecord["CD_name"] as? String ?? "Wishlist"

        // "Anyone with the link" — public permission for URL-based join
        switch role {
        case .editor:
            share.publicPermission = .readWrite
        case .viewer:
            share.publicPermission = .readOnly
        }

        // 4. Save the share + updated root record together
        let (saveResults, _) = try await privateDB.modifyRecords(
            saving: [share, rootRecord],
            deleting: [],
            savePolicy: .changedKeys
        )

        // Check save results for errors
        for (_, result) in saveResults {
            _ = try result.get()
        }

        // 5. Return the share URL
        guard let shareURL = share.url else {
            throw SharingError.invalidShareURL
        }

        return shareURL
    }

    /// Fetches the CD_Wishlist CKRecord from the private DB by Wishlist UUID.
    private nonisolated func fetchWishlistRecord(
        wishlistID: UUID,
        in zone: CKRecordZone
    ) async throws -> CKRecord {
        let predicate = NSPredicate(format: "CD_id == %@", wishlistID as CVarArg)
        let query = CKQuery(recordType: "CD_Wishlist", predicate: predicate)

        let (results, _) = try await privateDB.records(
            matching: query,
            inZoneWith: zone.zoneID,
            resultsLimit: 1
        )

        guard let (_, result) = results.first else {
            throw SharingError.wishlistRecordNotFound
        }

        return try result.get()
    }

    /// Deletes an existing CKShare so we can create a fresh one.
    private nonisolated func deleteExistingShare(
        _ shareRef: CKRecord.Reference,
        in zone: CKRecordZone
    ) async throws {
        try await privateDB.modifyRecords(
            saving: [],
            deleting: [shareRef.recordID]
        )
    }

    /// Deletes the CKShare associated with a wishlist (for revocation).
    nonisolated func deleteCKShare(for wishlistID: UUID) async throws {
        let zone = CKRecordZone(zoneName: Self.swiftDataZoneName)

        let rootRecord = try await fetchWishlistRecord(wishlistID: wishlistID, in: zone)
        guard let shareRef = rootRecord.share else { return }

        try await privateDB.modifyRecords(
            saving: [],
            deleting: [shareRef.recordID]
        )
    }

    // MARK: - Public DB: Create ShareLink

    nonisolated func createShareLink(
        shortID: String,
        ckShareURL: URL,
        wishlistName: String,
        wishlistEmoji: String?,
        ownerName: String?,
        role: ShareRole,
        itemCount: Int,
        expiresAt: Date
    ) async throws {
        let recordID = CKRecord.ID(recordName: shortID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["shortID"] = shortID as CKRecordValue
        record["ckShareURL"] = ckShareURL.absoluteString as CKRecordValue
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

    // MARK: - Public DB: Resolve ShareLink by shortID

    nonisolated func resolveShareLink(shortID: String) async throws -> ShareLinkInfo? {
        let predicate = NSPredicate(format: "shortID == %@", shortID)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)

        let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)

        guard let (_, result) = results.first else { return nil }

        let record = try result.get()

        // Check expiration
        if let expiresAt = record["expiresAt"] as? Date, expiresAt < Date.now {
            // Expired — best-effort delete, return nil
            try? await publicDB.deleteRecord(withID: record.recordID)
            return nil
        }

        guard let urlString = record["ckShareURL"] as? String,
              let url = URL(string: urlString)
        else {
            return nil
        }

        let wishlistName = record["wishlistName"] as? String ?? ""
        let emoji = record["wishlistEmoji"] as? String
        let owner = record["ownerName"] as? String
        let role = record["role"] as? String ?? ShareRole.viewer.rawValue
        let count = record["itemCount"] as? Int64 ?? 0

        return ShareLinkInfo(
            ckShareURL: url,
            wishlistName: wishlistName,
            wishlistEmoji: emoji?.isEmpty == true ? nil : emoji,
            ownerName: owner?.isEmpty == true ? nil : owner,
            role: role,
            itemCount: Int(count)
        )
    }

    // MARK: - Public DB: Delete ShareLink by shortID

    nonisolated func deleteShareLink(shortID: String) async throws {
        let recordID = CKRecord.ID(recordName: shortID)
        do {
            try await publicDB.deleteRecord(withID: recordID)
        } catch {
            throw SharingError.deleteFailed(error)
        }
    }

    // MARK: - Delete expired ShareLinks (TTL rotation)

    nonisolated func deleteExpiredShareLinks() async {
        do {
            let predicate = NSPredicate(format: "expiresAt < %@", Date.now as NSDate)
            let query = CKQuery(recordType: Self.recordType, predicate: predicate)

            let (results, _) = try await publicDB.records(matching: query)

            let recordIDs = results.compactMap { recordID, _ in recordID }

            guard !recordIDs.isEmpty else { return }

            try await publicDB.modifyRecords(
                saving: [],
                deleting: recordIDs
            )
        } catch {
            // Best-effort — silently ignore
        }
    }

    // MARK: - CKShare: Fetch Participants

    struct ParticipantInfo {
        let name: String?
        let role: CKShare.ParticipantRole
        let acceptance: CKShare.ParticipantAcceptanceStatus
    }

    /// Fetches real CKShare participants for a given wishlist UUID.
    /// Returns empty array if no share exists or on any error.
    nonisolated func fetchParticipants(for wishlistID: UUID) async -> [ParticipantInfo] {
        let zone = CKRecordZone(zoneName: Self.swiftDataZoneName)

        do {
            // 1. Fetch the CD_Wishlist record
            let rootRecord = try await fetchWishlistRecord(wishlistID: wishlistID, in: zone)

            // 2. Check for .share reference
            guard let shareRef = rootRecord.share else { return [] }

            // 3. Fetch the CKShare record itself
            let shareRecord = try await privateDB.record(for: shareRef.recordID)
            guard let share = shareRecord as? CKShare else { return [] }

            // 4. Map participants (skip the owner)
            var result: [ParticipantInfo] = []
            for participant in share.participants {
                if participant.role == .owner { continue }

                // Try to resolve the display name via userIdentity
                var displayName: String? = nil
                if let nameComponents = participant.userIdentity.nameComponents {
                    let formatter = PersonNameComponentsFormatter()
                    let formatted = formatter.string(from: nameComponents)
                    if !formatted.isEmpty {
                        displayName = formatted
                    }
                }

                // Fallback: try discoverUserIdentity for the participant's userRecordID
                if displayName == nil, let userRecordID = participant.userIdentity.userRecordID {
                    let identity: CKUserIdentity? = await withCheckedContinuation { cont in
                        container.discoverUserIdentity(withUserRecordID: userRecordID) { identity, _ in
                            cont.resume(returning: identity)
                        }
                    }
                    if let nameComponents = identity?.nameComponents {
                        let formatter = PersonNameComponentsFormatter()
                        let formatted = formatter.string(from: nameComponents)
                        if !formatted.isEmpty {
                            displayName = formatted
                        }
                    }
                }

                result.append(ParticipantInfo(
                    name: displayName,
                    role: participant.role,
                    acceptance: participant.acceptanceStatus
                ))
            }

            return result
        } catch {
            return []
        }
    }

    // MARK: - CKShare: Accept

    nonisolated func acceptShare(from url: URL) async throws {
        let metadata = try await fetchShareMetadata(from: url)
        try await acceptShareMetadata(metadata)
    }

    // MARK: - Private Helpers

    private nonisolated func fetchShareMetadata(
        from url: URL
    ) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            let op = CKFetchShareMetadataOperation(shareURLs: [url])
            op.shouldFetchRootRecord = false

            nonisolated(unsafe) var fetchedMetadata: CKShare.Metadata?
            nonisolated(unsafe) var perShareError: Error?

            op.perShareMetadataResultBlock = { _, result in
                switch result {
                case .success(let metadata):
                    fetchedMetadata = metadata
                case .failure(let error):
                    perShareError = error
                }
            }

            op.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let metadata = fetchedMetadata {
                        continuation.resume(returning: metadata)
                    } else if let error = perShareError {
                        continuation.resume(throwing: SharingError.metadataFetchFailed(error))
                    } else {
                        continuation.resume(throwing: SharingError.invalidShareURL)
                    }
                case .failure(let error):
                    continuation.resume(throwing: SharingError.metadataFetchFailed(error))
                }
            }

            container.add(op)
        }
    }

    private nonisolated func acceptShareMetadata(
        _ metadata: CKShare.Metadata
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKAcceptSharesOperation(shareMetadatas: [metadata])

            op.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: SharingError.acceptFailed(error))
                }
            }

            container.add(op)
        }
    }
}
