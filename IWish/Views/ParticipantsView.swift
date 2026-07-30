import SwiftUI
import SwiftData
import os.log

private let participantsLog = Logger(subsystem: "RUGyron.IWish", category: "ParticipantsView")

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
                                Text(ownerName ?? String(localized: "Owner"))
                                    .font(.body.weight(.medium))
                                if ownerUID == services.auth.uid {
                                    Text("(you)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("(owner)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("Full access")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Owner")
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
                                Text("Nobody invited yet")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Share the list via QR code or link")
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
                        Text("Participants")
                        Spacer()
                        Button {
                            dismiss()
                            onShareRequested?()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                Text("Invite")
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    .textCase(nil)
                }
            }
            .warmBackground()
            .navigationTitle("Participants")
            .navigationBarTitleDisplayMode(.inline)
            .fontDesign(.rounded)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await fetchMembers()
            }
            .onAppear { startPolling() }
            .onDisappear { stopPolling() }
            .confirmationDialog(
                "Remove participant from the list?",
                isPresented: Binding(
                    get: { memberToKick != nil },
                    set: { if !$0 { memberToKick = nil } }
                ),
                titleVisibility: .visible,
                presenting: memberToKick
            ) { target in
                Button("Remove", role: .destructive) {
                    performKick(userUID: target.userUID, name: target.name)
                }
                Button("Cancel", role: .cancel) {
                    memberToKick = nil
                }
            } message: { target in
                Text("“\(target.name)” will lose access to the list. To restore it, a new invitation will be required.")
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
                    Label("Remove", systemImage: "person.fill.xmark")
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
        // CLAMP: если member.role в Firestore содержит unknown значение (напр. "owner" из-за
        // прошлого owner-flip бага, или forward-compat unknown string) — отображаем least-privilege
        // "viewer". Иначе Picker не найдёт matching tag → оба chip серые.
        // Owner может затем тапнуть нужную роль → server PATCH самовосстановит запись.
        let rawRole = optimisticRoles[member.userUID] ?? member.role
        // Case-insensitive + trimmed для robustness против forward-compat / typos на сервере.
        let normalizedRaw = rawRole.trimmingCharacters(in: .whitespaces).lowercased()
        let displayRole: String = (normalizedRaw == "editor" || normalizedRaw == "viewer") ? normalizedRaw : "viewer"
        if displayRole != normalizedRaw, !rawRole.isEmpty {
            let _ = participantsLog.warning("memberControls: clamping unknown role '\(rawRole, privacy: .public)' → 'viewer' for member \(member.userUID, privacy: .public)")
        }
        let displayCanInvite = optimisticCanInvite[member.userUID] ?? member.canInvite
        let isLocked = pendingMutationUID == member.userUID

        ZStack {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Role", selection: Binding(
                    get: { displayRole },
                    set: { newRole in
                        guard newRole != displayRole else { return }
                        // Optimistic UI: моментально показываем новое значение, picker анимация идёт без задержки.
                        optimisticRoles[member.userUID] = newRole
                        performRoleChange(memberUID: member.userUID, newRole: newRole)
                    }
                )) {
                    Text("Editor").tag("editor")
                    Text("Viewer").tag("viewer")
                }
                .pickerStyle(.segmented)

                Toggle(isOn: Binding(
                    get: { displayCanInvite },
                    set: { newValue in
                        optimisticCanInvite[member.userUID] = newValue
                        performCanInviteChange(memberUID: member.userUID, canInvite: newValue)
                    }
                )) {
                    Label("Can invite", systemImage: "person.badge.plus")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                }
                .tint(Color(red: 0.72, green: 0.38, blue: 0.06))

                Button {
                    memberToKick = (userUID: member.userUID, name: member.name)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.xmark")
                        Text("Remove from list")
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

            // Set owner info.
            // SOURCE-OF-TRUTH для ownerName: сначала plaintext memberships.userName
            // (надёжнее — не может быть отравлен старым owner-flip багом, который
            // перезаписывал encryptedPayload.ownerName именем "флипера"). Если
            // membership с role="owner" у owner UID отсутствует — fallback на
            // encryptedPayload.ownerName, затем на дефолт.
            ownerUID = info.ownerUID
            let ownerMembership = info.members.first { $0.userUID == info.ownerUID && $0.role == "owner" }
            if let mname = ownerMembership?.userName, !mname.isEmpty {
                ownerName = mname
            } else {
                ownerName = info.ownerName ?? String(localized: "Owner")
            }

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
                    name = String(localized: "Participant")
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
        // Имя для toast — snapshot ДО запроса, чтобы текст был стабилен даже если member kicked в гонке.
        let memberName = members.first(where: { $0.userUID == memberUID })?.name ?? String(localized: "Participant")
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
                let label = newRole == "editor" ? String(localized: "editor") : String(localized: "viewer")
                toast.success(String(format: String(localized: "%@ is now %@"), memberName, label))
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
        // Idempotency guard (как в performRoleChange): rapid double-tap не отправит лишний PATCH.
        if let current = members.first(where: { $0.userUID == memberUID }), current.canInvite == canInvite {
            optimisticCanInvite.removeValue(forKey: memberUID)
            return
        }
        let memberName = members.first(where: { $0.userUID == memberUID })?.name ?? String(localized: "Participant")
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
                if canInvite {
                    toast.success(String(format: String(localized: "%@ can now invite others"), memberName))
                } else {
                    toast.success(String(format: String(localized: "%@ can no longer invite"), memberName))
                }
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
                toast.success(String(format: String(localized: "“%@” removed from the list"), name))
            } catch {
                toast.error(error.localizedDescription)
            }
            pendingMutationUID = nil
        }
    }

    // MARK: - Helpers

    private func roleBadge(for role: String) -> String {
        role == "editor" ? String(localized: "(editor)") : String(localized: "(viewer)")
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
