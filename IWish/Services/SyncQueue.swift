import Foundation
import Network
import SwiftData

@Observable
@MainActor
final class SyncQueue {

    // MARK: - Types

    struct PendingSync: Codable, Identifiable {
        let id: UUID
        let wishlistID: String
        let timestamp: Date
    }

    // MARK: - Properties

    private(set) var pendingCount = 0
    private var pending: [PendingSync] = []
    private let monitor = NWPathMonitor()
    private var isProcessing = false

    /// Weak-ish references set after init by AppServices
    var syncService: SharedWishlistSyncService?
    var modelContext: ModelContext?

    // MARK: - Init

    init() {
        loadPending()
        startMonitoring()
    }

    // MARK: - Public API

    /// Enqueue a sync -- called when push fails due to network error.
    func enqueue(wishlistID: String) {
        guard !pending.contains(where: { $0.wishlistID == wishlistID }) else { return }
        let item = PendingSync(id: UUID(), wishlistID: wishlistID, timestamp: .now)
        pending.append(item)
        pendingCount = pending.count
        savePending()
    }

    /// Remove a specific wishlist from the queue (called on successful push).
    func dequeue(wishlistID: String) {
        pending.removeAll { $0.wishlistID == wishlistID }
        pendingCount = pending.count
        savePending()
    }

    /// Process all pending syncs.
    func processQueue() async {
        guard !isProcessing, !pending.isEmpty else { return }
        isProcessing = true

        var remaining: [PendingSync] = []
        for item in pending {
            let success = await pushWishlist(id: item.wishlistID)
            if !success { remaining.append(item) }
        }

        pending = remaining
        pendingCount = pending.count
        savePending()
        isProcessing = false
    }

    // MARK: - Private

    private func pushWishlist(id: String) async -> Bool {
        guard let ctx = modelContext, let sync = syncService else { return false }

        let descriptor = FetchDescriptor<Wishlist>(
            predicate: #Predicate { $0.sharedWishlistID == id }
        )
        guard let wishlist = try? ctx.fetch(descriptor).first else {
            // Wishlist no longer exists locally -- treat as success (remove from queue)
            return true
        }

        await sync.pushChanges(for: wishlist)
        // If pushChanges enqueues again internally, it means it failed --
        // but we remove this entry and let the new one take its place.
        return !pending.contains(where: { $0.wishlistID == id })
    }

    // MARK: - Persistence (UserDefaults)

    private static let storageKey = "SyncQueue.pending"

    private func savePending() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func loadPending() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let items = try? JSONDecoder().decode([PendingSync].self, from: data)
        else { return }
        pending = items
        pendingCount = pending.count
    }

    // MARK: - Network Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                Task { @MainActor in
                    await self?.processQueue()
                }
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }
}
