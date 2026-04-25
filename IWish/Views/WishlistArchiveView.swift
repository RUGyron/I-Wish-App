import SwiftUI
import SwiftData

struct WishlistArchiveView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @Environment(\.toast) private var toast
    @Query private var allWishlists: [Wishlist]
    @State private var isPerformingAction = false
    @State private var wishlistToDelete: Wishlist?

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
                                    emoji: wishlist.coverEmoji,
                                    gradientSeed: wishlist.gradientSeed
                                )
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                                    wishlistToDelete = wishlist
                                } label: { Label("Удалить", systemImage: "trash") }

                                Button {
                                    isPerformingAction = true
                                    Task {
                                        do {
                                            try await services.data?.unarchiveWishlist(id: wishlist.id.uuidString)
                                        } catch {
                                            toast.error(error.localizedDescription)
                                        }
                                        isPerformingAction = false
                                    }
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
            .loadingOverlay(isPerformingAction)
            .confirmationDialog(
                "Удалить «\(wishlistToDelete?.name ?? "")»?",
                isPresented: Binding(get: { wishlistToDelete != nil }, set: { if !$0 { wishlistToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Удалить", role: .destructive) {
                    guard let wl = wishlistToDelete else { return }
                    isPerformingAction = true
                    Task {
                        do {
                            try await services.data?.deleteWishlist(id: wl.id.uuidString)
                        } catch {
                            toast.error(error.localizedDescription)
                        }
                        isPerformingAction = false
                    }
                    wishlistToDelete = nil
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
