import SwiftUI
import SwiftData

struct ParticipantsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    let wishlist: Wishlist
    var onShareRequested: (() -> Void)? = nil

    @State private var members: [(userUID: String, role: String, name: String)] = []
    @State private var isLoading = true
    @State private var ownerName: String?
    @State private var ownerUID: String?
    @State private var pollTimer: Timer?
    private var isCurrentUserOwner: Bool { ownerUID == services.auth.uid }

    var body: some View {
        NavigationStack {
            List {
                // Owner
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
                                Text(ownerName ?? "Владелец")
                                    .font(.body.weight(.medium))
                                if ownerUID == services.auth.uid {
                                    Text("(это вы)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("(владелец)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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
                                        Text(member.name)
                                            .font(.body.weight(.medium))
                                        Text(roleBadge(for: member.role))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                // Kick (owner only, not self)
                                if isCurrentUserOwner && member.userUID != services.auth.uid {
                                    Button {
                                        kickMember(userUID: member.userUID)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                }
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
                await fetchMembers()
            }
            .onAppear { startPolling() }
            .onDisappear { stopPolling() }
        }
        .applyTheme()
    }

    // MARK: - Polling

    private func startPolling() {
        // 30 сек — список участников меняется редко, нет смысла поллить чаще.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                await fetchMembers()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func fetchMembers() async {
        do {
            let sharedID = wishlist.sharedWishlistID ?? wishlist.id.uuidString
            // Ключ wishlist'а нужен для расшифровки encryptedPayload (включая ownerName).
            // Без ключа просто пропускаем — последний известный список members останется.
            guard let key = KeychainService.load(for: sharedID) else {
                isLoading = false
                return
            }
            let info = try await services.firestore.fetchSharedWishlist(
                wishlistID: sharedID,
                key: key
            )

            // Set owner info: ownerName приходит расшифрованным из payload SharedWishlistInfo.
            ownerUID = info.ownerUID
            ownerName = info.ownerName ?? "Владелец"

            // Filter out the owner — they're shown in the owner section
            let nonOwnerMembers = info.members.filter { $0.userUID != info.ownerUID }

            // Имена members сейчас зашифрованно нигде не лежат (см. TODO в FirestoreService:
            // member-имена требуют отдельного key-exchange механизма). Для self берём локальное
            // userName, для остальных — fallback "Участник".
            let myUID = services.auth.uid
            let myName = services.auth.userName
            var resolved: [(userUID: String, role: String, name: String)] = []
            for member in nonOwnerMembers {
                let name: String
                if member.userUID == myUID, let myName, !myName.isEmpty {
                    name = myName
                } else {
                    name = "Участник"
                }
                resolved.append((userUID: member.userUID, role: member.role, name: name))
            }
            members = resolved
        } catch {
            // Don't clear members on poll failure — keep last known state
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func kickMember(userUID: String) {
        guard let sharedID = wishlist.sharedWishlistID else { return }
        Task {
            do {
                try await services.firestore.leaveWishlist(wishlistID: sharedID, userUID: userUID)
                await fetchMembers()
            } catch {
                // silent — member removed
            }
        }
    }

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
