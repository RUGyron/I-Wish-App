import SwiftUI

struct ForceUpdateBlockingView: View {
    let message: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                Text("Обновите I Wish")
                    .font(.title2.weight(.semibold))

                Text(message ?? "Установлена устаревшая версия. Обновитесь, чтобы продолжить.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                if let url = URL(string: "https://apps.apple.com/app/id6762267281") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Открыть App Store")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .applyTheme()
    }
}
