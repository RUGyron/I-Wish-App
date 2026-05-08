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
                        icon: "lock.fill",
                        title: "Контент шифруется на устройстве",
                        body: "Имена списков, желания, фотки, цены, описания, ссылки — всё шифруется AES-256 прямо на вашем iPhone до того, как улетит в облако. На сервере хранятся только нечитаемые байты."
                    )

                    section(
                        icon: "icloud.fill",
                        title: "Ключи живут в iCloud Keychain",
                        body: "Ключ шифрования каждого списка генерируется локально и сохраняется в iCloud Keychain. Apple синхронизирует его между вашими Apple ID устройствами через end-to-end защищённый канал. Apple ключи видит только в зашифрованном виде, разработчик — никогда."
                    )

                    section(
                        icon: "server.rack",
                        title: "Что мы видим в облаке",
                        body: "Данные хранятся в Google Firebase. Разработчик через консоль Firebase может узнать только техническую информацию: количество списков, время создания, размер зашифрованных блобов и связи «кто с кем поделился». Содержимое — нет."
                    )

                    section(
                        icon: "person.text.rectangle",
                        title: "Имя в общих списках",
                        body: "Если вы делитесь списком, ваше имя записывается в Firebase в открытом виде в документ membership — чтобы участники видели реальные имена друг друга. Без этого они отображались бы как безличный «Участник». Имя не привязано к содержимому списков, разработчик видит только сами имена. Если списками не делитесь — имя в Firebase не попадает."
                    )

                    section(
                        icon: "qrcode",
                        title: "Шеринг через QR-код",
                        body: "Когда вы делитесь списком, ключ шифрования встраивается в QR-код или ссылку (после `#`) и не отправляется на сервер. Получатель сканирует QR — ключ оказывается у него локально, и его iPhone сам расшифровывает содержимое."
                    )

                    section(
                        icon: "exclamationmark.triangle.fill",
                        title: "У нас нет копии ваших ключей",
                        body: "Если вы потеряете все Apple ID устройства и сбросите iCloud Keychain — данные станут нечитаемыми навсегда. Это плата за то, что разработчик никогда не может в них заглянуть."
                    )

                    section(
                        icon: "eye.slash.fill",
                        title: "Без трекинга и аналитики",
                        body: "Никакой аналитики, крашлитики, рекламы. Приложение общается только с серверами Firebase для синхронизации (зашифрованной) и Apple для авторизации."
                    )
                }
                .padding(.horizontal)

                VStack(spacing: 8) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("Исходный код открыт и проверяем")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("github.com/RUGyron/I-Wish-App")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
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
