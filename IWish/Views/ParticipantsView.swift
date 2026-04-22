import SwiftUI
import SwiftData

struct ParticipantsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    let wishlist: Wishlist
    var onShareRequested: (() -> Void)? = nil

    @State private var members: [(userUID: String, role: String)] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                // Owner (current user)
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.title3)
                            .foregroundStyle(.yellow)
                            .frame(width: 36, height: 36)
                            .background(.yellow.opacity(0.15))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(services.userProfile.userName ?? "Вы")
                                    .font(.body.weight(.medium))
                                Text("(владелец)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Полный доступ")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Владелец")
                }

                // Members
                Section {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 24)
                            Spacer()
                        }
                    } else if members.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)

                            VStack(spacing: 4) {
                                Text("Пока никто не приглашён")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Поделитесь списком по QR-коду или ссылке")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(Array(members.enumerated()), id: \.offset) { _, member in
                            HStack(spacing: 12) {
                                Image(systemName: "person.fill.checkmark")
                                    .font(.title3)
                                    .foregroundStyle(.green)
                                    .frame(width: 36, height: 36)
                                    .background(.green.opacity(0.15))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text("Участник")
                                            .font(.body.weight(.medium))
                                        Text(roleBadge(for: member.role))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    HStack {
                        Text("Участники")
                        Spacer()
                        Button {
                            dismiss()
                            onShareRequested?()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                Text("Пригласить")
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    .textCase(nil)
                }
            }
            .warmBackground()
            .navigationTitle("Участники")
            .navigationBarTitleDisplayMode(.inline)
            .fontDesign(.rounded)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task {
                do {
                    let sharedID = wishlist.sharedWishlistID ?? wishlist.id.uuidString
                    let info = try await services.firestore.fetchSharedWishlist(
                        wishlistID: sharedID
                    )
                    // Filter out the owner — they're shown in the owner section
                    members = info.members.filter { $0.userUID != info.ownerUID }
                } catch {
                    members = []
                }
                isLoading = false
            }
        }
        .applyTheme()
    }

    // MARK: - Helpers

    private func roleBadge(for role: String) -> String {
        role == "editor" ? "(редактор)" : "(зритель)"
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Wishlist.self, Item.self, AppSettings.self,
        configurations: config
    )

    let wishlist = Wishlist(name: "День рождения")
    container.mainContext.insert(wishlist)
    try? container.mainContext.save()

    return ParticipantsView(wishlist: wishlist, onShareRequested: {})
        .modelContainer(container)
}
