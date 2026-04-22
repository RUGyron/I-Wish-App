import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit

@Observable
@MainActor
final class AuthService: NSObject {
    var currentUser: User? // Firebase Auth User
    var userName: String?
    var isAuthenticated: Bool { currentUser != nil && !currentUser!.isAnonymous }
    var isAnonymous: Bool { currentUser?.isAnonymous ?? true }
    var uid: String? { currentUser?.uid }

    private var currentNonce: String?

    override init() {
        super.init()
        currentUser = Auth.auth().currentUser
        if currentUser == nil {
            // Auto sign-in anonymously
            Task { await signInAnonymously() }
        }
    }

    func signInAnonymously() async {
        do {
            let result = try await Auth.auth().signInAnonymously()
            currentUser = result.user
            print("[Auth] Anonymous sign-in OK, uid: \(result.user.uid)")
        } catch {
            print("[Auth] Anonymous sign-in failed: \(error)")
        }
    }

    /// Ensures we have an authenticated user (anonymous or Apple). Waits up to 5s.
    func ensureAuth() async -> Bool {
        if currentUser != nil { return true }
        // Wait for in-flight anonymous sign-in
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(500))
            if currentUser != nil { return true }
        }
        // Try once more
        await signInAnonymously()
        return currentUser != nil
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

            if let user = currentUser, user.isAnonymous {
                // Link anonymous account with Apple
                let result = try await user.link(with: firebaseCredential)
                currentUser = result.user
            } else {
                let result = try await Auth.auth().signIn(with: firebaseCredential)
                currentUser = result.user
            }

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
        currentUser = nil
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
