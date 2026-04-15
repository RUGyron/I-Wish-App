import SwiftUI

struct DiscoverabilitySheet: View {
    let onAllow: () -> Void
    let onDeny: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.top, 40)

            VStack(spacing: 12) {
                Text("Показать ваше имя")
                    .font(.title2.weight(.semibold))
                Text("Чтобы сохранять ваши списки в iCloud, делиться ими с другими и видеть участников по именам — нужно разрешить приложению узнать ваше имя из iCloud.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 16) {
                infoRow(icon: "icloud", title: "Только имя", subtitle: "Никаких других данных не передаём")
                infoRow(icon: "lock.shield", title: "Всё зашифровано", subtitle: "Мы не видим содержимое ваших списков")
                infoRow(icon: "person.2", title: "Для шеринга", subtitle: "Участники увидят ваше имя")
            }
            .padding(.horizontal, 24)
            .padding(.vertical)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    onAllow()
                    dismiss()
                } label: {
                    Text("Разрешить")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }

                Button {
                    onDeny()
                    dismiss()
                } label: {
                    Text("Не сейчас")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .fontDesign(.rounded)
    }

    private func infoRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
