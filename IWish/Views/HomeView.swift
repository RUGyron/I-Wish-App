import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appServices) private var services
    @Query(sort: \Wishlist.createdAt, order: .reverse) private var wishlists: [Wishlist]
    @State private var showingAddSheet = false
    @State private var showingSettings = false
    @State private var showingJoin = false
    @State private var pullOffset: CGFloat = 0

    private var activeWishlists: [Wishlist] {
        wishlists.filter { !($0.isArchived) }
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

    var body: some View {
        Group {
            if activeWishlists.isEmpty {
                emptyState
            } else {
                wishlistList
            }
        }
        .navigationTitle("Вишлисты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveShareLink)) { _ in
            showingJoin = true
        }
        .overlay(alignment: .bottom) {
            addButton
                .padding(.bottom, 24)
        }
    }

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
        List {
            Section {
                ForEach(activeWishlists) { wishlist in
                    NavigationLink {
                        WishlistDetailView(wishlist: wishlist)
                    } label: {
                        wishlistRow(wishlist)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            context.delete(wishlist)
                            try? context.save()
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }

                        Button {
                            wishlist.isArchived = true
                            wishlist.updatedAt = .now
                            try? context.save()
                        } label: {
                            Label("Архив", systemImage: "archivebox")
                        }
                        .tint(.blue)

                        Button {
                            // Share action placeholder — ties into ShareWishlistSheet
                        } label: {
                            Label("Поделиться", systemImage: "square.and.arrow.up")
                        }
                        .tint(.green)
                    }
                }
            } header: {
                Text("\(String(format: NSLocalizedString("%lld списков", comment: ""), activeWishlists.count)) \u{00B7} \(String(format: NSLocalizedString("%lld желаний", comment: ""), totalItems))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .contentMargins(.bottom, 80)
        .warmBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            SyncStatusPullHeader(
                state: services.syncStatus.state,
                pullOffset: pullOffset,
                isPermissionDenied: services.userProfile.discoverabilityStatus == .denied
            ) {
                services.syncStatus.retry(context: context)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, newValue in
            pullOffset = max(0, -newValue)
        }
    }

    private func wishlistRow(_ wishlist: Wishlist) -> some View {
        let activeItems = (wishlist.items ?? []).filter { !$0.isArchived }

        return HStack(spacing: 12) {
            DefaultCoverView(
                id: wishlist.id,
                imageData: wishlist.coverImageData,
                emoji: wishlist.coverEmoji
            )
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(wishlist.name)
                    .font(.headline)

                HStack(spacing: 4) {
                    Text(String(format: NSLocalizedString("%lld желаний", comment: ""), activeItems.count))
                    tierBadgeRow(for: activeItems)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tierBadgeRow(for items: [Item]) -> some View {
        let counts = Dictionary(grouping: items, by: \.tier)
        let activeTiers = ItemTier.allCases.filter { counts[$0]?.count ?? 0 > 0 }

        ForEach(activeTiers) { tier in
            if let count = counts[tier]?.count {
                Text("\u{00B7}")
                Text(tier.emoji)
                Text("\(count)")
            }
        }
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
