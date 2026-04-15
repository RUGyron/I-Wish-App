import SwiftUI
import SwiftData

struct WishlistArchiveView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allWishlists: [Wishlist]

    private var archivedWishlists: [Wishlist] {
        allWishlists.filter { $0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if archivedWishlists.isEmpty {
                    ContentUnavailableView("Архив пуст", systemImage: "archivebox")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background)
                        .onAppear { dismiss() }
                } else {
                    List {
                        ForEach(archivedWishlists) { wishlist in
                            HStack(spacing: 12) {
                                DefaultCoverView(
                                    id: wishlist.id,
                                    imageData: wishlist.coverImageData,
                                    emoji: wishlist.coverEmoji
                                )
                                .frame(width: 48, height: 48)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(wishlist.name).font(.body)
                                    Text(wishlist.updatedAt, format: .dateTime.day().month(.abbreviated))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    context.delete(wishlist)
                                    try? context.save()
                                } label: { Label("Удалить", systemImage: "trash") }

                                Button {
                                    wishlist.isArchived = false
                                    wishlist.updatedAt = .now
                                    try? context.save()
                                } label: { Label("Восстановить", systemImage: "arrow.uturn.backward") }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .warmBackground()
            .navigationTitle("Архив списков")
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

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Wishlist.self, Item.self, AppSettings.self,
        configurations: config
    )

    let wl1 = Wishlist(name: "Старый список", coverEmoji: "\u{1F4E6}", isArchived: true)
    wl1.updatedAt = .now
    container.mainContext.insert(wl1)

    let wl2 = Wishlist(name: "Ещё один архивный", isArchived: true)
    wl2.updatedAt = Calendar.current.date(byAdding: .day, value: -5, to: .now)!
    container.mainContext.insert(wl2)

    try? container.mainContext.save()

    return WishlistArchiveView()
        .modelContainer(container)
}
