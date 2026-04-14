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

    private static let linkDomain = "https://rugyron.github.io/I-Wish-App"

    func generateShare(
        for wishlist: Wishlist,
        role: ShareRole,
        ttl: InviteTTL
    ) {
        let shortID = wishlist.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        let url = URL(string: "\(Self.linkDomain)/j/\(shortID)?r=\(role.rawValue.prefix(1))&t=\(ttl.rawValue)")!
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
        guard let url = shareURL else { return "" }
        return "Присоединяйся к моему списку желаний «\(wishlistName)» в I Wish!\n\n\(url.absoluteString)"
    }
}
