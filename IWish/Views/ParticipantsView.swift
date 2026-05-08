import SwiftUI
import SwiftData

struct ParticipantsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @Environment(\.toast) private var toast
    let wishlist: Wishlist
    var onShareRequested: (() -> Void)? = nil

    @State private var members: [(userUID: String, role: String, name: String, canInvite: Bool)] = []
    @State private var isLoading = true
    @State private var ownerName: String?
    @State private var ownerUID: String?
    @State private var pollTimer: Timer?
    /// userUID участника, по которому сейчас идёт mutation (changeRole / kick).
    /// Нужен чтобы заблокировать повторные тапы на той же строке и показать ProgressView.
    @State private var pendingMutationUID: String?
    /// Confirmation dialog: какого юзера собираемся кикнуть.
    @State private var memberToKick: (userUID: String, name: String)?
    /// userUID участника, чья панель прав сейчас раскрыта (только один за раз).
    @State private var expandedMemberUID: String?
    /// Optimistic UI: локальные значения picker'ов поверх server-state (пока запрос летит).
    /// При успехе — server догонит, optimistic value совпадёт с member.role.
    /// При ошибке — toast + revert через сброс ключа в этом dict.
    @State private var optimisticRoles: [String: String] = [:]
    @State private var optimisticCanInvite: [String: Bool] = [:]

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
                            memberRow(member: member)
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
            .confirmationDialog(
                "Удалить участника из списка?",
                isPresented: Binding(
                    get: { memberToKick != nil },
                    set: { if !$0 { memberToKick = nil } }
                ),
                titleVisibility: .visible,
                presenting: memberToKick
            ) { target in
                Button("Удалить", role: .destructive) {
                    performKick(userUID: target.userUID, name: target.name)
                }
                Button("Отмена", role: .cancel) {
                    memberToKick = nil
                }
            } message: { target in
                Text("«\(target.name)» потеряет доступ к списку. Чтобы вернуть — потребуется новое приглашение.")
            }
        }
        .applyTheme()
    }

    // MARK: - Member row

    @ViewBuilder
    private func memberRow(member: (userUID: String, role: String, name: String, canInvite: Bool)) -> some View {
        let canEdit = isCurrentUserOwner && member.userUID != services.auth.uid
        let isExpandedBinding = Binding<Bool>(
            get: { expandedMemberUID == member.userUID },
            set: { newValue in
                guard canEdit, pendingMutationUID == nil else { return }
                expandedMemberUID = newValue ? member.userUID : nil
            }
        )

        Group {
            if canEdit {
                DisclosureGroup(isExpanded: isExpandedBinding) {
                    memberControls(member: member)
                        .padding(.top, 8)
                } label: {
                    memberLabel(member: member)
                }
                .disclosureGroupStyle(.automatic)
                .tint(.secondary)
            } else {
                memberLabel(member: member)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEdit && pendingMutationUID != member.userUID {
                Button(role: .destructive) {
                    memberToKick = (userUID: member.userUID, name: member.name)
                } label: {
                    Label("Удалить", systemImage: "person.fill.xmark")
                }
            }
        }
    }

    @ViewBuilder
    private func memberLabel(member: (userUID: String, role: String, name: String, canInvite: Bool)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill.checkmark")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(.green.opacity(0.15))
                .clipShape(Circle())

            HStack(spacing: 4) {
                Text(member.name)
                    .font(.body.weight(.medium))
                Text(roleBadge(for: member.role))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func memberControls(member: (userUID: String, role: String, name: String, canInvite: Bool)) -> some View {
        let displayRole = optimisticRoles[member.userUID] ?? member.role
        let displayCanInvite = optimisticCanInvite[member.userUID] ?? member.canInvite
        let isLocked = pendingMutationUID == member.userUID

        ZStack {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Роль", selection: Binding(
                    get: { displayRole },
                    set: { newRole in
                        guard newRole != displayRole else { return }
                        // Optimistic UI: моментально показываем новое значение, picker анимация идёт без задержки.
                        optimisticRoles[member.userUID] = newRole
                        performRoleChange(memberUID: member.userUID, newRole: newRole)
                    }
                )) {
                    Text("Редактор").tag("editor")
                    Text("Зритель").tag("viewer")
                }
                .pickerStyle(.segmented)

                Toggle(isOn: Binding(
                    get: { displayCanInvite },
                    set: { newValue in
                        optimisticCanInvite[member.userUID] = newValue
                        performCanInviteChange(memberUID: member.userUID, canInvite: newValue)
                    }
                )) {
                    Label("Может приглашать", systemImage: "person.badge.plus")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                }
                .tint(Color(red: 0.72, green: 0.38, blue: 0.06))

                Button {
                    memberToKick = (userUID: member.userUID, name: member.name)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.xmark")
                        Text("Удалить из списка")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            // Поверх блока — overlay с ProgressView пока сетевой запрос летит.
            // Не блокирует анимацию picker'а / toggle'а (она уже произошла оптимистично).
            if isLocked {
                Color.black.opacity(0.001) // прозрачный hit-blocker
                    .contentShape(Rectangle())
                    .overlay(alignment: .center) {
                        ProgressView()
                            .controlSize(.regular)
                            .padding(10)
                            .background(.regularMaterial, in: Circle())
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isLocked)
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

            // Имена members теперь приходят из memberships document (поле userName,
            // backfill в v1.1). Для self берём актуальное services.auth.userName, для
            // legacy memberships без userName — fallback "Участник".
            let myUID = services.auth.uid
            let myName = services.auth.userName
            var resolved: [(userUID: String, role: String, name: String, canInvite: Bool)] = []
            for member in nonOwnerMembers {
                let name: String
                if member.userUID == myUID, let myName, !myName.isEmpty {
                    name = myName
                } else if let memberName = member.userName, !memberName.isEmpty {
                    name = memberName
                } else {
                    name = "Участник"
                }
                resolved.append((userUID: member.userUID, role: member.role, name: name, canInvite: member.canInvite))
            }
            members = resolved
        } catch {
            // Don't clear members on poll failure — keep last known state
        }
        isLoading = false
    }

    // MARK: - Mutations

    private func performRoleChange(memberUID: String, newRole: String) {
        guard let sharedID = wishlist.sharedWishlistID else { return }
        if let current = members.first(where: { $0.userUID == memberUID }), current.role == newRole {
            optimisticRoles.removeValue(forKey: memberUID)
            return
        }
        pendingMutationUID = memberUID
        Task {
            do {
                try await services.data.changeMemberRole(
                    wishlistID: sharedID,
                    memberUID: memberUID,
                    newRole: newRole
                )
                await fetchMembers()
                optimisticRoles.removeValue(forKey: memberUID)
                let label = newRole == "editor" ? "редактором" : "зрителем"
                toast.success("Участник теперь \(label)")
            } catch {
                // Revert: optimistic value сброс → picker анимированно вернётся в server-state.
                optimisticRoles.removeValue(forKey: memberUID)
                toast.error(error.localizedDescription)
            }
            pendingMutationUID = nil
        }
    }

    private func performCanInviteChange(memberUID: String, canInvite: Bool) {
        guard let sharedID = wishlist.sharedWishlistID else { return }
        pendingMutationUID = memberUID
        Task {
            do {
                try await services.data.changeMemberCanInvite(
                    wishlistID: sharedID,
                    memberUID: memberUID,
                    canInvite: canInvite
                )
                await fetchMembers()
                optimisticCanInvite.removeValue(forKey: memberUID)
                toast.success(canInvite ? "Может приглашать других" : "Не может приглашать других")
            } catch {
                optimisticCanInvite.removeValue(forKey: memberUID)
                toast.error(error.localizedDescription)
            }
            pendingMutationUID = nil
        }
    }

    private func performKick(userUID: String, name: String) {
        guard let sharedID = wishlist.sharedWishlistID else { return }
        memberToKick = nil
        pendingMutationUID = userUID
        Task {
            do {
                try await services.data.kickMember(
                    wishlistID: sharedID,
                    memberUID: userUID
                )
                // Локально убираем сразу — fetchMembers догонит из Firestore через 30s,
                // но пользователь должен видеть результат немедленно.
                members.removeAll { $0.userUID == userUID }
                toast.success("«\(name)» удалён из списка")
            } catch {
                toast.error(error.localizedDescription)
            }
            pendingMutationUID = nil
        }
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
