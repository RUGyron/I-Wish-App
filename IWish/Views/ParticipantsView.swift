import SwiftUI
import SwiftData

struct ParticipantsView: View {
    @Environment(\.dismiss) private var dismiss
    let wishlist: Wishlist

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
                                Text("Вы")
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

                // Placeholder for future participants
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)

                        Text("Участники появятся после настройки iCloud")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } header: {
                    Text("Участники")
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
        }
        .applyTheme()
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

    return ParticipantsView(wishlist: wishlist)
        .modelContainer(container)
}
