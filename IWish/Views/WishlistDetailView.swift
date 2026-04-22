import SwiftUI
import SwiftData
import FirebaseFirestore

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
        case .price:      return "dollarsign.circle"
        case .name:       return "textformat.abc"
        }
    }
}

// MARK: - View

struct WishlistDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    let wishlist: Wishlist
    @State private var showingAddItem = false
    @State private var selectedSort: SortOption = .importance
    @State private var showingArchive = false
    @State private var showingShare = false
    @State private var showingParticipants = false
    @State private var showingDeleteConfirmation = false
    @State private var editingItem: Item?
    @State private var showingEditWishlist = false
    @State private var editMode: EditMode = .inactive
    @State private var sortSnapshot: [UUID: Double] = [:]
    @State private var itemsListener: ListenerRegistration?
    @AppStorage("collapsedTiers") private var collapsedTiersRaw: String = ""

    private var collapsedTiers: Set<String> {
        Set(collapsedTiersRaw.split(separator: ",").map(String.init))
    }

    private func toggleCollapse(_ tier: ItemTier) {
        var set = collapsedTiers
        if set.contains(tier.rawValue) {
            set.remove(tier.rawValue)
        } else {
            set.insert(tier.rawValue)
        }
        collapsedTiersRaw = set.joined(separator: ",")
    }

    private var syncShouldForceShow: Bool {
        switch services.syncStatus.state {
        case .syncing, .error, .offline: return true
        default: return false
        }
    }

    private var totalActivePrice: Double {
        activeItems.compactMap(\.price).reduce(0, +)
    }

    // MARK: - Debug

    #if DEBUG
    @State private var debugItemMode = 0 // 0=real, 1=empty, 2=full
    @State private var debugMockItems: [Item] = {
        let data: [(String, ItemTier, Double?, String?)] = [
            ("Наушники Sony WH-1000XM5", .must, 29990, "https://wildberries.ru"),
            ("MacBook Air M4", .must, 89990, nil),
            ("Кроссовки Nike Air Max 2024", .must, 15990, "https://nike.com"),
            ("Книга «Дюна» Фрэнк Герберт", .maybe, 1500, "https://ozon.ru"),
            ("Настольная игра «Каркассон»", .maybe, 3500, nil),
            ("Стикеры с котиками", .idea, nil, nil),
            ("Подписка Apple Arcade", .idea, 219, nil),
        ]
        return data.enumerated().map { idx, tuple in
            let item = Item(name: tuple.0, tier: tuple.1, price: tuple.2, url: tuple.3)
            item.sortIndex = Double((idx + 1) * 1000)
            return item
        }
    }()
    #endif

    private var activeItems: [Item] {
        #if DEBUG
        switch debugItemMode {
        case 1: return []
        case 2: return debugMockItems
        default: break
        }
        #endif
        return (wishlist.items ?? []).filter { !$0.isArchived }
    }

    var body: some View {
        Group {
            if activeItems.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .navigationTitle("Желания")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Желания").font(.headline)
                    if syncShouldForceShow || services.syncStatus.hasEverSynced {
                        syncSubtitle
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: services.syncStatus.state)
            }

            ToolbarItem(placement: .topBarTrailing) {
                if editMode.isEditing {
                    Button {
                        cancelReorder()
                    } label: {
                        Image(systemName: "xmark")
                    }
                } else {
                    Menu {
                        ForEach(SortOption.allCases) { option in
                            Button {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    selectedSort = option
                                }
                            } label: {
                                if selectedSort == option {
                                    Label(option.label, systemImage: "checkmark")
                                } else {
                                    Label(option.label, systemImage: option.symbolName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if editMode.isEditing {
                    Button {
                        sortSnapshot = [:]
                        withAnimation { editMode = .inactive }
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                } else {
                    Menu {
                        Button {
                            showingEditWishlist = true
                        } label: {
                            Label("Изменить список", systemImage: "pencil")
                        }

                        if selectedSort == .importance {
                            Button {
                                saveSortSnapshot()
                                withAnimation { editMode = .active }
                            } label: {
                                Label("Переместить", systemImage: "arrow.up.arrow.down")
                            }
                        }

                        Divider()

                        let archivedCount = (wishlist.items ?? []).filter { $0.isArchived }.count
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
            ParticipantsView(wishlist: wishlist, onShareRequested: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingShare = true
                }
            })
            .applyTheme()
        }
        .sheet(item: $editingItem) { item in
            EditItemSheet(item: item)
                .applyTheme()
        }
        .sheet(isPresented: $showingEditWishlist) {
            EditWishlistSheet(wishlist: wishlist)
                .applyTheme()
        }
        .confirmationDialog("Удалить «\(wishlist.name)»?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить список", role: .destructive) {
                context.delete(wishlist)
                try? context.save()
                dismiss()
            }
        }
        .onDisappear {
            if editMode.isEditing {
                cancelReorder()
            }
            itemsListener?.remove()
            itemsListener = nil
        }
        .overlay(alignment: .bottom) {
            addButton
                .padding(.bottom, 24)
        }
        .task {
            guard let sharedID = wishlist.sharedWishlistID else { return }
            itemsListener = services.firestore.listenToItems(wishlistID: sharedID) { remoteItems in
                mergeRemoteItems(remoteItems)
            }
        }
        .overlay {
            if wishlist.isShared && !services.syncStatus.hasEverSynced {
                sharedSyncGate
            }
        }
    }

    // MARK: - Shared Sync Gate

    private var sharedSyncGate: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Загрузка данных...")
                    .font(.headline)
                Text("Синхронизируемся с iCloud, чтобы показать актуальный список.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if case .error = services.syncStatus.state {
                    Button("Попробовать снова") {
                        services.syncStatus.retry(context: context)
                    }
                    .buttonStyle(.bordered)
                }
                if case .offline = services.syncStatus.state {
                    Label("Нет подключения к сети", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
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
            wishlistHeaderRow
            if selectedSort == .importance {
                groupedByTier
            } else {
                flatSorted
            }
        }
        .environment(\.editMode, $editMode)
        .contentMargins(.bottom, 80)
        .warmBackground()
        .animation(.easeInOut, value: activeItems.map(\.id))
        .animation(.easeInOut(duration: 0.25), value: collapsedTiersRaw)
    }

    // Хедер — часть списка, но визуально читается как продолжение навбара:
    // прозрачный фон, нет разделителей, крупный шрифт
    private var wishlistHeaderRow: some View {
        HStack(alignment: .center, spacing: 16) {
            DefaultCoverView(
                id: wishlist.id,
                imageData: wishlist.coverImageData,
                emoji: wishlist.coverEmoji
            )
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(wishlist.name)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(String(format: NSLocalizedString("%lld желаний", comment: ""), activeItems.count))
                        .foregroundStyle(.secondary)
                    if totalActivePrice > 0 {
                        Text("\u{00B7} \(formatPrice(totalActivePrice, currency: activeItems.first(where: { $0.price != nil })?.currency ?? "RUB"))")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)      // прозрачно — читается как часть фона
        .listRowSeparator(.hidden)           // нет разделителя — не как ячейка
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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
                    if !collapsedTiers.contains(tier.rawValue) {
                        ForEach(tierItems) { item in
                            itemRow(item)
                                .itemContextMenu(item: item, context: context, editingItem: $editingItem, onMutate: { pushIfShared() })
                                .itemSwipeActions(item: item, context: context, onMutate: { pushIfShared() })
                        }
                        .onMove { from, to in
                            reorderItems(in: tier, from: from, to: to)
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            toggleCollapse(tier)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            tierHeaderContent(tier: tier, items: tierItems)
                            Spacer()
                            Image(systemName: collapsedTiers.contains(tier.rawValue) ? "chevron.right" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func tierHeaderContent(tier: ItemTier, items: [Item]) -> some View {
        let total = items.compactMap(\.price).reduce(0.0, +)
        let currency = items.first?.currency ?? "RUB"
        let priceText = total > 0 ? " \u{00B7} \(formatPrice(total, currency: currency))" : ""

        return HStack(spacing: 4) {
            Text(tier.emoji)
            Text("\(tier.label)\(priceText) \u{00B7} \(items.count)")
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    private func reorderItems(in tier: ItemTier, from source: IndexSet, to destination: Int) {
        var tierItems = activeItems
            .filter { $0.tier == tier }
            .sorted { $0.sortIndex < $1.sortIndex }

        tierItems.move(fromOffsets: source, toOffset: destination)

        for (i, item) in tierItems.enumerated() {
            item.sortIndex = Double((i + 1) * 1000)
            item.updatedAt = .now
        }
        try? context.save()
        pushIfShared()
    }

    private func pushIfShared() {
        guard let sharedID = wishlist.sharedWishlistID else { return }
        let items = (wishlist.items ?? []).map { item in
            FirestoreService.SharedItemInfo(
                itemID: item.id.uuidString,
                name: item.name,
                tier: item.tier.rawValue,
                price: item.price,
                currency: item.currency,
                url: item.url,
                coverEmoji: item.coverEmoji,
                sortIndex: item.sortIndex,
                isArchived: item.isArchived
            )
        }
        Task { try? await services.firestore.updateItems(wishlistID: sharedID, items: items) }
    }

    /// Merges remote Firestore items into local SwiftData: add new, update changed, delete removed.
    private func mergeRemoteItems(_ remoteItems: [FirestoreService.SharedItemInfo]) {
        let localItems = wishlist.items ?? []
        let localByID = Dictionary(uniqueKeysWithValues: localItems.compactMap { item -> (String, Item)? in
            (item.id.uuidString, item)
        })
        let remoteIDs = Set(remoteItems.map(\.itemID))

        // Delete items that no longer exist remotely
        for local in localItems {
            if !remoteIDs.contains(local.id.uuidString) {
                context.delete(local)
            }
        }

        // Add new or update changed items
        for remote in remoteItems {
            let tier: ItemTier
            switch remote.tier {
            case "must": tier = .must
            case "maybe": tier = .maybe
            default: tier = .idea
            }

            if let local = localByID[remote.itemID] {
                // Update existing
                local.name = remote.name
                local.tier = tier
                local.price = remote.price
                local.currency = remote.currency
                local.url = remote.url
                local.coverEmoji = remote.coverEmoji
                local.sortIndex = remote.sortIndex
                local.isArchived = remote.isArchived
                local.updatedAt = .now
            } else {
                // Add new
                let item = Item(
                    name: remote.name,
                    tier: tier,
                    currency: remote.currency,
                    price: remote.price,
                    url: remote.url
                )
                item.coverEmoji = remote.coverEmoji
                item.sortIndex = remote.sortIndex
                item.isArchived = remote.isArchived
                item.wishlist = wishlist
                if let uuid = UUID(uuidString: remote.itemID) {
                    item.id = uuid
                }
                context.insert(item)
            }
        }

        try? context.save()
    }

    // MARK: - Flat Sorted

    @ViewBuilder
    private var flatSorted: some View {
        let sorted = sortedItems(by: selectedSort)

        Section {
            ForEach(sorted) { item in
                itemRow(item)
                    .itemContextMenu(item: item, context: context, editingItem: $editingItem, onMutate: { pushIfShared() })
                    .itemSwipeActions(item: item, context: context, onMutate: { pushIfShared() })
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
            Text(item.tier.emoji)
            Text(item.createdAt.formatted(.dateTime.day().month(.abbreviated)))
            if let domain = extractDomain(from: item.url) {
                Text("\u{00B7}")
                Image(systemName: "link")
                Text(domain)
            }
            if let days = probationDaysLeft(item) {
                Text("\u{00B7}")
                Image(systemName: "clock")
                Text(String(format: NSLocalizedString("%lld дней", comment: ""), days))
            }
        }
    }

    // MARK: - Sync Subtitle (navbar)

    @ViewBuilder
    private var syncSubtitle: some View {
        let state = services.syncStatus.state
        let isError: Bool = {
            switch state {
            case .error, .offline: return true
            default: return false
            }
        }()

        HStack(spacing: 3) {
            Image(systemName: syncIcon)
                .font(.system(size: 9))
            Text(syncLabel)
                .font(.system(size: 10))
        }
        .foregroundStyle(isError ? .orange : .secondary)
        .onTapGesture {
            if isError {
                services.syncStatus.retry(context: context)
            }
        }
    }

    private var syncIcon: String {
        switch services.syncStatus.state {
        case .idle: return "icloud"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.icloud"
        case .offline: return "icloud.slash"
        case .error: return "exclamationmark.icloud"
        }
    }

    private var syncLabel: String {
        switch services.syncStatus.state {
        case .idle: return "iCloud"
        case .syncing: return "Синхронизация..."
        case .synced: return "iCloud"
        case .offline: return "Нет сети"
        case .error: return "Ошибка"
        }
    }

    // MARK: - Reorder helpers

    private func saveSortSnapshot() {
        sortSnapshot = Dictionary(
            uniqueKeysWithValues: activeItems.map { ($0.id, $0.sortIndex) }
        )
    }

    private func cancelReorder() {
        if !sortSnapshot.isEmpty {
            for item in (wishlist.items ?? []) {
                if let saved = sortSnapshot[item.id] {
                    item.sortIndex = saved
                    item.updatedAt = .now
                }
            }
            try? context.save()
            sortSnapshot = [:]
        }
        withAnimation { editMode = .inactive }
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
    }

    // MARK: - Helpers

    private func formatPrice(_ price: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "\(price) \(currency)"
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
    func itemContextMenu(item: Item, context: ModelContext, editingItem: Binding<Item?>, onMutate: (() -> Void)? = nil) -> some View {
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
                        onMutate?()
                    } label: {
                        if item.tier == tier {
                            Label {
                                Text(tier.label)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                        } else {
                            Text("\(tier.emoji) \(tier.label)")
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
                onMutate?()
            } label: {
                Label("В архив", systemImage: "archivebox")
            }

            Button(role: .destructive) {
                context.delete(item)
                try? context.save()
                onMutate?()
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    func itemSwipeActions(item: Item, context: ModelContext, onMutate: (() -> Void)? = nil) -> some View {
        self.swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                context.delete(item)
                try? context.save()
                onMutate?()
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            .tint(.red)

            Button {
                item.isArchived = true
                item.updatedAt = .now
                try? context.save()
                onMutate?()
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

    let items: [(String, ItemTier, Double?, String?)] = [
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
