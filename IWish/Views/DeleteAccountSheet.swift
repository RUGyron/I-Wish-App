import SwiftUI
import AuthenticationServices
import CryptoKit

/// Re-auth + удаление аккаунта (Apple Guideline 5.1.1(v)).
/// Свой nonce + SIWA-кнопка → AccountDeletionService.deleteAccount.
struct DeleteAccountSheet: View {
    let onComplete: (Result<Void, Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var rawNonce: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 56))
                .foregroundStyle(.red)

            Text("Delete account")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("Will be deleted permanently:")
                    .font(.subheadline.weight(.medium))
                Label("All your wishlists and items", systemImage: "list.bullet")
                Label("All shared lists you own", systemImage: "person.2")
                Label("Your membership in other people’s lists", systemImage: "person.crop.circle.badge.minus")
                Label("Encryption keys from iCloud Keychain", systemImage: "key")
                Label("Your Apple ID account for this app", systemImage: "applelogo")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)

            Text("This action is irreversible. Confirm with Apple ID to continue.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if isDeleting {
                ProgressView("Deleting account…")
                    .padding(.vertical, 8)
            } else {
                SignInWithAppleButton(.continue) { request in
                    let nonce = Self.randomNonce()
                    rawNonce = nonce
                    request.requestedScopes = []
                    request.nonce = Self.sha256(nonce)
                } onCompletion: { result in
                    handleAppleResult(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .padding(.horizontal, 32)
            }

            Button("Cancel") {
                dismiss()
            }
            .disabled(isDeleting)
            .padding(.bottom, 8)

            Spacer()
        }
        .fontDesign(.rounded)
        .interactiveDismissDisabled(isDeleting)
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = String(localized: "Couldn’t get Apple ID data")
                return
            }
            isDeleting = true
            errorMessage = nil
            Task {
                do {
                    try await services.accountDeletion.deleteAccount(
                        appleCredential: credential,
                        rawNonce: rawNonce
                    )
                    onComplete(.success(()))
                    dismiss()
                } catch {
                    isDeleting = false
                    errorMessage = error.localizedDescription
                    onComplete(.failure(error))
                }
            }
        case .failure(let error):
            // Юзер мог отменить — не показываем как ошибку
            let nsError = error as NSError
            if nsError.code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
