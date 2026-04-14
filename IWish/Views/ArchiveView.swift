import SwiftUI
import SwiftData

struct ArchiveView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let wishlist: Wishlist

    private var archivedItems: [Item] {
        (wishlist.items ?? []).filter { $0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if archivedItems.isEmpty {
                    ContentUnavailableView("Архив пуст", systemImage: "archivebox")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background)
                        .onAppear { dismiss() }
                } else {
                    List {
                        ForEach(archivedItems) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name).font(.subheadline)
                                    Text(item.updatedAt, format: .dateTime.day().month(.abbreviated))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    context.delete(item)
                                    try? context.save()
                                } label: { Label("Удалить", systemImage: "trash") }

                                Button {
                                    item.isArchived = false
                                    item.updatedAt = .now
                                    try? context.save()
                                } label: { Label("Восстановить", systemImage: "arrow.uturn.backward") }
                                    .tint(.blue)
                            }
                        }
                    }
                }
            }
            .warmBackground()
            .navigationTitle("Архив")
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

    let wishlist = Wishlist(name: "Тестовый список")
    container.mainContext.insert(wishlist)

    let item1 = Item(name: "Архивный предмет 1", tier: .must, price: 5000)
    item1.wishlist = wishlist
    item1.isArchived = true
    item1.updatedAt = .now
    container.mainContext.insert(item1)

    let item2 = Item(name: "Архивный предмет 2", tier: .maybe, price: 1200)
    item2.wishlist = wishlist
    item2.isArchived = true
    item2.updatedAt = Calendar.current.date(byAdding: .day, value: -3, to: .now)!
    container.mainContext.insert(item2)

    try? container.mainContext.save()

    return ArchiveView(wishlist: wishlist)
        .modelContainer(container)
}
