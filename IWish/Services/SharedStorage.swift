import Foundation
import os.log

/// Shared file-based storage между main app и ShareExtension через App Group.
/// Storage — App Group container directory. JSON для structured data.
///
/// **Архитектура** (см. /Users/rugyron/Documents/Xcode/IWish/ShareExtension/):
/// - Share Extension получает URL + title + image preview от системы.
/// - Записывает `PendingShare` в JSON-очередь.
/// - Main app при `didBecomeActive` читает очередь, создаёт `Item` через DataService, удаляет.
///
/// Вторая ответственность — кеш списка вишлистов: Share Extension читает оттуда picker.
/// Main app обновляет cache при создании/удалении вишлистов.
enum SharedStorage {
    static let appGroupID = "group.RUGyron.IWish.shared"

    private static let log = Logger(subsystem: "RUGyron.IWish", category: "SharedStorage")

    private static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var pendingSharesURL: URL? { container?.appendingPathComponent("PendingShares.json") }
    private static var wishlistsCacheURL: URL? { container?.appendingPathComponent("WishlistsCache.json") }

    // MARK: - Models

    /// Лёгкая запись пендинга — payload для main-app processing.
    /// Extension UI делает parse + Gemini refine, поэтому может сразу заполнить все поля.
    /// Main app использует значения как-есть (без повторного parse) если они присутствуют.
    struct PendingShare: Codable, Identifiable {
        let id: UUID
        let url: String
        let title: String?
        let imageData: Data?
        let wishlistID: String?
        let tierRaw: String
        let createdAt: Date
        let price: Double?
        let currency: String?
        let descriptionText: String?

        init(
            id: UUID = UUID(),
            url: String,
            title: String?,
            imageData: Data? = nil,
            wishlistID: String?,
            tierRaw: String = "maybe",
            createdAt: Date = .now,
            price: Double? = nil,
            currency: String? = nil,
            descriptionText: String? = nil
        ) {
            self.id = id
            self.url = url
            self.title = title
            self.imageData = imageData
            self.wishlistID = wishlistID
            self.tierRaw = tierRaw
            self.createdAt = createdAt
            self.price = price
            self.currency = currency
            self.descriptionText = descriptionText
        }
    }

    /// Слепок вишлиста для picker'а в Share Extension. UID + display fields.
    struct WishlistSummary: Codable, Identifiable {
        let id: String
        let name: String
        let emoji: String?
        let isShared: Bool
        let memberCount: Int
        let updatedAt: Date

        init(id: String, name: String, emoji: String?, isShared: Bool, memberCount: Int, updatedAt: Date) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.isShared = isShared
            self.memberCount = memberCount
            self.updatedAt = updatedAt
        }
    }

    // MARK: - Wishlists cache (main app пишет, Share Extension читает)

    static func writeWishlistsCache(_ list: [WishlistSummary]) {
        guard let url = wishlistsCacheURL else {
            log.error("App Group container недоступен — wishlistsCacheURL nil")
            return
        }
        do {
            let data = try JSONEncoder.iso.encode(list)
            try data.write(to: url, options: .atomic)
            log.debug("WishlistsCache written: \(list.count, privacy: .public) items")
        } catch {
            log.error("writeWishlistsCache: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func readWishlistsCache() -> [WishlistSummary] {
        guard let url = wishlistsCacheURL,
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder.iso.decode([WishlistSummary].self, from: data)) ?? []
    }

    // MARK: - Pending shares (Share Extension пишет, main app читает + чистит)

    /// Атомарно добавить запись в очередь. File lock через atomic write.
    static func appendPendingShare(_ share: PendingShare) {
        guard let url = pendingSharesURL else {
            log.error("App Group container недоступен — pendingSharesURL nil")
            return
        }
        var existing = readPendingShares()
        existing.append(share)
        do {
            let data = try JSONEncoder.iso.encode(existing)
            try data.write(to: url, options: .atomic)
            log.info("PendingShare appended: \(share.id.uuidString, privacy: .public), total=\(existing.count, privacy: .public)")
        } catch {
            log.error("appendPendingShare: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func readPendingShares() -> [PendingShare] {
        guard let url = pendingSharesURL,
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder.iso.decode([PendingShare].self, from: data)) ?? []
    }

    /// После успешного создания Item — удалить запись из очереди.
    /// Использовать только из main app. Атомарность через перезапись всей очереди.
    static func removePendingShare(id: UUID) {
        guard let url = pendingSharesURL else { return }
        let filtered = readPendingShares().filter { $0.id != id }
        if filtered.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            let data = try JSONEncoder.iso.encode(filtered)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("removePendingShare: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Полная очистка — на случай инкорректного state или sign-out.
    static func clearAll() {
        if let url = pendingSharesURL { try? FileManager.default.removeItem(at: url) }
        if let url = wishlistsCacheURL { try? FileManager.default.removeItem(at: url) }
    }
}

// MARK: - JSON helpers

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
