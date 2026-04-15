import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Wishlist.createdAt, order: .reverse) private var wishlists: [Wishlist]
    @State private var showingAddSheet = false
    @State private var showingSettings = false
    @State private var showingJoin = false
    @State private var userProfile = UserProfileService()
    @State private var syncStatus = SyncStatusService()

    private var totalItems: Int {
        wishlists.reduce(0) { $0 + ($1.items ?? []).filter { !$0.isArchived }.count }
    }

    var body: some View {
        Group {
            if wishlists.isEmpty {
                emptyState
            } else {
                wishlistList
            }
        }
        .navigationTitle("Желания")
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
        .onAppear {
            userProfile.fetchProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveShareLink)) { _ in
            showingJoin = true
        }
        .overlay(alignment: .bottom) {
            addButton
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(userProfile.userName.map { "Привет, \($0)!" } ?? "Привет!")
                .font(.title2.weight(.semibold))

            SyncStatusBadge(state: syncStatus.state)

            Spacer().frame(height: 20)

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
                ForEach(wishlists) { wishlist in
                    NavigationLink {
                        WishlistDetailView(wishlist: wishlist)
                    } label: {
                        wishlistRow(wishlist)
                    }
                }
                .onDelete(perform: deleteWishlists)
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(userProfile.userName.map { "Привет, \($0)!" } ?? "Привет!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("\(wishlists.count) списков \u{00B7} \(totalItems) желаний")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        SyncStatusBadge(state: syncStatus.state)
                    }
                }
                .textCase(nil)
            }
        }
        .contentMargins(.bottom, 80)
        .warmBackground()
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
                    Text("\(activeItems.count) желаний")
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
                Image(systemName: tier.symbolName)
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
        .padding(.bottom, 16)
    }

    // MARK: - Actions

    private func deleteWishlists(offsets: IndexSet) {
        for index in offsets {
            context.delete(wishlists[index])
        }
        try? context.save()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Wishlist.self, Item.self, AppSettings.self,
        configurations: config
    )

    let wl1 = Wishlist(name: "День рождения", coverEmoji: "🎂")
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
