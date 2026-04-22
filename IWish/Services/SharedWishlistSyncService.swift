import Foundation
import SwiftData
import CloudKit

@Observable
@MainActor
final class SharedWishlistSyncService {
    private let sharing = CloudKitSharingService()

    /// Set by AppServices after init to enable offline retry queue
    var syncQueue: SyncQueue?

    /// Push local changes to PublicDB for a shared wishlist.
    /// On network failure, enqueues to SyncQueue for automatic retry.
    func pushChanges(for wishlist: Wishlist) async {
        guard let sharedID = wishlist.sharedWishlistID else { return }
        let items = (wishlist.items ?? []).map { item in
            CloudKitSharingService.SharedItemInfo(
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

        do {
            try await sharing.updateSharedItems(wishlistID: sharedID, items: items)
            // Success -- remove from queue if it was pending
            syncQueue?.dequeue(wishlistID: sharedID)
        } catch {
            if Self.isNetworkError(error) {
                syncQueue?.enqueue(wishlistID: sharedID)
            }
        }
    }

    /// Check whether an error is a network-related failure worth retrying.
    private static func isNetworkError(_ error: Error) -> Bool {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                return true
            default:
                break
            }
        }
        // Also handle underlying NSURLError domain
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return true
        }
        // Check wrapped CKError.saveFailed containing network causes
        if let ckError = error as? CloudKitSharingService.SharingError,
           case .saveFailed(let underlying) = ckError {
            return isNetworkError(underlying)
        }
        return false
    }

    /// Pull remote changes from PublicDB into local SwiftData
    func pullChanges(for wishlist: Wishlist, context: ModelContext) async {
        guard let sharedID = wishlist.sharedWishlistID else { return }
        guard let remote = try? await sharing.fetchSharedWishlist(wishlistID: sharedID) else { return }

        // Update wishlist name/emoji if changed remotely
        if wishlist.name != remote.name { wishlist.name = remote.name }
        if wishlist.coverEmoji != remote.coverEmoji { wishlist.coverEmoji = remote.coverEmoji }

        let localItems = wishlist.items ?? []
        let remoteItemIDs = Set(remote.items.map(\.itemID))
        let localItemIDs = Set(localItems.map { $0.id.uuidString })

        // Add new remote items
        for remoteItem in remote.items where !localItemIDs.contains(remoteItem.itemID) {
            let item = Item(
                name: remoteItem.name,
                tier: ItemTier(rawValue: remoteItem.tier) ?? .maybe,
                sortIndex: remoteItem.sortIndex,
                currency: remoteItem.currency,
                price: remoteItem.price,
                url: remoteItem.url,
                coverEmoji: remoteItem.coverEmoji
            )
            item.isArchived = remoteItem.isArchived
            item.wishlist = wishlist
            context.insert(item)
        }

        // Update existing items
        for localItem in localItems {
            if let remoteItem = remote.items.first(where: { $0.itemID == localItem.id.uuidString }) {
                if localItem.name != remoteItem.name { localItem.name = remoteItem.name }
                if localItem.tier.rawValue != remoteItem.tier { localItem.tierRaw = remoteItem.tier }
                if localItem.price != remoteItem.price { localItem.priceValue = remoteItem.price }
                if localItem.currency != remoteItem.currency { localItem.currency = remoteItem.currency }
                if localItem.url != remoteItem.url { localItem.url = remoteItem.url }
                if localItem.coverEmoji != remoteItem.coverEmoji { localItem.coverEmoji = remoteItem.coverEmoji }
                if localItem.sortIndex != remoteItem.sortIndex { localItem.sortIndex = remoteItem.sortIndex }
                if localItem.isArchived != remoteItem.isArchived { localItem.isArchived = remoteItem.isArchived }
            }
        }

        // Remove items deleted remotely
        for localItem in localItems where !remoteItemIDs.contains(localItem.id.uuidString) {
            context.delete(localItem)
        }

        try? context.save()
    }
}
