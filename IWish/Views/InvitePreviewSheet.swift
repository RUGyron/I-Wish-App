import SwiftUI

struct InvitePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let info: FirestoreService.ShareLinkInfo
    let onAccept: () -> Void

    @State private var isAccepting = false

    private let brand = Color(red: 0.72, green: 0.38, blue: 0.06)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                heroSection
                contentSection
            }
            .background(Theme.background)
            .navigationTitle("Приглашение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .fontDesign(.rounded)
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            // Warm amber gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.93, blue: 0.84),
                    Color(red: 0.93, green: 0.83, blue: 0.68)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Cover: emoji or palette gradient (same as HomeView tiles)
            coverView
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }

    @ViewBuilder
    private var coverView: some View {
        if let emoji = info.wishlistEmoji, !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: 64))
        } else {
            // Same palette as DefaultCoverGenerator — identical colors everywhere
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

    // MARK: - Content

    private var contentSection: some View {
        VStack(spacing: 0) {
            // Wishlist name
            Text(info.wishlistName)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.top, 28)
                .padding(.horizontal, 24)

            // Info card
            infoCard
                .padding(.top, 20)
                .padding(.horizontal, 24)

            Spacer(minLength: 24)

            // Buttons
            acceptButton
                .padding(.horizontal, 24)

            Button { dismiss() } label: {
                Text("Отклонить")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let owner = info.ownerName, !owner.isEmpty {
                Label {
                    Text("\(owner) приглашает тебя")
                } icon: {
                    Image(systemName: "person.fill")
                        .foregroundStyle(brand)
                }
            }

            Label {
                Text("Роль: \(info.role == "editor" ? "Редактор" : "Только просмотр")")
            } icon: {
                Image(systemName: info.role == "editor" ? "pencil" : "eye")
                    .foregroundStyle(brand)
            }

            if info.itemCount > 0 {
                Label {
                    Text("\(info.itemCount) \(wishWord(info.itemCount)) в списке")
                } icon: {
                    Image(systemName: "gift.fill")
                        .foregroundStyle(brand)
                }
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Accept Button

    private var acceptButton: some View {
        Button {
            guard !isAccepting else { return }
            isAccepting = true
            onAccept()
        } label: {
            ZStack {
                // Always reserve space for text height
                Text("Принять приглашение")
                    .opacity(isAccepting ? 0 : 1)

                if isAccepting {
                    ProgressView()
                        .tint(.white)
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
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
