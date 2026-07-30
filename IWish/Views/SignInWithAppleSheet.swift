import SwiftUI
import AuthenticationServices

struct SignInWithAppleSheet: View {
    let onComplete: (Result<ASAuthorization, Error>) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Sign in with Apple")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("An Apple ID is required to use the app. Your data is securely protected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            SignInWithAppleButton(.signIn) { request in
                let appleRequest = AppServices.shared.auth.startSignInWithApple()
                request.requestedScopes = appleRequest.requestedScopes
                request.nonce = appleRequest.nonce
            } onCompletion: { result in
                onComplete(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .padding(.horizontal, 32)

            Spacer()
        }
        .fontDesign(.rounded)
    }
}
