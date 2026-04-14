import CloudKit
import SwiftData
import SwiftUI

// MARK: - Share Role

enum ShareRole: String, CaseIterable, Identifiable {
    case editor = "editor"
    case viewer = "viewer"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .editor: return "Редактор"
        case .viewer: return "Только просмотр"
        }
    }

    var icon: String {
        switch self {
        case .editor: return "pencil"
        case .viewer: return "eye"
        }
    }
}

// MARK: - Share Manager

@Observable
final class ShareManager {
    var activeShare: CKShare?
    var shareURL: URL?
    var expiresAt: Date?
    var isLoading = false
    var error: String?

    /// Creates or recreates a CKShare for the wishlist.
    /// Placeholder implementation — generates a local URL until CloudKit entitlements are configured.
    func createShare(
        for wishlist: Wishlist,
        role: ShareRole,
        ttl: InviteTTL
    ) {
        isLoading = true
        error = nil

        // Placeholder: generate a URL like iwish://share/{wishlist.id}
        // Real implementation will use CKContainer.shared().privateCloudDatabase
        let url = URL(string: "iwish://share/\(wishlist.id.uuidString)")!
        self.shareURL = url
        self.expiresAt = ttl.duration.map { Date.now.addingTimeInterval($0) }
        self.isLoading = false
    }

    func revokeShare() {
        shareURL = nil
        expiresAt = nil
        activeShare = nil
        error = nil
    }

    var hasActiveShare: Bool {
        shareURL != nil
    }
}
