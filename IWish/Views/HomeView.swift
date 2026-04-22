import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appServices) private var services
    @Query(sort: \Wishlist.createdAt, order: .reverse) private var wishlists: [Wishlist]
    @State private var showingAddSheet = false
    @State private var showingSettings = false
    @State private var showingJoin = false
    @State private var sharingWishlist: Wishlist?
    @State private var sharedWishlists: [FirestoreService.SharedWishlistInfo] = []

    // MARK: - Debug

    #if DEBUG
    @State private var debugListMode = 0 // 0=real, 1=empty, 2=full
    @State private var debugInserted: [Wishlist] = []
    #endif

    private var activeWishlists: [Wishlist] {
        #if DEBUG
        if debugListMode == 1 { return [] }
        #endif
        return wishlists.filter { !($0.isArchived) }
    }

    private var syncShouldForceShow: Bool {
        switch services.syncStatus.state {
        case .syncing, .error, .offline: return true
        default: return false
        }
    }

    private var totalItems: Int {
        activeWishlists.reduce(0) { $0 + ($1.items ?? []).filter { !$0.isArchived }.count }
    }

    private var showDiscoverabilitySheet: Binding<Bool> {
        Binding(
            get: { services.userProfile.discoverabilityStatus == .askingCustom },
            set: { newValue in
                if !newValue && services.userProfile.discoverabilityStatus == .askingCustom {
                    services.userProfile.declineCustomDialog()
                }
            }
        )
    }

    private var hasAnyWishlists: Bool {
        !activeWishlists.isEmpty || !sharedWishlists.isEmpty
    }

    var body: some View {
        Group {
            if hasAnyWishlists {
                wishlistList
            } else {
                emptyState
            }
        }
        .navigationTitle("Вишлисты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    homeNavTitle
                    if syncShouldForceShow || services.syncStatus.hasEverSynced {
                        syncSubtitle
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: services.syncStatus.state)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingJoin = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
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
        .sheet(isPresented: showDiscoverabilitySheet) {
            DiscoverabilitySheet(
                onAllow: { services.userProfile.confirmCustomDialog() },
                onDeny: { services.userProfile.declineCustomDialog() }
            )
            .applyTheme()
        }
        .onAppear {
            services.userProfile.requestDiscoverability()
        }
        .task {
            await fetchSharedWishlists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveShareLink)) { _ in
            showingJoin = true
        }
        .overlay(alignment: .bottom) {
            addButton
                .padding(.bottom, 24)
        }
    }

    // MARK: - Debug

    private var homeNavTitle: some View {
        Text("Вишлисты").font(.headline)
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
            Text("Пока пусто")
                .font(.title3)
            Text("Создай первый список — начнём собирать желания.")
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

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(activeWishlists) { wishlist in
                        NavigationLink {
                            WishlistDetailView(wishlist: wishlist)
                        } label: {
                            wishlistTile(wishlist)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                sharingWishlist = wishlist
                            } label: {
                                Label("Поделиться", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                wishlist.isArchived = true
                                wishlist.updatedAt = .now
                                try? context.save()
                            } label: {
                                Label("В архив", systemImage: "archivebox")
                            }
                            Divider()
                            Button(role: .destructive) {
                                context.delete(wishlist)
                                try? context.save()
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }

                    // Shared wishlists from PublicDB (not owned locally)
                    ForEach(sharedWishlists, id: \.wishlistID) { info in
                        NavigationLink {
                            if let local = localWishlist(for: info) {
                                WishlistDetailView(wishlist: local)
                            }
                        } label: {
                            sharedWishlistTile(info)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 80)
        }
        .warmBackground()
    }

    private func wishlistTile(_ wishlist: Wishlist) -> some View {
        let activeItems = (wishlist.items ?? []).filter { !$0.isArchived }
        let total = activeItems.compactMap(\.price).reduce(0, +)

        return ZStack(alignment: .bottomLeading) {
            if let imageData = wishlist.coverImageData, let uiImage = UIImage(data: imageData) {
                GeometryReader { geo in
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                let colors = DefaultCoverGenerator.colors(for: wishlist.id)
                ZStack {
                    MeshGradient(
                        width: 3, height: 3,
                        points: [
                            .init(0, 0),   .init(0.5, 0),   .init(1, 0),
                            .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                            .init(0, 1),   .init(0.5, 1),   .init(1, 1),
                        ],
                        colors: [
                            colors[0], colors[1], colors[2],
                            colors[1], colors[2], colors[0],
                            colors[2], colors[0], colors[1],
                        ]
                    )
                    if let emoji = wishlist.coverEmoji {
                        Text(emoji).font(.system(size: 48))
                    }
                }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(wishlist.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if wishlist.isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                if total > 0 {
                    Text(formatPrice(total, currency: activeItems.first(where: { $0.price != nil })?.currency ?? "RUB"))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text(String(format: NSLocalizedString("%lld желаний", comment: ""), activeItems.count))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(10)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .titaniumBorder(cornerRadius: 16)
    }

    // MARK: - Shared Wishlists

    private func fetchSharedWishlists() async {
        do {
            guard let uid = services.auth.uid else { return }

            let memberships = try await services.firestore.fetchMyMemberships(userUID: uid)

            var fetched: [FirestoreService.SharedWishlistInfo] = []
            for membership in memberships {
                if let info = try? await services.firestore.fetchSharedWishlist(wishlistID: membership.wishlistID) {
                    fetched.append(info)
                }
            }

            // Filter out wishlists that already exist locally (owned by us)
            let localIDs = Set(activeWishlists.map(\.id.uuidString))
            sharedWishlists = fetched.filter { !localIDs.contains($0.wishlistID) }

            // Ensure each shared wishlist has a local copy for WishlistDetailView
            for info in sharedWishlists {
                ensureLocalCopy(for: info)
            }
        } catch {
            sharedWishlists = []
        }
    }

    /// Creates a local Wishlist in SwiftData if one doesn't exist for this shared wishlist.
    private func ensureLocalCopy(for info: FirestoreService.SharedWishlistInfo) {
        guard let uuid = UUID(uuidString: info.wishlistID) else { return }

        // Check if local copy already exists
        let existing = wishlists.first { $0.id == uuid }
        if existing != nil { return }

        let local = Wishlist(
            name: info.name,
            coverEmoji: info.coverEmoji,
            ownerRecordID: info.ownerUID,
            isShared: true
        )
        // Override the auto-generated UUID with the shared one
        local.id = uuid
        context.insert(local)

        // Create local items from shared items
        for (idx, sharedItem) in info.items.enumerated() {
            let tier: ItemTier
            switch sharedItem.tier {
            case "must": tier = .must
            case "maybe": tier = .maybe
            default: tier = .idea
            }
            let item = Item(
                name: sharedItem.name,
                tier: tier,
                currency: sharedItem.currency,
                price: sharedItem.price,
                url: sharedItem.url
            )
            item.coverEmoji = sharedItem.coverEmoji
            item.sortIndex = sharedItem.sortIndex
            item.isArchived = sharedItem.isArchived
            item.wishlist = local
            if let itemUUID = UUID(uuidString: sharedItem.itemID) {
                item.id = itemUUID
            }
            context.insert(item)
        }

        try? context.save()
    }

    /// Finds local Wishlist matching a SharedWishlistInfo by UUID.
    private func localWishlist(for info: FirestoreService.SharedWishlistInfo) -> Wishlist? {
        guard let uuid = UUID(uuidString: info.wishlistID) else { return nil }
        return wishlists.first { $0.id == uuid }
    }

    private func sharedWishlistTile(_ info: FirestoreService.SharedWishlistInfo) -> some View {
        let itemCount = info.items.filter { !$0.isArchived }.count
        let tileUUID = UUID(uuidString: info.wishlistID) ?? UUID()
        let colors = DefaultCoverGenerator.colors(for: tileUUID)

        return ZStack(alignment: .bottomLeading) {
            ZStack {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        .init(0, 0),   .init(0.5, 0),   .init(1, 0),
                        .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                        .init(0, 1),   .init(0.5, 1),   .init(1, 1),
                    ],
                    colors: [
                        colors[0], colors[1], colors[2],
                        colors[1], colors[2], colors[0],
                        colors[2], colors[0], colors[1],
                    ]
                )
                if let emoji = info.coverEmoji {
                    Text(emoji).font(.system(size: 48))
                }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(info.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                if let ownerName = info.ownerName {
                    Text(ownerName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text(String(format: NSLocalizedString("%lld желаний", comment: ""), itemCount))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(10)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .titaniumBorder(cornerRadius: 16)
    }

    private func formatPrice(_ price: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "\(Int(price)) \(currency)"
    }

    // MARK: - Sync Subtitle (in navbar)

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

    // MARK: - Sync Badge (scrolls with list)

    @ViewBuilder
    private var syncBadgeRow: some View {
        let denied = services.userProfile.discoverabilityStatus == .denied
        let isError: Bool = {
            switch services.syncStatus.state {
            case .error, .offline: return true
            default: return false
            }
        }()

        HStack {
            Spacer()
            SyncStatusBadge(
                state: denied ? .idle : services.syncStatus.state,
                onTap: isError ? { services.syncStatus.retry(context: context) } : nil
            )
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - FAB

    private var addButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            Label("Новый список", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.titaniumGradient, lineWidth: 0.5))
        }
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

