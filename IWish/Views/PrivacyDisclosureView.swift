import SwiftUI

struct PrivacyDisclosureView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                    Text("Ваши данные — только ваши")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)

                Group {
                    section(
                        icon: "icloud.slash",
                        title: "Мы ничего не храним",
                        body: "У нас нет своего сервера. Приложение использует только ваш личный iCloud — как iPhone-заметки."
                    )

                    section(
                        icon: "key.fill",
                        title: "Всё зашифровано",
                        body: "Ваши списки, желания, цены, картинки — всё шифруется на устройстве ключами из вашего iCloud Keychain. Ни Apple, ни разработчик прочитать не могут."
                    )

                    section(
                        icon: "chart.bar.xaxis",
                        title: "Мы видим только цифры",
                        body: "Через Apple CloudKit разработчик может узнать только количество активных пользователей и объём использованной iCloud-квоты — без имён и без содержимого."
                    )

                    section(
                        icon: "person.2.fill",
                        title: "Шеринг безопасен",
                        body: "Когда делитесь списком — Apple безопасно передаёт ключи шифрования только выбранным участникам. Остальные (включая разработчика) не видят ничего."
                    )

                    section(
                        icon: "eye.slash.fill",
                        title: "Без трекинга и аналитики",
                        body: "Нет SDK аналитики, нет крашлитики, нет рекламы. Приложение не отправляет никаких запросов на серверы разработчика."
                    )
                }
                .padding(.horizontal)

                Text("Исходный код приложения открыт и проверяем: github.com/RUGyron/I-Wish-App")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .background(Theme.background)
        .navigationTitle("Как мы храним данные")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
