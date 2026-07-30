import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appServices) private var services
    @Environment(\.toast) private var toast
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Wishlist.createdAt, order: .reverse) private var wishlists: [Wishlist]
    @State private var showingAddSheet = false
    @State private var showingSettings = false
    @State private var showingJoin = false
    @State private var sharingWishlist: Wishlist?
    @State private var pollTimer: Timer?
    @State private var deletingWishlistID: String?
    @State private var wishlistToDelete: Wishlist?
    @State private var wishlistToArchive: Wishlist?
    @State private var wishlistToLeave: Wishlist?
    @State private var isPerformingAction = false
    @State private var showingArchive = false

    // MARK: - Debug

    #if DEBUG
    @State private var debugListMode = 0 // 0=real, 1=empty, 2=full
    @State private var debugInserted: [Wishlist] = []
    #endif

    private var activeWishlists: [Wishlist] {
        #if DEBUG
        if debugListMode == 1 { return [] }
        #endif
        return wishlists.filter { !$0.isArchived && !$0.isTombstoned }
    }

    /// Hash для анимации списка. Ловит insert/delete + изменения name/cover/items.count.
    /// updatedAt НАМЕРЕННО исключён — он дёргался каждым polling-тиком (refreshWishlists писал
    /// updatedAt безусловно) и вызывал лишнюю переанимацию грида. Реальные изменения ловятся по полям.
    private var wishlistsAnimationKey: Int {
        var hasher = Hasher()
        for wl in activeWishlists {
            hasher.combine(wl.id)
            hasher.combine(wl.name)
            hasher.combine(wl.coverEmoji)
            hasher.combine(wl.coverImageData?.count)
            hasher.combine((wl.items ?? []).filter { !$0.isArchived && !$0.isTombstoned }.count)
        }
        return hasher.finalize()
    }

    private var totalItems: Int {
        activeWishlists.reduce(0) { $0 + ($1.items ?? []).filter { !$0.isArchived && !$0.isTombstoned }.count }
    }

    private var archivedCount: Int {
        wishlists.filter { $0.isArchived && !$0.isTombstoned }.count
    }

    private var hasAnyWishlists: Bool {
        !activeWishlists.isEmpty
    }

    private var gridColumns: [GridItem] {
        let count: Int
        switch sizeClass {
        case .compact: count = 2
        case .regular:
            // iPad / iPad Multitasking. UIScreen.main deprecated в iOS 26 и врёт при split-view.
            // Используем GridItem с adaptive minimum — SwiftUI сам наполнит 3-4 столбца
            // в зависимости от доступной ширины контейнера.
            return [GridItem(.adaptive(minimum: 220), spacing: 12)]
        default: count = 2
        }
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        Group {
            if hasAnyWishlists {
                wishlistList
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .warmBackground()
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Wishlists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                homeNavTitle
            }
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 16) {
                    Button {
                        showingJoin = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    if archivedCount > 0 {
                        Button {
                            showingArchive = true
                        } label: {
                            Image(systemName: "archivebox")
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWishlistSheet()
                .applyTheme()
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView() }
                .fontDesign(.rounded)
                .applyTheme()
        }
        .sheet(isPresented: $showingJoin) {
            JoinWishlistSheet()
                .applyTheme()
        }
        .sheet(item: $sharingWishlist) { wishlist in
            ShareWishlistSheet(wishlist: wishlist)
                .applyTheme()
        }
        .sheet(isPresented: $showingArchive) {
            WishlistArchiveView()
                .applyTheme()
        }
        .onAppear {
            if pollTimer == nil {
                // First appear — refresh + start polling
                Task { await services.data?.refreshWishlists() }
                startPolling()
            }
        }
        .onDisappear {
            // Не выгружаемся пока view навигационно в стеке (NavigationLink → детальный
            // экран не вызывает onDisappear на HomeView), но при reset стека / переключении
            // вкладок остановим polling чтобы не жрать quota / батарею в фоне.
            stopPolling()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Pause polling когда app в background. Resume на foreground.
            switch newPhase {
            case .background, .inactive:
                stopPolling()
            case .active:
                if pollTimer == nil {
                    Task { await services.data?.refreshWishlists() }
                    startPolling()
                }
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveShareLink)) { _ in
            showingJoin = true
        }
        .loadingOverlay(isPerformingAction)
        .confirmationDialog(
            "Delete “\(wishlistToDelete?.name ?? "")”?",
            isPresented: Binding(get: { wishlistToDelete != nil }, set: { if !$0 { wishlistToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
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
        .confirmationDialog(
            "Archive “\(wishlistToArchive?.name ?? "")”?",
            isPresented: Binding(get: { wishlistToArchive != nil }, set: { if !$0 { wishlistToArchive = nil } }),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                guard let wl = wishlistToArchive else { return }
                isPerformingAction = true
                Task {
                    do {
                        try await services.data?.archiveWishlist(id: wl.id.uuidString)
                    } catch {
                        toast.error(error.localizedDescription)
                    }
                    isPerformingAction = false
                }
                wishlistToArchive = nil
            }
        } message: {
            Text("All participants will be removed, invitations revoked. The list becomes private.")
        }
        .confirmationDialog(
            "Leave “\(wishlistToLeave?.name ?? "")”?",
            isPresented: Binding(get: { wishlistToLeave != nil }, set: { if !$0 { wishlistToLeave = nil } }),
            titleVisibility: .visible
        ) {
            Button("Leave list", role: .destructive) {
                guard let wl = wishlistToLeave else { return }
                isPerformingAction = true
                Task {
                    do {
                        try await services.data?.deleteWishlist(id: wl.id.uuidString)
                    } catch {
                        toast.error(error.localizedDescription)
                    }
                    isPerformingAction = false
                }
                wishlistToLeave = nil
            }
        }
        .overlay(alignment: .bottom) {
            addButton
                .padding(.bottom, 24)
        }
    }

    // MARK: - Debug

    private var homeNavTitle: some View {
        HStack(spacing: 6) {
            if let data = services.data {
                SyncStatusBadge(
                    isSyncing: services.sync.isSyncing,
                    syncError: services.sync.lastError,
                    pendingCount: services.sync.pendingCount,
                    isOffline: services.networkMonitor.isBlocked,
                    syncStartedAt: services.sync.syncStartedAt,
                    onTap: {
                        Task {
                            await services.sync.retryAll()
                            await services.data?.refreshWishlists()
                        }
                    }
                )
            }
            Text("Wishlists").font(.headline)
        }
    }

    // MARK: - Debug Helpers

    #if DEBUG
    private func cycleDebugListMode() {
        switch debugListMode {
        case 0:
            debugListMode = 1
        case 1:
            insertDebugWishlists()
            debugListMode = 2
        default:
            cleanupDebugWishlists()
            debugListMode = 0
        }
    }

    private func insertDebugWishlists() {
        let data: [(String, String?, [(String, ItemTier, Double?)])] = [
            ("🎂 День рождения", "🎂", [
                ("Наушники Sony WH-1000XM5", .must, 29990),
                ("Книга «Мастер и Маргарита»", .maybe, 1200),
                ("Стикеры с котиками", .idea, nil),
            ]),
            ("Техника", nil, [
                ("MacBook Air M4", .must, 89990),
                ("iPad Pro 13\"", .must, 119990),
                ("AirPods Pro 2", .maybe, 24990),
                ("Apple Watch Ultra 2", .idea, 89990),
            ]),
            ("Путешествия ✈️", "✈️", [
                ("Чемодан Samsonite", .must, 25000),
                ("Адаптер для розеток", .idea, 800),
            ]),
            ("Книги", nil, [
                ("«Дюна» Герберт", .must, 1500),
                ("«Игра престолов»", .maybe, 2200),
                ("«Атлант расправил плечи»", .idea, 1800),
            ]),
        ]
        var inserted: [Wishlist] = []
        for (name, emoji, items) in data {
            let wl = Wishlist(name: name, coverEmoji: emoji)
            context.insert(wl)
            for (idx, (iName, tier, price)) in items.enumerated() {
                let item = Item(name: iName, tier: tier, price: price)
                item.wishlist = wl
                item.sortIndex = Double((idx + 1) * 1000)
                context.insert(item)
            }
            inserted.append(wl)
        }
        debugInserted = inserted
        try? context.save()
    }

    private func cleanupDebugWishlists() {
        for wl in debugInserted {
            context.delete(wl)
        }
        debugInserted = []
        try? context.save()
    }
    #endif

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Nothing here yet")
                .font(.title3)
            Text("Start collecting wishes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Wishlist List

    private var wishlistList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(String(format: NSLocalizedString("%lld списков", comment: ""), activeWishlists.count)) \u{00B7} \(String(format: NSLocalizedString("%lld желаний", comment: ""), totalItems))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(activeWishlists) { wishlist in
                        WishlistTileView(
                            wishlist: wishlist,
                            onShare: { wl in sharingWishlist = wl },
                            onArchive: { wl in
                                if wl.isShared && wl.memberCount > 1 {
                                    wishlistToArchive = wl
                                } else {
                                    isPerformingAction = true
                                    Task {
                                        do {
                                            try await services.data?.archiveWishlist(id: wl.id.uuidString)
                                        } catch {
                                            toast.error(error.localizedDescription)
                                        }
                                        isPerformingAction = false
                                    }
                                }
                            },
                            onDelete: { wl in wishlistToDelete = wl },
                            onLeave: { wl in wishlistToLeave = wl }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.85).combined(with: .opacity),
                            removal: .scale(scale: 0.85).combined(with: .opacity)
                        ))
                    }

                }
                .padding(.horizontal, 16)
                .animation(.smooth(duration: 0.45), value: wishlistsAnimationKey)
            }
            .padding(.bottom, 80)
        }
    }

    // wishlistTile/tileBackground/tileStatusIcon/roleBadgeIcon/formatPrice удалены —
    // были дубликатами WishlistTileView (см. Views/Components/), не использовались.

    // MARK: - Polling

    private func startPolling() {
        // 30 сек — экономим Firestore quota; throttle в DataService всё равно отсечёт
        // более частые вызовы. Когда offline — skip polling tick (не плодим зависающие
        // запросы и спиннер-мигание; NetworkMonitor сам разбудит SyncEngine при появлении сети).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                guard services.networkMonitor.isBlocked == false else { return }
                await services.data?.refreshWishlists()
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
            showingAddSheet = true
        } label: {
            Label("New list", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .glassEffect(.regular.interactive())
        .clipShape(Capsule())
        // Offline-mode: создание списка работает без сети — op уйдёт в outbox и push'нется при сети.
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Wishlist.self, Item.self, AppSettings.self,
        configurations: config
    )

    let wl1 = Wishlist(name: "День рождения", coverEmoji: "\u{1F382}")
    let wl2 = Wishlist(name: "Техника")
    container.mainContext.insert(wl1)
    container.mainContext.insert(wl2)

    let items: [(String, ItemTier, Double?)] = [
        ("Наушники Sony", .must, 12990),
        ("Книга", .maybe, 1500),
        ("Стикеры", .idea, nil),
    ]
    for (name, tier, price) in items {
        let item = Item(name: name, tier: tier, price: price)
        item.wishlist = wl1
        container.mainContext.insert(item)
    }

    let item2 = Item(name: "MacBook Air", tier: .must, price: 119980)
    item2.wishlist = wl2
    container.mainContext.insert(item2)

    try? container.mainContext.save()

    return NavigationStack {
        HomeView()
    }
    .modelContainer(container)
}

