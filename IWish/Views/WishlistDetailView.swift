import SwiftUI
import SwiftData

struct WishlistDetailView: View {
    @Environment(\.modelContext) private var context
    let wishlist: Wishlist
    @State private var showingAddItem = false

    private var sortedItems: [Item] {
        wishlist.items
            .filter { !$0.isArchived }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        Group {
            if sortedItems.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .navigationTitle(wishlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddItem) {
            AddItemSheet(wishlist: wishlist)
        }
        .overlay(alignment: .bottom) {
            addButton
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Список пуст")
                .font(.title3)
            Text("Добавь первое желание.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var itemList: some View {
        List {
            ForEach(sortedItems) { item in
                HStack(spacing: 12) {
                    DefaultCoverView(
                        id: item.id,
                        imageData: item.coverImageData,
                        emoji: item.coverEmoji
                    )
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(item.tier.icon)
                            Text(item.name)
                                .font(.subheadline)
                        }
                        if let description = item.descriptionText, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if let price = item.price {
                        Text(formatPrice(price, currency: item.currency))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteItems)
        }
    }

    private var addButton: some View {
        Button {
            showingAddItem = true
        } label: {
            Label("Новое желание", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.bottom, 16)
    }

    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            context.delete(sortedItems[index])
        }
        try? context.save()
    }

    private func formatPrice(_ price: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: price as NSDecimalNumber) ?? "\(price) \(currency)"
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Wishlist.self, Item.self, AppSettings.self, configurations: config)

    let wishlist = Wishlist(name: "День рождения")
    let item1 = Item(name: "Наушники", tier: .must, price: 5000)
    let item2 = Item(name: "Книга", tier: .maybe, price: 1500, descriptionText: "Какая-нибудь интересная")
    item1.wishlist = wishlist
    item2.wishlist = wishlist
    wishlist.items = [item1, item2]

    container.mainContext.insert(wishlist)
    try? container.mainContext.save()

    return NavigationStack {
        WishlistDetailView(wishlist: wishlist)
    }
    .modelContainer(container)
}
