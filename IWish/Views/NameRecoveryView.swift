import SwiftUI

/// Показывается когда у залогиненного юзера не удалось получить имя
/// (Apple credential.fullName == nil + Firebase displayName пуст + Keychain пуст).
/// Юзер должен выйти и зайти заново, удалив "Sign in with Apple" в настройках iPhone.
struct NameRecoveryView: View {
    @Environment(\.appServices) private var services
    @Environment(\.toast) private var toast
    @State private var isSigningOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .padding(.top, 40)

                VStack(spacing: 12) {
                    Text("Не удалось получить ваше имя")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text("Apple Sign In передаёт имя только при первой авторизации. Чтобы получить имя заново — нужно сбросить связь с приложением.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Что нужно сделать:")
                        .font(.subheadline.weight(.semibold))
                    instructionRow(num: "1", text: "Удалите I Wish с устройства (зажмите иконку → «Удалить приложение»)")
                    instructionRow(num: "2", text: "Откройте «Настройки» → ваше имя сверху → «Вход с Apple»")
                    instructionRow(num: "3", text: "Найдите I Wish в списке → «Прекратить использовать Apple ID»")
                    instructionRow(num: "4", text: "Установите I Wish заново из App Store и войдите — Apple снова передаст имя")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Открыть Настройки", systemImage: "gearshape")
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
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .applyTheme()
    }

    @ViewBuilder
    private func instructionRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(num)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
