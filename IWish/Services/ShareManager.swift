import CloudKit
import SwiftUI
import SwiftData

// MARK: - Share Role

enum ShareRole: String, CaseIterable, Identifiable {
    case editor
    case viewer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .editor: return "Редактор"
        case .viewer: return "Только просмотр"
        }
    }
}

// MARK: - Share Manager

@Observable
final class ShareManager {
    private(set) var shareURL: URL?
    private(set) var expiresAt: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var shortID: String?

    private static let linkDomain = "https://rugyron.github.io/I-Wish-App"
    private let sharingService = CloudKitSharingService()

    func generateShare(
        for wishlist: Wishlist,
        role: ShareRole,
        ttl: InviteTTL,
        ownerName: String?,
        container: ModelContainer
    ) async {
        isLoading = true
        error = nil

        do {
            let newShortID = String(
                wishlist.id.uuidString
                    .replacingOccurrences(of: "-", with: "")
                    .prefix(12)
                    .lowercased()
            )

            // Always delete existing ShareLink before creating new one
            try? await sharingService.deleteShareLink(shortID: newShortID)

            // 1. Create a REAL CKShare in the private DB
            let ckShareURL = try await sharingService.createCKShare(
                for: wishlist.id,
                role: role
            )

            let itemCount = (wishlist.items ?? []).filter { !$0.isArchived }.count
            let expiry = ttl.duration.map { Date.now.addingTimeInterval($0) }
            let effectiveExpiry = expiry ?? Date.distantFuture

            // 2. Store the real CKShare URL in PublicDB ShareLink
            //    The user-facing URL (for QR) still goes through GitHub Pages,
            //    but the ShareLink record now holds the real ckShareURL for accept flow.
            let userURL = URL(string: "\(Self.linkDomain)/j/\(newShortID)")!

            try await sharingService.createShareLink(
                shortID: newShortID,
                ckShareURL: ckShareURL,
                wishlistName: wishlist.name,
                wishlistEmoji: wishlist.coverEmoji,
                ownerName: ownerName,
                role: role,
                itemCount: itemCount,
                expiresAt: effectiveExpiry
            )

            self.shareURL = userURL
            self.expiresAt = expiry
            self.shortID = newShortID
            self.wishlistID = wishlist.id
            self.wishlistRef = wishlist

            wishlist.isShared = true
            wishlist.updatedAt = .now
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Wishlist ID to track for CKShare cleanup on revoke
    private var wishlistID: UUID?
    private var wishlistRef: Wishlist?

    func revokeAll() async {
        // Delete CKShare from private DB
        if let wid = wishlistID {
            try? await sharingService.deleteCKShare(for: wid)
        }
        // Delete ShareLink from public DB
        if let shortID {
            try? await sharingService.deleteShareLink(shortID: shortID)
        }
        wishlistRef?.isShared = false
        wishlistRef?.updatedAt = .now
        wishlistRef = nil
        shareURL = nil
        expiresAt = nil
        shortID = nil
        wishlistID = nil
        error = nil
    }

    var hasActiveShare: Bool { shareURL != nil }

    func invitationText(wishlistName: String) -> String {
        guard let url = shareURL else { return "" }
        return "Присоединяйся к моему списку желаний «\(wishlistName)» в I Wish!\n\n\(url.absoluteString)"
    }
}
