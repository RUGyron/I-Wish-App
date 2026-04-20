import CloudKit
import SwiftUI
import SwiftData

struct ParticipantsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    let wishlist: Wishlist
    var onShareRequested: (() -> Void)? = nil

    @State private var participants: [CloudKitSharingService.ParticipantInfo] = []
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

                // Participants
                Section {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 24)
                            Spacer()
                        }
                    } else if participants.isEmpty {
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
                        ForEach(Array(participants.enumerated()), id: \.offset) { _, participant in
                            HStack(spacing: 12) {
                                Image(systemName: participantIcon(for: participant.acceptance))
                                    .font(.title3)
                                    .foregroundStyle(participantColor(for: participant.acceptance))
                                    .frame(width: 36, height: 36)
                                    .background(participantColor(for: participant.acceptance).opacity(0.15))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(participant.name ?? "Участник")
                                            .font(.body.weight(.medium))
                                        Text(roleBadge(for: participant.role))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(acceptanceLabel(for: participant.acceptance))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                participants = await services.sharing.fetchParticipants(for: wishlist.id)
                isLoading = false
            }
        }
        .applyTheme()
    }

    // MARK: - Helpers

    private func roleBadge(for role: CKShare.ParticipantRole) -> String {
        switch role {
        case .readWrite: return "(редактор)"
        case .readOnly: return "(зритель)"
        default: return ""
        }
    }

    private func acceptanceLabel(for status: CKShare.ParticipantAcceptanceStatus) -> String {
        switch status {
        case .accepted: return "Принял приглашение"
        case .pending: return "Ожидает подтверждения"
        case .removed: return "Удалён"
        default: return "Неизвестно"
        }
    }

    private func participantIcon(for status: CKShare.ParticipantAcceptanceStatus) -> String {
        switch status {
        case .accepted: return "person.fill.checkmark"
        case .pending: return "person.fill.questionmark"
        case .removed: return "person.fill.xmark"
        default: return "person.fill"
        }
    }

    private func participantColor(for status: CKShare.ParticipantAcceptanceStatus) -> Color {
        switch status {
        case .accepted: return .green
        case .pending: return .orange
        case .removed: return .red
        default: return .gray
        }
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
