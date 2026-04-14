import SwiftUI
import SwiftData

// MARK: - Sort Option

private enum SortOption: String, CaseIterable, Identifiable {
    case importance
    case date
    case price
    case name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .importance: return "По важности"
        case .date:       return "По дате"
        case .price:      return "По цене"
        case .name:       return "По названию"
        }
    }

    var symbolName: String {
        switch self {
        case .importance: return "flame.fill"
        case .date:       return "calendar"
        case .price:      return "banknote"
        case .name:       return "textformat.abc"
        }
    }
}

// MARK: - View

struct WishlistDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let wishlist: Wishlist
    @State private var showingAddItem = false
    @State private var selectedSort: SortOption = .importance
    @State private var showingArchive = false
    @State private var showingShare = false
    @State private var showingParticipants = false
    @State private var showingDeleteConfirmation = false
    @State private var editingItem: Item?

    private var activeItems: [Item] {
        wishlist.items.filter { !$0.isArchived }
    }

    var body: some View {
        Group {
            if activeItems.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .navigationTitle(wishlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(SortOption.allCases) { option in
                        Button {
                            selectedSort = option
                        } label: {
                            if selectedSort == option {
                                Label {
                                    Text(option.label)
                                } icon: {
                                    Image(systemName: "checkmark")
                                }
                            } else {
                                Label(option.label, systemImage: option.symbolName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    let archivedCount = wishlist.items.filter { $0.isArchived }.count
                    if archivedCount > 0 {
                        Button {
                            showingArchive = true
                        } label: {
                            Label("Архив (\(archivedCount))", systemImage: "archivebox")
                        }
                    }

                    Button {
                        showingShare = true
                    } label: {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingParticipants = true
                    } label: {
                        Label("Участники", systemImage: "person.2")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Удалить список", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemSheet(wishlist: wishlist)
                .applyTheme()
        }
        .sheet(isPresented: $showingArchive) {
            ArchiveView(wishlist: wishlist)
                .applyTheme()
        }
        .sheet(isPresented: $showingShare) {
            ShareWishlistSheet(wishlist: wishlist)
                .applyTheme()
        }
        .sheet(isPresented: $showingParticipants) {
            ParticipantsView(wishlist: wishlist)
                .applyTheme()
        }
        .sheet(item: $editingItem) { item in
            EditItemSheet(item: item)
                .applyTheme()
        }
        .confirmationDialog("Удалить «\(wishlist.name)»?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить список", role: .destructive) {
                context.delete(wishlist)
                try? context.save()
                dismiss()
            }
        }
        .overlay(alignment: .bottom) {
            addButton
        }
    }

    // MARK: - Empty State

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
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Item List

    private var itemList: some View {
        List {
            if selectedSort == .importance {
                groupedByTier
            } else {
                flatSorted
            }
        }
        .contentMargins(.bottom, 80)
        .warmBackground()
    }

    // MARK: - Grouped by Tier

    @ViewBuilder
    private var groupedByTier: some View {
        ForEach(ItemTier.allCases) { tier in
            let tierItems = activeItems
                .filter { $0.tier == tier }
                .sorted { $0.sortIndex < $1.sortIndex }

            if !tierItems.isEmpty {
                Section {
                    ForEach(tierItems) { item in
                        itemRow(item)
                            .itemContextMenu(item: item, context: context, editingItem: $editingItem)
                            .itemSwipeActions(item: item, context: context)
                    }
                } header: {
                    tierHeader(tier: tier, items: tierItems)
                }
            }
        }
    }

    private func tierHeader(tier: ItemTier, items: [Item]) -> some View {
        let total = items.compactMap(\.price).reduce(Decimal.zero, +)
        let currency = items.first?.currency ?? "RUB"
        let priceText = total > 0 ? " \u{00B7} \(formatPrice(total, currency: currency))" : ""

        return HStack(spacing: 4) {
            Image(systemName: tier.symbolName)
            Text("\(tier.label)\(priceText) \u{00B7} \(items.count)")
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    // MARK: - Flat Sorted

    @ViewBuilder
    private var flatSorted: some View {
        let sorted = sortedItems(by: selectedSort)

        Section {
            ForEach(sorted) { item in
                itemRow(item)
                    .itemContextMenu(item: item, context: context, editingItem: $editingItem)
                    .itemSwipeActions(item: item, context: context)
            }
        }
    }

    private func sortedItems(by option: SortOption) -> [Item] {
        switch option {
        case .importance:
            return activeItems.sorted { $0.sortIndex < $1.sortIndex }
        case .date:
            return activeItems.sorted { $0.createdAt > $1.createdAt }
        case .price:
            return activeItems.sorted { lhs, rhs in
                switch (lhs.price, rhs.price) {
                case let (.some(l), .some(r)): return l > r
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.sortIndex < rhs.sortIndex
                }
            }
        case .name:
            return activeItems.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    // MARK: - Item Row

    private func itemRow(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            DefaultCoverView(
                id: item.id,
                imageData: item.coverImageData,
                emoji: item.coverEmoji
            )
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name)
                        .font(.body)
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    if let price = item.price {
                        Text(formatPrice(price, currency: item.currency))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }
                }

                itemMetadataRow(item)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func itemMetadataRow(_ item: Item) -> some View {
        HStack(spacing: 4) {
            Image(systemName: item.tier.symbolName)
            Text(item.createdAt.formatted(.dateTime.day().month(.abbreviated)))
            if let domain = extractDomain(from: item.url) {
                Text("\u{00B7}")
                Image(systemName: "link")
                Text(domain)
            }
            if let days = probationDaysLeft(item) {
                Text("\u{00B7}")
                Image(systemName: "clock")
                Text("\(days) дн.")
            }
        }
    }

    // MARK: - FAB

    private var addButton: some View {
        Button {
            showingAddItem = true
        } label: {
            Label("Новое желание", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.titaniumGradient, lineWidth: 0.5))
        }
        .padding(.bottom, 16)
    }

    // MARK: - Helpers

    private func formatPrice(_ price: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: price as NSDecimalNumber) ?? "\(price) \(currency)"
    }

    private func extractDomain(from urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty,
              let url = URL(string: urlString),
              let host = url.host()
        else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func probationDaysLeft(_ item: Item) -> Int? {
        guard let end = item.probationEndAt, end > .now else { return nil }
        let days = Calendar.current.dateComponents([.day], from: .now, to: end).day ?? 0
        return days > 0 ? days : nil
    }
}

// MARK: - Context Menu & Swipe Actions

private extension View {
    func itemContextMenu(item: Item, context: ModelContext, editingItem: Binding<Item?>) -> some View {
        self.contextMenu {
            Button {
                editingItem.wrappedValue = item
            } label: {
                Label("Изменить", systemImage: "pencil")
            }

            if let urlString = item.url, let url = URL(string: urlString) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("Открыть ссылку", systemImage: "safari")
                }
            }

            Menu {
                ForEach(ItemTier.allCases) { tier in
                    Button {
                        item.tier = tier
                        item.updatedAt = .now
                        try? context.save()
                    } label: {
                        if item.tier == tier {
                            Label {
                                Text(tier.label)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                        } else {
                            Label(tier.label, systemImage: tier.symbolName)
                        }
                    }
                }
            } label: {
                Label("Изменить важность", systemImage: "arrow.up.arrow.down")
            }

            Button {
                item.isArchived = true
                item.updatedAt = .now
                try? context.save()
            } label: {
                Label("В архив", systemImage: "archivebox")
            }

            Button(role: .destructive) {
                context.delete(item)
                try? context.save()
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    func itemSwipeActions(item: Item, context: ModelContext) -> some View {
        self.swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                context.delete(item)
                try? context.save()
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            .tint(.red)

            Button {
                item.isArchived = true
                item.updatedAt = .now
                try? context.save()
            } label: {
                Label("В архив", systemImage: "archivebox")
            }
            .tint(.blue)
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

    let items: [(String, ItemTier, Decimal?, String?)] = [
        ("Наушники Sony WH-1000XM5", .must, 29990, "https://www.wildberries.ru/product/123"),
        ("MacBook Air M4", .must, 89990, nil),
        ("Книга Дюна", .maybe, 1500, "https://ozon.ru/product/456"),
        ("Стикеры", .idea, nil, nil),
        ("Кроссовки Nike", .maybe, 15990, "https://nike.com/shoes/789"),
    ]
    for (name, tier, price, url) in items {
        let item = Item(name: name, tier: tier, price: price, url: url)
        item.wishlist = wishlist
        container.mainContext.insert(item)
    }

    try? container.mainContext.save()

    return NavigationStack {
        WishlistDetailView(wishlist: wishlist)
    }
    .modelContainer(container)
}
