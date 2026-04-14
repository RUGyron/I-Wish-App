import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Wishlist.createdAt, order: .reverse) private var wishlists: [Wishlist]
    @State private var showingAddSheet = false
    @State private var showingSettings = false

    var body: some View {
        Group {
            if wishlists.isEmpty {
                emptyState
            } else {
                wishlistList
            }
        }
        .navigationTitle("Желания")
        .toolbar {
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
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView() }
        }
        .overlay(alignment: .bottom) {
            addButton
        }
    }

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
    }

    private var wishlistList: some View {
        List {
            ForEach(wishlists) { wishlist in
                NavigationLink {
                    WishlistDetailView(wishlist: wishlist)
                } label: {
                    HStack(spacing: 12) {
                        DefaultCoverView(
                            id: wishlist.id,
                            imageData: wishlist.coverImageData,
                            emoji: wishlist.coverEmoji
                        )
                        .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(wishlist.name)
                                .font(.headline)
                            Text("\(wishlist.items.count) желаний")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete(perform: deleteWishlists)
        }
    }

    private var addButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            Label("Новый список", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.bottom, 16)
    }

    private func deleteWishlists(offsets: IndexSet) {
        for index in offsets {
            context.delete(wishlists[index])
        }
        try? context.save()
    }
}
