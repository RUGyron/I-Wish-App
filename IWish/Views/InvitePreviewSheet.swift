import SwiftUI

struct InvitePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let info: FirestoreService.ShareLinkInfo
    let onAccept: () -> Void

    @State private var isAccepting = false

    private let brand = Color(red: 0.72, green: 0.38, blue: 0.06)

    var body: some View {
        VStack(spacing: 20) {
            // Cover
            coverView
                .padding(.top, 24)

            // Name
            Text(info.wishlistName)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Info rows
            VStack(alignment: .leading, spacing: 10) {
                if let owner = info.ownerName, !owner.isEmpty {
                    infoRow(icon: "person.fill", text: "\(owner) приглашает")
                }
                infoRow(
                    icon: info.role == "editor" ? "pencil" : "eye",
                    text: info.role == "editor" ? "Редактор" : "Только просмотр"
                )
                if info.itemCount > 0 {
                    infoRow(icon: "gift.fill", text: "\(info.itemCount) \(wishWord(info.itemCount))")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 20)

            Spacer()

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
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .loadingOverlay(isAccepting)
        .fontDesign(.rounded)
    }

    // MARK: - Cover

    @ViewBuilder
    private var coverView: some View {
        if let emoji = info.wishlistEmoji, !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: 56))
                .frame(width: 80, height: 80)
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
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Helpers

    private func infoRow(icon: String, text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(brand)
                .frame(width: 20)
        }
    }

    private func wishWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "желание" }
        if mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14) { return "желания" }
        return "желаний"
    }
}
