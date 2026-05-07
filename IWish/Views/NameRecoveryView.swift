import SwiftUI

/// Показывается когда у залогиненного юзера не удалось получить имя
/// (Apple credential.fullName == nil + Firebase displayName пуст + Keychain пуст).
/// Юзер должен выйти и зайти заново, удалив "Sign in with Apple" в настройках iPhone.
struct NameRecoveryView: View {
    @Environment(\.appServices) private var services
    @Environment(\.toast) private var toast
    @State private var isSigningOut = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                Text("Не удалось получить ваше имя")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Apple Sign In не передал имя при входе. Это происходит при повторной авторизации — Apple отдаёт имя только при первом входе.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Чтобы починить:\n1. Откройте Настройки → Apple ID → Вход с Apple\n2. Найдите I Wish и нажмите «Прекратить использовать»\n3. Вернитесь сюда и войдите заново")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                Button {
                    if let url = URL(string: "App-Prefs:APPLE_ACCOUNT") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Открыть настройки Apple ID", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    isSigningOut = true
                    do {
                        try services.auth.signOut()
                    } catch {
                        toast.error("Не удалось выйти: \(error.localizedDescription)")
                    }
                    isSigningOut = false
                } label: {
                    Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isSigningOut)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .applyTheme()
    }
}
