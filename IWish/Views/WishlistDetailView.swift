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
    @Environment(\.toast) private var toast
    let wishlist: Wishlist
    @State private var showingAddItem = false
    @State private var selectedSort: SortOption = .importance
    @State private var showingArchive = false
    @State private var showingShare = false
    @State private var showingParticipants = false
    @State private var showingDeleteConfirmation = false
    @State private var editingItem: Item?
    @State private var detailItem: Item?
    @State private var showingEditWishlist = false
    @State private var editMode: EditMode = .inactive
    @State private var sortSnapshot: [UUID: Double] = [:]
    @State private var pollTimer: Timer?
    @State private var showingLeaveConfirmation = false
    @State private var isCurrentUserOwner = true
    @State private var isPerformingAction = false
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

    private var totalActivePriceText: String? {
        let currency = activeItems.first(where: { $0.priceValue != nil })?.currency ?? "RUB"
        return totalPriceText(for: activeItems, currency: currency)
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
                HStack(spacing: 6) {
                    detailSyncSubtitle
                    Text("Желания").font(.headline)
                }
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
                        if wishlist.isEditable {
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
                        }

                        let archivedCount = (wishlist.items ?? []).filter { $0.isArchived }.count
                        if archivedCount > 0 && wishlist.isEditable {
                            Button {
                                showingArchive = true
                            } label: {
                                Label("Архив (\(archivedCount))", systemImage: "archivebox")
                            }
                        }

                        if !wishlist.isShared || wishlist.myRole == "owner" || wishlist.canInvite {
                            Button {
                                showingShare = true
                            } label: {
                                Label("Поделиться", systemImage: "square.and.arrow.up")
                            }
                        }

                        // Participants: visible for all shared wishlists
                        if wishlist.isShared {
                            Button {
                                showingParticipants = true
                            } label: {
                                Label("Участники", systemImage: "person.2")
                            }
                        }

                        Divider()

                        if wishlist.isShared && !isCurrentUserOwner {
                            Button(role: .destructive) {
                                showingLeaveConfirmation = true
                            } label: {
                                Label("Покинуть список", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } else {
                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Удалить список", systemImage: "trash")
                            }
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
        .sheet(item: $detailItem) { item in
            ItemDetailSheet(item: item, wishlist: wishlist)
        }
        .sheet(isPresented: $showingEditWishlist) {
            EditWishlistSheet(wishlist: wishlist)
                .applyTheme()
        }
        .loadingOverlay(isPerformingAction)
        .confirmationDialog("Удалить «\(wishlist.name)»?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить список", role: .destructive) {
                isPerformingAction = true
                Task {
                    do {
                        try await services.data?.deleteWishlist(id: wishlist.id.uuidString)
                        dismiss()
                    } catch {
                        toast.error(error.localizedDescription)
                    }
                    isPerformingAction = false
                }
            }
        }
        .confirmationDialog("Покинуть «\(wishlist.name)»?", isPresented: $showingLeaveConfirmation, titleVisibility: .visible) {
            Button("Покинуть список", role: .destructive) {
                isPerformingAction = true
                Task {
                    do {
                        try await services.data?.deleteWishlist(id: wishlist.id.uuidString)
                        dismiss()
                    } catch {
                        toast.error(error.localizedDescription)
                    }
                    isPerformingAction = false
                }
            }
        }
        .onAppear {
            if pollTimer == nil {
                startPolling()
                Task {
                    await services.data?.refreshItems(for: wishlist.id.uuidString)
                    if wishlist.isShared, let sharedID = wishlist.sharedWishlistID {
                        // Owner-флаг можем взять из локально сохранённого ownerRecordID —
                        // не нужен сетевой fetchSharedWishlist (и его ключ-зависимость).
                        if let owner = wishlist.ownerRecordID {
                            isCurrentUserOwner = owner == services.auth.uid
                        } else if let key = KeychainService.load(for: sharedID),
                                  let info = try? await services.firestore.fetchSharedWishlist(wishlistID: sharedID, key: key) {
                            isCurrentUserOwner = info.ownerUID == services.auth.uid
                        }
                    }
                }
            }
        }
        .onDisappear {
            stopPolling()
            if editMode.isEditing {
                cancelReorder()
            }
        }
        .overlay(alignment: .bottom) {
            if wishlist.isEditable {
                addButton
                    .padding(.bottom, 24)
            }
        }
        .onChange(of: wishlist.isDeleted) { _, deleted in
            if deleted { dismiss() }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            wishlistHeaderRow
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("Список пуст")
                    .font(.title3)
                if wishlist.isEditable {
                    Text("Добавь первое желание.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("В этот список ещё ничего не добавили.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.bottom, 80)
        .warmBackground()
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
                emoji: wishlist.coverEmoji,
                gradientSeed: wishlist.gradientSeed,
                gradientHue: wishlist.gradientHue
            )
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(wishlist.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    if wishlist.isShared {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(.secondary)
                            if let role = wishlist.myRole {
                                Image(systemName: roleIcon(role))
                                    .foregroundStyle(roleColor(role))
                            }
                        }
                        .font(.caption)
                    }
                }

                HStack(spacing: 4) {
                    Text(String(format: NSLocalizedString("%lld желаний", comment: ""), activeItems.count))
                        .foregroundStyle(.secondary)
                    if let totalText = totalActivePriceText {
                        Text("\u{00B7} \(totalText)")
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
                            if wishlist.isEditable {
                                itemRow(item)
                                    .itemContextMenu(item: item, context: context, editingItem: $editingItem, dataService: services.data, wishlistID: wishlist.id.uuidString, toast: toast)
                                    .itemSwipeActions(item: item, dataService: services.data, wishlistID: wishlist.id.uuidString, toast: toast)
                            } else {
                                itemRow(item)
                            }
                        }
                        .onMove { from, to in
                            guard wishlist.isEditable else { return }
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
        let currency = items.first?.currency ?? "RUB"
        let totalText = totalPriceText(for: items, currency: currency)
        let priceSuffix = totalText.map { " \u{00B7} \($0)" } ?? ""

        return HStack(spacing: 4) {
            Text(tier.emoji)
            Text("\(tier.label)\(priceSuffix) \u{00B7} \(items.count)")
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    /// Сумма items с учётом range. Если есть хотя бы один item-диапазон — "Σmin — Σmax".
    /// Если все exact — простая сумма. Возвращает nil если ни у одного item нет цены.
    private func totalPriceText(for items: [Item], currency: String) -> String? {
        let priced = items.filter {
            if case .none = $0.priceMode { return false }
            return true
        }
        guard !priced.isEmpty else { return nil }

        let hasRange = priced.contains {
            if case .range = $0.priceMode { return true }
            return false
        }

        if hasRange {
            let totalMin = priced.reduce(0.0) { acc, item in
                switch item.priceMode {
                case .none: return acc
                case .exact(let p): return acc + p
                case .range(let min, _): return acc + min
                }
            }
            let totalMax = priced.reduce(0.0) { acc, item in
                switch item.priceMode {
                case .none: return acc
                case .exact(let p): return acc + p
                case .range(_, let max): return acc + max
                }
            }
            return "\(formatPrice(totalMin, currency: currency)) — \(formatPrice(totalMax, currency: currency))"
        } else {
            let total = priced.reduce(0.0) { acc, item in
                switch item.priceMode {
                case .exact(let p): return acc + p
                default: return acc
                }
            }
            return total > 0 ? formatPrice(total, currency: currency) : nil
        }
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
        // Sync reordered items to Firestore
        for item in tierItems {
            Task {
                do {
                    try await services.data?.updateItem(
                        id: item.id.uuidString,
                        wishlistID: wishlist.id.uuidString,
                        name: item.name,
                        tier: item.tier,
                        price: item.priceValue,
                        priceMax: item.priceMaxValue,
                        currency: item.currency,
                        url: item.url,
                        emoji: item.coverEmoji,
                        sortIndex: item.sortIndex,
                        isArchived: item.isArchived,
                        descriptionText: item.descriptionText,
                        coverImageData: item.coverImageData,
                        linkMetadataData: item.linkMetadataData,
                        probationEndAt: item.probationEndAt
                    )
                } catch {
                    toast.error(error.localizedDescription)
                }
            }
        }
    }

    private var detailSyncSubtitle: some View {
        Group {
            if let data = services.data {
                SyncStatusBadge(
                    isSyncing: data.isSyncing,
                    syncError: data.syncError,
                    onTap: { Task { await services.data?.refreshItems(for: wishlist.id.uuidString) } }
                )
            }
        }
    }

    // MARK: - Flat Sorted

    @ViewBuilder
    private var flatSorted: some View {
        let sorted = sortedItems(by: selectedSort)

        Section {
            ForEach(sorted) { item in
                if wishlist.isEditable {
                    itemRow(item)
                        .itemContextMenu(item: item, context: context, editingItem: $editingItem, dataService: services.data, wishlistID: wishlist.id.uuidString, toast: toast)
                        .itemSwipeActions(item: item, dataService: services.data, wishlistID: wishlist.id.uuidString, toast: toast)
                } else {
                    itemRow(item)
                }
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
                switch (avgPrice(lhs), avgPrice(rhs)) {
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

    /// Для сортировки по цене — точная даёт само значение, диапазон — среднее min/max.
    private func avgPrice(_ item: Item) -> Double? {
        switch item.priceMode {
        case .none: return nil
        case .exact(let p): return p
        case .range(let min, let max): return (min + max) / 2
        }
    }

    // MARK: - Item Row

    private func itemRow(_ item: Item) -> some View {
        // Telegram-style: автор+дата сверху, имя жирно, мета-строка снизу.
        // Слева — цветная полоска по tier (вместо эмодзи в тексте).
        // Title зафиксирован lineLimit(1) → длинный текст не растягивает row.
        // Bottom row показываем только когда есть url / probation, иначе
        // карточка не оставляет пустого места под именем.
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(item.tier.stripeColor)
                .frame(width: 4)

            HStack(alignment: .top, spacing: 12) {
                DefaultCoverView(
                    id: item.id,
                    imageData: item.coverImageData,
                    emoji: item.coverEmoji
                )
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    topRow(for: item)
                    titleRow(for: item)
                    if hasBottomMeta(item) {
                        bottomRow(for: item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 10)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture { detailItem = item }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color(.secondarySystemGroupedBackground))
        .alignmentGuide(.listRowSeparatorLeading) { _ in 78 }
    }

    private func hasBottomMeta(_ item: Item) -> Bool {
        let hasURL = (item.url ?? "").isEmpty == false
        return hasURL || probationDaysLeft(item) != nil
    }

    private func topRow(for item: Item) -> some View {
        HStack(spacing: 6) {
            if wishlist.isShared, let author = authorLabel(for: item) {
                Text(author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(item.createdAt.formatted(.dateTime.day().month(.abbreviated)))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 4)

            if let priceText = priceCardText(for: item) {
                Text(priceText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .layoutPriority(1)
                    .lineLimit(1)
            }
        }
        .frame(height: 16)
    }

    /// На карточке желания: точная цена или "до Y" для диапазона (только верхняя граница —
    /// места мало). В детальном экране (ItemDetailSheet) показываем полный "X — Y".
    private func priceCardText(for item: Item) -> String? {
        switch item.priceMode {
        case .none: return nil
        case .exact(let p): return formatPrice(p, currency: item.currency)
        case .range(_, let max): return "до \(formatPrice(max, currency: item.currency))"
        }
    }

    private func titleRow(for item: Item) -> some View {
        Text(item.name)
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: 22, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func bottomRow(for item: Item) -> some View {
        HStack(spacing: 8) {
            if let urlString = item.url, !urlString.isEmpty, let url = URL(string: urlString) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                        Text(extractDomain(from: urlString) ?? "ссылка")
                    }
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
            if let days = probationDaysLeft(item) {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                    Text("\(days) дн.")
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .frame(height: 16)
    }

    /// Имя автора item в shared wishlist (без префикса "от " — он отрисовывается отдельно).
    /// Возвращает "Вы" если item добавлен текущим юзером.
    /// Если addedByName отсутствует (legacy item, добавленный до внедрения авторства) — возвращаем nil.
    private func authorLabel(for item: Item) -> String? {
        if let myUID = services.auth.uid, item.addedByUID == myUID {
            return "Вы"
        }
        guard let name = item.addedByName, !name.isEmpty else { return nil }
        return name
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

    // MARK: - Polling

    private func startPolling() {
        // 15 сек — экономим Firestore quota; throttle в DataService отсечёт более частые.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
            Task { @MainActor in
                // Check if wishlist still exists (might be deleted by another device)
                if wishlist.isDeleted || wishlist.modelContext == nil {
                    stopPolling()
                    dismiss()
                    return
                }
                await services.data?.refreshItems(for: wishlist.id.uuidString)
                // Check if refreshItems detected remote deletion
                if services.data?.wishlistDeleted == true {
                    services.data?.wishlistDeleted = false
                    stopPolling()
                    dismiss()
                    return
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
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
        }
        .glassEffect(.regular.interactive())
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func roleIcon(_ role: String) -> String {
        switch role {
        case "owner": return "crown.fill"
        case "editor": return "pencil"
        case "viewer": return "eye"
        default: return "person.2.fill"
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "owner": return .orange
        case "editor": return .blue
        case "viewer": return .secondary
        default: return .secondary
        }
    }

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
    func itemContextMenu(item: Item, context: ModelContext, editingItem: Binding<Item?>, dataService: DataService?, wishlistID: String, toast: ToastManager) -> some View {
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
                        Task {
                            do {
                                try await dataService?.updateItem(
                                    id: item.id.uuidString,
                                    wishlistID: wishlistID,
                                    name: item.name,
                                    tier: tier,
                                    price: item.priceValue,
                                    priceMax: item.priceMaxValue,
                                    currency: item.currency,
                                    url: item.url,
                                    emoji: item.coverEmoji,
                                    sortIndex: item.sortIndex,
                                    isArchived: item.isArchived,
                                    descriptionText: item.descriptionText,
                                    coverImageData: item.coverImageData,
                                    linkMetadataData: item.linkMetadataData,
                                    probationEndAt: item.probationEndAt
                                )
                            } catch {
                                toast.error(error.localizedDescription)
                            }
                        }
                    } label: {
                        // Эмодзи всегда виден; checkmark рядом с выбранной опцией.
                        HStack {
                            Text("\(tier.emoji) \(tier.label)")
                            if item.tier == tier {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Изменить важность", systemImage: "arrow.up.arrow.down")
            }

            Button {
                Task {
                    do {
                        try await dataService?.archiveItem(id: item.id.uuidString, wishlistID: wishlistID)
                    } catch {
                        toast.error(error.localizedDescription)
                    }
                }
            } label: {
                Label("В архив", systemImage: "archivebox")
            }

            Button(role: .destructive) {
                Task {
                    do {
                        try await dataService?.deleteItem(id: item.id.uuidString, wishlistID: wishlistID)
                    } catch {
                        toast.error(error.localizedDescription)
                    }
                }
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    func itemSwipeActions(item: Item, dataService: DataService?, wishlistID: String, toast: ToastManager) -> some View {
        self.swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task {
                    do {
                        try await dataService?.deleteItem(id: item.id.uuidString, wishlistID: wishlistID)
                    } catch {
                        toast.error(error.localizedDescription)
                    }
                }
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            .tint(.red)

            Button {
                Task {
                    do {
                        try await dataService?.archiveItem(id: item.id.uuidString, wishlistID: wishlistID)
                    } catch {
                        toast.error(error.localizedDescription)
                    }
                }
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
