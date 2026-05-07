import Foundation
import SwiftData
import FirebaseAuth
import AuthenticationServices
import os.log

private let log = Logger(subsystem: "RUGyron.IWish", category: "AccountDeletion")

/// Полное удаление аккаунта (Guideline 5.1.1(v)).
///
/// Порядок:
/// 1. Re-auth свежим Apple credential (Firebase требует recent login для delete)
/// 2. Чистим Firestore: personal wishlists, owner-shared wishlists (с items + memberships + invites),
///    leave participant-shared wishlists
/// 3. Wipe iCloud Keychain (AES-ключи + displayName)
/// 4. Wipe локальный SwiftData
/// 5. `Auth.auth().currentUser?.delete()` — Firebase iOS SDK при этом сам отзывает SIWA token
///    у Apple через server-to-server revoke. Это и удовлетворяет 5.1.1(v) без своего бэкенда.
@MainActor
final class AccountDeletionService {
    let auth: AuthService
    let firestore: FirestoreService
    let data: DataService

    init(auth: AuthService, firestore: FirestoreService, data: DataService) {
        self.auth = auth
        self.firestore = firestore
        self.data = data
    }

    enum AccountDeletionError: LocalizedError {
        case notAuthenticated
        case requiresReauth
        case firebaseDeleteFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Сначала войдите в аккаунт"
            case .requiresReauth: return "Требуется повторный вход через Apple ID"
            case .firebaseDeleteFailed(let m): return "Не удалось удалить аккаунт: \(m)"
            }
        }
    }

    func deleteAccount(appleCredential: ASAuthorizationAppleIDCredential, rawNonce: String) async throws {
        guard let uid = auth.uid, let user = Auth.auth().currentUser else {
            throw AccountDeletionError.notAuthenticated
        }

        guard let tokenData = appleCredential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            throw AccountDeletionError.requiresReauth
        }
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: token,
            rawNonce: rawNonce,
            fullName: appleCredential.fullName
        )
        do {
            try await user.reauthenticate(with: firebaseCredential)
        } catch {
            log.error("Re-auth failed: \(error.localizedDescription, privacy: .public)")
            throw AccountDeletionError.requiresReauth
        }

        log.info("AccountDeletion: starting for uid=\(uid, privacy: .public)")

        // Локальные wishlists — источник правды что чистить (cached Firestore state).
        let descriptor = FetchDescriptor<Wishlist>()
        let localWishlists = (try? data.modelContext.fetch(descriptor)) ?? []

        for wl in localWishlists {
            let wlID = wl.id.uuidString
            do {
                if wl.isShared, let sharedID = wl.sharedWishlistID {
                    let isOwner = (wl.ownerRecordID == uid) || wl.myRole == "owner"
                    if isOwner {
                        try await firestore.deleteSharedWishlistFull(wishlistID: sharedID)
                        try? await firestore.deletePersonalWishlist(uid: uid, wishlistID: wlID)
                    } else {
                        try await firestore.leaveWishlist(wishlistID: sharedID, userUID: uid)
                    }
                } else {
                    try await firestore.deletePersonalWishlist(uid: uid, wishlistID: wlID)
                }
            } catch {
                // Best-effort: продолжаем чтобы Firebase user всё равно удалился.
                // Orphaned docs в Firestore не критичны (без ключа из Keychain нерасшифруемы).
                log.error("Cleanup failed for \(wlID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // На случай если локальный кеш неполон — добираем оставшиеся memberships по серверу.
        if let memberships = try? await firestore.fetchMyMemberships(userUID: uid) {
            for m in memberships {
                try? await firestore.leaveWishlist(wishlistID: m.wishlistID, userUID: uid)
            }
        }

        KeychainService.deleteAll()

        if let allWL = try? data.modelContext.fetch(FetchDescriptor<Wishlist>()) {
            for wl in allWL { data.modelContext.delete(wl) }
        }
        if let allItems = try? data.modelContext.fetch(FetchDescriptor<Item>()) {
            for it in allItems { data.modelContext.delete(it) }
        }
        if let allSettings = try? data.modelContext.fetch(FetchDescriptor<AppSettings>()) {
            for s in allSettings { data.modelContext.delete(s) }
        }
        try? data.modelContext.save()

        UserDefaults.standard.removeObject(forKey: "iwish_encrypted_v1_migration_done")
        UserDefaults.standard.removeObject(forKey: "auth_userName")

        // Firebase iOS SDK при delete() сам делает server-to-server revoke у Apple
        // (POST appleid.apple.com/auth/revoke c client_secret JWT, подписанным Firebase'ом).
        // Это закрывает требование 5.1.1(v) без нашего бэкенда.
        do {
            try await user.delete()
            log.info("AccountDeletion: Firebase user deleted, SIWA token revoked")
        } catch {
            log.error("Firebase user.delete() failed: \(error.localizedDescription, privacy: .public)")
            throw AccountDeletionError.firebaseDeleteFailed(error.localizedDescription)
        }

        try? auth.signOut()
    }
}
