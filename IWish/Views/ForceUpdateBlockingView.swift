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
                Text("Update I Wish")
                    .font(.title2.weight(.semibold))

                Text(message ?? String(localized: "You have an outdated version. Please update to continue."))
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
                Text("Open App Store")
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
