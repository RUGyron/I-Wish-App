import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit

@Observable
@MainActor
final class AuthService: NSObject {
    var userName: String?
    var isLoading: Bool = true
    /// True only after Sign in with Apple (not anonymous)
    var isAuthenticated: Bool { _isAppleSignedIn }
    var hasToken: Bool { _idToken != nil }
    var uid: String? { _uid }
    var currentUser: User? { Auth.auth().currentUser }

    private var _uid: String?
    private var _idToken: String?
    private var _refreshToken: String?
    private var _isAppleSignedIn: Bool = false
    private var currentNonce: String?

    private static let apiKey = "AIzaSyBifbBfRvO47M7mZnxJ55QZSqeelqPeSMs"

    override init() {
        super.init()

        // Migration: перенести legacy UserDefaults["auth_userName"] в iCloud Keychain
        if KeychainService.loadUserName() == nil,
           let legacyName = UserDefaults.standard.string(forKey: "auth_userName"),
           !legacyName.isEmpty {
            KeychainService.saveUserName(legacyName)
            UserDefaults.standard.removeObject(forKey: "auth_userName")
        }

        // Основной источник имени — iCloud Keychain (sync между Apple ID девайсами).
        // Fallback на UserDefaults если Keychain ещё не синкнулся (но новые записи туда НЕ пишем).
        userName = KeychainService.loadUserName()
            ?? UserDefaults.standard.string(forKey: "auth_userName")

        if let user = Auth.auth().currentUser, !user.isAnonymous {
            _uid = user.uid
            print("[Auth] Found Keychain session: \(user.uid)")
            Task {
                await verifyAndRestore(uid: user.uid)
                isLoading = false
            }
        } else {
            isLoading = false
            print("[Auth] No session, will show Sign in with Apple")
        }
    }

    /// Restore session. Trust Firebase SDK + iCloud Keychain.
    /// Имя приходит из iCloud Keychain (синкается между девайсами того же Apple ID).
    /// Если Keychain пустой — оставляем nil, SettingsView покажет fallback ("Apple ID").
    private func verifyAndRestore(uid: String) async {
        _isAppleSignedIn = true
        await refreshToken()

        // На случай если Keychain синкнулся уже после init() — перечитываем.
        if userName == nil {
            userName = KeychainService.loadUserName()
        }
        print("[Auth] Restored: \(uid), name: \(userName ?? "nil")")
    }

    /// Get a valid ID token (refreshes if needed)
    func getIDToken() async -> String? {
        // Try SDK first
        if let user = Auth.auth().currentUser {
            if let token = try? await user.getIDToken() {
                _idToken = token
                return token
            }
        }
        // Fall back to REST token
        if let token = _idToken { return token }
        // Try refresh
        await refreshToken()
        return _idToken
    }

    private func refreshToken() async {
        guard let refreshToken = _refreshToken else { return }
        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(Self.apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&refresh_token=\(refreshToken)".data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let idToken = json["id_token"] as? String,
                  let newRefresh = json["refresh_token"] as? String,
                  let userId = json["user_id"] as? String else { return }
            _uid = userId
            _idToken = idToken
            _refreshToken = newRefresh
        } catch {
            print("[Auth] Token refresh failed: \(error)")
        }
    }

    /// Ensures we have an authenticated Apple user.
    func ensureAuth() async -> Bool {
        return _isAppleSignedIn && _idToken != nil
    }

    // Sign in with Apple -- returns (credential, nonce) for Firebase
    func startSignInWithApple() -> ASAuthorizationAppleIDRequest {
        let nonce = randomNonceString()
        currentNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName]
        request.nonce = sha256(nonce)
        return request
    }

    func handleSignInWithApple(result: Result<ASAuthorization, Error>) async throws {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                throw AuthError.missingCredential
            }

            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: token,
                rawNonce: nonce,
                fullName: credential.fullName
            )

            let authResult: AuthDataResult
            if let user = Auth.auth().currentUser, user.isAnonymous {
                authResult = try await user.link(with: firebaseCredential)
            } else {
                authResult = try await Auth.auth().signIn(with: firebaseCredential)
            }
            _uid = authResult.user.uid
            _idToken = try? await authResult.user.getIDToken()
            _isAppleSignedIn = true
            print("[Auth] Apple sign-in OK, uid: \(_uid ?? "nil")")

            // Extract name — Apple only sends it on FIRST sign-in ever
            var resolvedName: String?

            // 1. Try Apple credential (только при первом sign-in c этим Apple ID)
            if let givenName = credential.fullName?.givenName {
                resolvedName = [givenName, credential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }

            // 2. Try Firebase displayName
            if resolvedName == nil, let dn = authResult.user.displayName, !dn.isEmpty {
                resolvedName = dn
            }

            // 3. Try iCloud Keychain (если юзер уже логинился на этом или другом девайсе)
            if resolvedName == nil {
                resolvedName = KeychainService.loadUserName()
            }

            // 4. Try email as last resort
            if resolvedName == nil {
                if let email = authResult.user.email, !email.isEmpty {
                    resolvedName = email.components(separatedBy: "@").first
                }
            }

            let finalName = resolvedName ?? "Пользователь"
            userName = finalName
            // Сохраняем приватно в iCloud Keychain — sync между Apple ID девайсами,
            // разраб (Firebase Console) имя не видит.
            KeychainService.saveUserName(finalName)

        case .failure(let error):
            throw error
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
        _uid = nil
        _idToken = nil
        _refreshToken = nil
        _isAppleSignedIn = false
        userName = nil
        KeychainService.deleteUserName()
        UserDefaults.standard.removeObject(forKey: "auth_userName")
    }

    enum AuthError: LocalizedError {
        case missingCredential
        case notAuthenticated

        var errorDescription: String? {
            switch self {
            case .missingCredential: return "Не удалось получить данные Apple ID"
            case .notAuthenticated: return "Необходимо войти через Apple ID"
            }
        }
    }

    // MARK: - Helpers

    private func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
