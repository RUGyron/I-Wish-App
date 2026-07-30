import Foundation
import SwiftData
import UIKit
import os.log

/// Обрабатывает очередь pending shares — записей из Share Extension. Для каждой записи:
/// 1. Определяет target wishlist (по `wishlistID` из share либо берёт самый свежий активный).
/// 2. Дёргает `URLMetadataService.fetch` чтобы обогатить (Gemini refine, image, price).
/// 3. Создаёт Item через `DataService.addItem` — это синкается с Firestore автоматически.
/// 4. Удаляет запись из очереди.
///
/// Если юзер не залогинен — оставляем pending в очереди (обработаем после login).
/// Если все wishlists архивированы / удалены — также skip (обработаем после восстановления).
@MainActor
final class PendingSharesProcessor {
    private let services: AppServices
    private let modelContext: ModelContext
    private let log = Logger(subsystem: "RUGyron.IWish", category: "PendingShares")

    init(services: AppServices, modelContext: ModelContext) {
        self.services = services
        self.modelContext = modelContext
    }

    func processAll() async {
        guard services.auth.isAuthenticated else {
            log.debug("Skip processing — not authenticated")
            return
        }
        let queue = SharedStorage.readPendingShares()
        guard !queue.isEmpty else { return }
        log.info("Processing \(queue.count, privacy: .public) pending share(s)")

        for share in queue {
            await process(share)
        }
    }

    private func process(_ share: SharedStorage.PendingShare) async {
        // 1. Найти target wishlist.
        let all = (try? modelContext.fetch(FetchDescriptor<Wishlist>())) ?? []
        let active = all.filter { !$0.isArchived }
        let target: Wishlist? = {
            if let idStr = share.wishlistID, let uuid = UUID(uuidString: idStr),
               let wl = active.first(where: { $0.id == uuid }) {
                return wl
            }
            // Fallback: самый свежий активный
            return active.sorted { $0.updatedAt > $1.updatedAt }.first
        }()
        guard let wishlist = target else {
            log.warning("Pending share \(share.id.uuidString, privacy: .public): нет target wishlist'а")
            return
        }

        // 2. Поля уже заполнены в Share Extension (он сам делает URLMetadataService.fetch).
        //    Если каких-то полей нет — добиваем повторным fetch (тонкий fallback на случай
        //    когда extension не смог сходить в сеть / Gemini был disabled).
        var enrichedTitle = share.title
        var enrichedImageData = share.imageData
        var enrichedPrice = share.price
        var enrichedCurrency = share.currency
        var enrichedDescription = share.descriptionText

        let needsFallbackFetch = (enrichedPrice == nil && enrichedDescription == nil && enrichedImageData == nil)
        if needsFallbackFetch, let url = URL(string: share.url) {
            let meta = await URLMetadataService.fetch(from: url)
            let settings = (try? modelContext.fetch(FetchDescriptor<AppSettings>()).first) ?? AppSettings()
            if settings.parseFillTitle, let t = meta.title, !t.isEmpty,
               enrichedTitle?.trimmingCharacters(in: .whitespaces).isEmpty != false {
                enrichedTitle = t
            }
            if settings.parseFillImage, let image = meta.image, enrichedImageData == nil {
                enrichedImageData = ImageCompressor.compress(image)
            }
            if settings.parseFillPrice {
                if enrichedPrice == nil { enrichedPrice = meta.price }
                if enrichedCurrency == nil { enrichedCurrency = meta.currency }
            }
            if settings.parseFillDescription, enrichedDescription == nil {
                enrichedDescription = meta.descriptionText
            }
        }

        let tier = ItemTier(rawValue: share.tierRaw) ?? .maybe
        let nextSort = nextSortIndex(in: wishlist, tier: tier)
        let finalName = (enrichedTitle?.trimmingCharacters(in: .whitespaces).isEmpty == false) ?
            enrichedTitle! : (share.title ?? String(localized: "Untitled"))

        do {
            _ = try await services.data.addItem(
                to: wishlist.id.uuidString,
                name: finalName,
                tier: tier,
                price: enrichedPrice,
                priceMax: nil,
                currency: enrichedCurrency ?? "RUB",
                url: share.url,
                emoji: nil,
                sortIndex: nextSort,
                descriptionText: enrichedDescription,
                probationEndAt: nil,
                coverImageData: enrichedImageData,
                linkMetadataData: nil,
                gradientHue: nil
            )
            SharedStorage.removePendingShare(id: share.id)
            log.info("Pending share \(share.id.uuidString, privacy: .public) added to wishlist \(wishlist.id.uuidString, privacy: .public)")
        } catch {
            log.error("Failed to add pending share \(share.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            // Не удаляем — попробуем ещё раз при следующем didBecomeActive
        }
    }

    private func nextSortIndex(in wishlist: Wishlist, tier: ItemTier) -> Double {
        let items = (wishlist.items ?? []).filter { $0.tier == tier && !$0.isArchived }
        let maxIndex = items.map(\.sortIndex).max() ?? 0
        return maxIndex + 1000
    }
}

// MARK: - Wishlists cache sync (main → Share Extension)

@MainActor
enum WishlistsCacheSync {
    /// Сохраняет лёгкий снэпшот активных вишлистов в App Group для Share Extension picker.
    /// Вызывается из RootView .onChange(of: wishlistsObservable) или явно после mutation.
    static func sync(from wishlists: [Wishlist]) {
        let active = wishlists.filter { !$0.isArchived }
        let summaries = active.map {
            SharedStorage.WishlistSummary(
                id: $0.id.uuidString,
                name: $0.name,
                emoji: $0.coverEmoji,
                isShared: $0.isShared,
                memberCount: $0.memberCount,
                updatedAt: $0.updatedAt
            )
        }
        SharedStorage.writeWishlistsCache(summaries)
    }
}
