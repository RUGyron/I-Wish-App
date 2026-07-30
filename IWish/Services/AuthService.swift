import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit
import os.log

private let authLog = Logger(subsystem: "RUGyron.IWish", category: "Auth")

@Observable
@MainActor
final class AuthService: NSObject {
    var userName: String?
    var isLoading: Bool = true
    /// v1.1: gate — если юзер залогинен, но имя не получено, требуется re-auth.
    /// Сценарий: повторный sign-in после удаления Keychain — Apple credential.fullName == nil.
    var requiresNameRecovery: Bool = false
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
    private weak var firestore: FirestoreService?

    func attach(firestore: FirestoreService) {
        self.firestore = firestore
    }

    /// Firebase Web API key — НЕ secret (REST-key, не service-account), но единственный
    /// источник правды — `GoogleService-Info.plist`. Раньше дублировался hardcoded.
    private static let apiKey: String = {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["API_KEY"] as? String, !key.isEmpty else {
            // Это не должно случиться в production (plist обязателен для FirebaseApp.configure).
            // Fallback на пустую строку даст 401 от Identity Toolkit — поведение очевидно для дебага.
            return ""
        }
        return key
    }()

    override init() {
        super.init()

        // Migration: перенести legacy UserDefaults["auth_userName"] в iCloud Keychain
        if KeychainService.loadUserName() == nil,
           let legacyName = UserDefaults.standard.string(forKey: "auth_userName"),
           !legacyName.isEmpty {
            KeychainService.saveUserName(legacyName)
            UserDefaults.standard.removeObject(forKey: "auth_userName")
        }

        // v1.1: стереть legacy "Пользователь" мусор (был fallback в старых версиях AuthService).
        // Этот же литерал шифровался в ownerName/addedByName payload'ы и распространялся в shared.
        if KeychainService.loadUserName() == "Пользователь" {
            KeychainService.deleteUserName()
            UserDefaults.standard.removeObject(forKey: "auth_userName")
        }

        // Основной источник имени — iCloud Keychain (sync между Apple ID девайсами).
        // Fallback на UserDefaults если Keychain ещё не синкнулся (но новые записи туда НЕ пишем).
        userName = KeychainService.loadUserName()
            ?? UserDefaults.standard.string(forKey: "auth_userName")

        if let user = Auth.auth().currentUser, !user.isAnonymous {
            _uid = user.uid
            _isAppleSignedIn = true
            authLog.info("Found Keychain session: \(user.uid, privacy: .private)")
            // Splash ВСЕГДА снимается мгновенно. Network-операции (token refresh, имя из
            // Firestore, userLocale) в фоне — не блокируют UI. Если имени нет нигде, gate
            // на NameRecovery поставит фоновая задача, юзер увидит main UI на пару секунд
            // и потом shield, что лучше чем минута splash на data-loss.
            if userName != nil && userName != "Пользователь" {
                requiresNameRecovery = false
            }
            isLoading = false
            Task { await verifyAndRestore(uid: user.uid) }
        } else {
            isLoading = false
            authLog.info("No session, will show Sign in with Apple")
        }
    }

    /// Restore session. Trust Firebase SDK + iCloud Keychain.
    /// Имя приходит из iCloud Keychain (синкается между девайсами того же Apple ID).
    /// Fallback — Firebase Auth displayName (Apple передал его при первом sign-in
    /// и Firebase сохранил на серверной стороне у себя). Это решает кейс когда
    /// юзер уже логинился раньше, но Keychain не синкнулся (или был стёрт).
    private func verifyAndRestore(uid: String) async {
        _isAppleSignedIn = true
        await refreshToken()

        // На случай если Keychain синкнулся уже после init() — перечитываем.
        if userName == nil {
            userName = KeychainService.loadUserName()
        }

        // Fallback на Firebase displayName — Apple отдал его при первом sign-in,
        // Firebase Auth хранит у себя.
        if userName == nil, let dn = Auth.auth().currentUser?.displayName, !dn.isEmpty {
            userName = dn
            KeychainService.saveUserName(dn)
            authLog.info("Restored name from Firebase displayName: \(dn, privacy: .private)")
        }

        // Серверный fallback: users/{uid}.displayName в Firestore (открытое поле, пишется
        // при первом sign-in). Покрывает кейс: новый девайс / Keychain не синкнулся / Firebase
        // displayName потерян. Имя в Firestore — серверная истина пока юзер сам не удалил аккаунт.
        if userName == nil, let fs = firestore {
            if let dn = try? await fs.fetchUserDisplayName(uid: uid), !dn.isEmpty, dn != "Пользователь" {
                userName = dn
                KeychainService.saveUserName(dn)
                authLog.info("Restored name from Firestore users/\(uid, privacy: .private).displayName")
            }
        }

        // v1.1: имя — обязательное условие. Если не получили — gate на re-auth.
        if userName == nil || userName == "Пользователь" {
            requiresNameRecovery = true
            authLog.info("No usable name after restore — requiring name recovery")
        } else {
            requiresNameRecovery = false
        }

        // Освежить userLocale при каждом restore — юзер мог сменить язык iPhone'а.
        // Серверный CF использует это для locale-aware push wording.
        if let fs = firestore {
            try? await fs.setUserLocale(uid: uid, locale: CurrentLocale.identifier())
        }

        authLog.info("Restored: uid=\(uid, privacy: .private), name=\(self.userName ?? "nil", privacy: .private)")
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
            authLog.warning("Token refresh failed: \(error.localizedDescription, privacy: .public)")
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
            authLog.info("Apple sign-in OK, uid=\(self._uid ?? "nil", privacy: .private)")

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

            // 3. Try iCloud Keychain (если юзер уже логинился на этом или другом девайсе).
            // v1.1: legacy "Пользователь" в Keychain игнорируем — это мусор.
            if resolvedName == nil {
                let kc = KeychainService.loadUserName()
                if let kc, !kc.isEmpty, kc != "Пользователь" {
                    resolvedName = kc
                }
            }

            // 4. Серверная истина: users/{uid}.displayName в Firestore. Пишется ниже после
            //    первого успешного sign-in и не стирается при signOut → выдерживает любой
            //    перелогин/новый девайс пока юзер сам не удалил аккаунт.
            if resolvedName == nil, let fs = firestore {
                if let dn = try? await fs.fetchUserDisplayName(uid: authResult.user.uid),
                   !dn.isEmpty, dn != "Пользователь" {
                    resolvedName = dn
                    authLog.info("Resolved name from Firestore users/{uid}.displayName")
                }
            }

            // v1.1: имя — обязательное условие. Без него gate на re-auth, не fallback на email/"Пользователь".
            // (Email от Apple через privaterelay = бессмысленный hash-prefix, не показываем.)
            if let finalName = resolvedName, !finalName.isEmpty, finalName != "Пользователь" {
                userName = finalName
                KeychainService.saveUserName(finalName)
                requiresNameRecovery = false

                // Persist в Firebase Auth profile (серверная истина) — Apple отдаёт fullName
                // только при ПЕРВОМ sign-in, дальше credential.fullName == nil навсегда.
                // Firebase сам собирает displayName из credential.fullName на первом signIn,
                // но не всегда надёжно (PersonNameComponents vs String) — пишем явно.
                if authResult.user.displayName != finalName {
                    let change = authResult.user.createProfileChangeRequest()
                    change.displayName = finalName
                    try? await change.commitChanges()
                }

                // Persist в Firestore users/{uid}.displayName — наш собственный серверный fallback.
                // Открытым полем (не E2E), это OK: имя нужно для атрибуции в shared и push wording.
                if let fs = firestore {
                    try? await fs.setUserDisplayName(uid: authResult.user.uid, displayName: finalName)
                    // userLocale — для locale-aware push в Cloud Function.
                    try? await fs.setUserLocale(uid: authResult.user.uid, locale: CurrentLocale.identifier())
                }
            } else {
                userName = nil
                requiresNameRecovery = true
                authLog.info("Sign-in без имени — переход в name recovery flow")
            }

        case .failure(let error):
            throw error
        }
    }

    /// Лучшее имя, которое можно подписать под items этого юзера прямо сейчас.
    /// Порядок: Keychain (синкнутое) → Firebase displayName → email-prefix.
    /// Используется в DataService.addItem, чтобы атрибуция работала даже когда
    /// Apple credential не передал имя на повторном sign-in.
    func bestDisplayName() -> String? {
        if let name = userName, !name.isEmpty { return name }
        if let dn = Auth.auth().currentUser?.displayName, !dn.isEmpty { return dn }
        if let email = Auth.auth().currentUser?.email,
           let prefix = email.components(separatedBy: "@").first,
           !prefix.isEmpty {
            return prefix
        }
        return nil
    }

    func signOut() throws {
        try Auth.auth().signOut()
        _uid = nil
        _idToken = nil
        _refreshToken = nil
        _isAppleSignedIn = false
        userName = nil
        requiresNameRecovery = false
        // НЕ стираем displayName из iCloud Keychain / Firestore / Firebase Auth profile.
        // Apple отдаёт fullName ТОЛЬКО при первом sign-in навсегда — если мы потеряем имя
        // при signOut, повторный signIn покажет shield "удалите прилу". Это была плохая UX:
        // имя — серверная истина, привязанная к Apple userIdentifier; стираем её только
        // при полном удалении аккаунта (AccountDeletionService).
        // UserDefaults["auth_userName"] не трогаем — legacy migration ключ.
    }

    enum AuthError: LocalizedError {
        case missingCredential
        case notAuthenticated

        var errorDescription: String? {
            switch self {
            case .missingCredential: return String(localized: "Couldn’t get Apple ID data")
            case .notAuthenticated: return String(localized: "Sign in with Apple ID is required")
            }
        }
    }

    // MARK: - Helpers

    private func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
