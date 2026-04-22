import SwiftUI
import AuthenticationServices

struct SignInWithAppleSheet: View {
    let onComplete: (Result<ASAuthorization, Error>) -> Void
    var onSkip: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Войдите через Apple")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Для создания и просмотра общих списков желаний нужен Apple ID. Ваше имя будет видно участникам.")
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
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 32)

            if onSkip != nil {
                Button("Не сейчас") {
                    onSkip?()
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .fontDesign(.rounded)
    }
}
