import SwiftUI

struct InvitePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let info: FirestoreService.ShareLinkInfo
    let onAccept: () -> Void

    @State private var isAccepting = false

    private let brand = Color(red: 0.72, green: 0.38, blue: 0.06)

    private var heroBg: Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.10, blue: 0.05)
            : Color(red: 0.96, green: 0.92, blue: 0.85)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Hero
            ZStack {
                heroBg
                coverView
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)

            // Name
            Text(info.wishlistName)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .padding(.horizontal, 24)

            // Info
            infoCard
                .padding(.top, 16)
                .padding(.horizontal, 20)

            Spacer(minLength: 20)

            // Accept
            Button {
                guard !isAccepting else { return }
                isAccepting = true
                onAccept()
            } label: {
                Text("Принять приглашение")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isAccepting)
            .padding(.horizontal, 20)

            // Decline
            Button { dismiss() } label: {
                Text("Отклонить")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .loadingOverlay(isAccepting)
        .fontDesign(.rounded)
    }

    // MARK: - Cover

    @ViewBuilder
    private var coverView: some View {
        if let emoji = info.wishlistEmoji, !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: 56))
        } else {
            let colors = DefaultCoverGenerator.colors(forSeed: info.gradientSeed)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    .init(0, 0),   .init(0.5, 0),   .init(1, 0),
                    .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                    .init(0, 1),   .init(0.5, 1),   .init(1, 1),
                ],
                colors: [
                    colors[0], colors[1], colors[2],
                    colors[1], colors[2], colors[0],
                    colors[2], colors[0], colors[1],
                ]
            )
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let owner = info.ownerName, !owner.isEmpty {
                row(icon: "person.fill", text: "\(owner) приглашает")
            }
            row(
                icon: info.role == "editor" ? "pencil" : "eye",
                text: info.role == "editor" ? "Редактор" : "Только просмотр"
            )
            if info.itemCount > 0 {
                row(icon: "gift.fill", text: "\(info.itemCount) \(wishWord(info.itemCount))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func row(icon: String, text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(brand)
                .frame(width: 20)
        }
    }

    // MARK: - Helpers

    private func wishWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "желание" }
        if mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14) { return "желания" }
        return "желаний"
    }
}
