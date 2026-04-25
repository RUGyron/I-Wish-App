import SwiftUI

/// Isolated tile view with confirmationDialog instead of contextMenu
struct WishlistTileView: View {
    let wishlist: Wishlist
    let onShare: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var menuEnabled = true

    private var canShare: Bool {
        !wishlist.isShared || wishlist.myRole == "owner" || wishlist.canInvite
    }

    var body: some View {
        NavigationLink {
            WishlistDetailView(wishlist: wishlist)
        } label: {
            tileContent
        }
        .buttonStyle(.plain)
        .allowsHitTesting(menuEnabled)
        .contextMenu {
            if canShare {
                Button { cooldown(); onShare() } label: {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
            }
            Button { cooldown(); onArchive() } label: {
                Label("В архив", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) { cooldown(); onDelete() } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    private func cooldown() {
        menuEnabled = false
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            menuEnabled = true
        }
    }

    private var tileContent: some View {
        let activeItems = (wishlist.items ?? []).filter { !$0.isArchived }
        let total = activeItems.compactMap(\.price).reduce(0, +)

        return ZStack {
            tileBackground
            bottomGradient
            topBadges(activeItems: activeItems)
            bottomContent(activeItems: activeItems, total: total)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .titaniumBorder(cornerRadius: 16)
    }

    @ViewBuilder
    private var tileBackground: some View {
        if let imageData = wishlist.coverImageData, let uiImage = UIImage(data: imageData) {
            GeometryReader { geo in
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else {
            let colors = DefaultCoverGenerator.colors(forSeed: wishlist.gradientSeed != 0 ? wishlist.gradientSeed : DefaultCoverGenerator.stableHash(wishlist.id.uuidString))
            GeometryReader { geo in
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
                    .frame(width: geo.size.width, height: geo.size.height)
                    if let emoji = wishlist.coverEmoji {
                        Text(emoji).font(.system(size: 44))
                    }
                }
            }
        }
    }

    private var bottomGradient: some View {
        VStack {
            Spacer()
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
        }
    }

    private func topBadges(activeItems: [Item]) -> some View {
        VStack {
            HStack {
                // Stats chip (top-left)
                HStack(spacing: 0) {
                    HStack(spacing: 3) {
                        Image(systemName: "gift")
                            .font(.system(size: 9))
                        Text("\(activeItems.count)")
                            .font(.caption2.weight(.medium))
                    }
                    Text(" · ")
                        .font(.caption2)
                    HStack(spacing: 3) {
                        Image(systemName: "person.2")
                            .font(.system(size: 9))
                        Text("\(max(wishlist.memberCount, 1))")
                            .font(.caption2.weight(.medium))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.35), in: Capsule())

                Spacer()

                // Status badge (top-right)
                Image(systemName: statusIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.35), in: Circle())
            }
            Spacer()
        }
        .padding(8)
    }

    private func bottomContent(activeItems: [Item], total: Double) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text(wishlist.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    private var statusIcon: String {
        if !wishlist.isShared || wishlist.memberCount <= 1 {
            return "lock.fill"
        }
        switch wishlist.myRole {
        case "owner": return "crown.fill"
        case "editor": return "pencil"
        case "viewer": return "eye"
        default: return "lock.fill"
        }
    }
}
