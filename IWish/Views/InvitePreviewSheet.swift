import SwiftUI

struct InvitePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let info: CloudKitSharingService.ShareLinkInfo
    let onAccept: () -> Void

    @State private var isAccepting = false
    @State private var error: String?

    private let brand = Color(red: 0.72, green: 0.38, blue: 0.06)
    private let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.93, blue: 0.84),
            Color(red: 0.93, green: 0.83, blue: 0.68)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Hero section with gradient background
                ZStack {
                    heroGradient
                        .ignoresSafeArea(edges: .top)

                    heroIcon
                        .padding(.vertical, 40)
                }
                .frame(maxWidth: .infinity)

                // Content area
                VStack(spacing: 20) {

                    // Wishlist name
                    Text(info.wishlistName)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                    // Info card
                    VStack(alignment: .leading, spacing: 14) {
                        if let owner = info.ownerName, !owner.isEmpty {
                            Label("\(owner) приглашает тебя", systemImage: "person.fill")
                                .foregroundStyle(.primary)
                        }

                        Label("Роль: \(roleDisplayName(info.role))", systemImage: "pencil")
                            .foregroundStyle(.primary)

                        if info.itemCount > 0 {
                            Label("\(info.itemCount) \(wishWord(info.itemCount)) в списке", systemImage: "gift.fill")
                                .foregroundStyle(.primary)
                        }
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                    )

                    Spacer()

                    // Error
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }

                    // Accept button
                    Button {
                        isAccepting = true
                        error = nil
                        onAccept()
                    } label: {
                        Group {
                            if isAccepting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Принять приглашение")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(brand)
                    .disabled(isAccepting)

                    // Decline button
                    Button {
                        dismiss()
                    } label: {
                        Text("Отклонить")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
                .background(Theme.background)
            }
            .navigationTitle("Приглашение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
        .fontDesign(.rounded)
    }

    // MARK: - Hero Icon

    @ViewBuilder
    private var heroIcon: some View {
        if let emoji = info.wishlistEmoji, !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: 72))
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [brand.opacity(0.25), brand.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 110, height: 110)

                Image(systemName: "gift.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(brand)
            }
        }
    }

    // MARK: - Helpers

    private func roleDisplayName(_ role: String) -> String {
        role.lowercased() == "editor" ? "Редактор" : "Только просмотр"
    }

    private func wishWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 {
            return "желание"
        } else if mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14) {
            return "желания"
        } else {
            return "желаний"
        }
    }
}
