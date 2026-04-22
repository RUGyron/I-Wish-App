import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit

@Observable
@MainActor
final class AuthService: NSObject {
    var userName: String?
    var isAuthenticated: Bool { _idToken != nil }
    var uid: String? { _uid }
    var currentUser: User? { Auth.auth().currentUser }

    private var _uid: String?
    private var _idToken: String?
    private var _refreshToken: String?
    private var currentNonce: String?

    private static let apiKey = "AIzaSyBifbBfRvO47M7mZnxJ55QZSqeelqPeSMs"

    override init() {
        super.init()
        // Restore from Firebase SDK cache
        if let user = Auth.auth().currentUser {
            _uid = user.uid
            print("[Auth] Restored cached user: \(user.uid)")
            Task { await refreshToken() }
        } else {
            Task { await signInAnonymouslyREST() }
        }
    }

    /// Anonymous sign-in via Firebase REST API (bypasses gRPC)
    func signInAnonymouslyREST() async {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(Self.apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["returnSecureToken": true])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let idToken = json["idToken"] as? String,
                  let refreshToken = json["refreshToken"] as? String,
                  let localId = json["localId"] as? String else {
                print("[Auth] REST sign-up: bad response")
                return
            }
            _uid = localId
            _idToken = idToken
            _refreshToken = refreshToken
            print("[Auth] Anonymous sign-in OK (REST), uid: \(localId)")

            // Also sign in SDK so getIDToken works for other Firebase services
            let credential = EmailAuthProvider.credential(withEmail: "", password: "")
            // Actually, sign in SDK with custom token — not possible without server
            // Just use our REST token directly
        } catch {
            print("[Auth] REST anonymous sign-in failed: \(error)")
        }
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

    /// Ensures we have an authenticated user. Waits up to 5s.
    func ensureAuth() async -> Bool {
        if _idToken != nil { return true }
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(500))
            if _idToken != nil { return true }
        }
        await signInAnonymouslyREST()
        return _idToken != nil
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
            // Refresh token from SDK
            _idToken = try? await authResult.user.getIDToken()

            // Extract name
            if let givenName = credential.fullName?.givenName {
                userName = [givenName, credential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }

        case .failure(let error):
            throw error
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
        _uid = nil
        _idToken = nil
        _refreshToken = nil
        userName = nil
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
