import CloudKit
import SwiftUI

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

    /// Generates (or regenerates) a share link for the wishlist.
    /// Placeholder — real CKShare when CloudKit is configured.
    func generateShare(
        for wishlist: Wishlist,
        role: ShareRole,
        ttl: InviteTTL
    ) {
        let url = URL(string: "iwish://join/\(wishlist.id.uuidString)")!
        self.shareURL = url
        self.expiresAt = ttl.duration.map { Date.now.addingTimeInterval($0) }
    }

    /// Revokes all active invitations.
    func revokeAll() {
        shareURL = nil
        expiresAt = nil
    }

    var hasActiveShare: Bool { shareURL != nil }

    /// Invitation text for sharing (includes wishlist name and link).
    func invitationText(wishlistName: String) -> String {
        "Присоединяйся к списку желаний «\(wishlistName)» в I Wish!\n\(shareURL?.absoluteString ?? "")"
    }
}
