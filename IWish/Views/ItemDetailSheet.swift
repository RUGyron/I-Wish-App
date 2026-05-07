import SwiftUI
import SwiftData

/// Подробный просмотр желания. Открывается тапом на карточку в списке.
/// Карандаш в toolbar открывает `EditItemSheet` поверх для редактирования.
struct ItemDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services

    let item: Item
    /// Wishlist нужен для проверки прав на редактирование (viewer не может).
    let wishlist: Wishlist

    @State private var showingEdit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    coverHero
                    headerBlock
                    if let description = item.descriptionText, !description.isEmpty {
                        descriptionBlock(description)
                    }
                    metaBlock
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Желание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                if wishlist.isEditable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            showingEdit = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingEdit) {
                EditItemSheet(item: item)
                    .applyTheme()
            }
        }
        .applyTheme()
    }

    // MARK: - Cover

    private var coverHero: some View {
        DefaultCoverView(
            id: item.id,
            imageData: item.coverImageData,
            emoji: item.coverEmoji
        )
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Header (tier badge + name + price)

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            tierBadge
            Text(item.name)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let priceText = priceFullText {
                Text(priceText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
            }
        }
    }

    /// Полное отображение цены: точная или "X — Y" для диапазона.
    /// На карточке (WishlistDetailView) показываем сокращённо "до Y", здесь — целиком.
    private var priceFullText: String? {
        switch item.priceMode {
        case .none: return nil
        case .exact(let p): return formatPrice(p, currency: item.currency)
        case .range(let min, let max):
            return "\(formatPrice(min, currency: item.currency)) — \(formatPrice(max, currency: item.currency))"
        }
    }

    private var tierBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(item.tier.stripeColor)
                .frame(width: 8, height: 8)
            Text(item.tier.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(item.tier.stripeColor.opacity(0.12), in: Capsule())
    }

    // MARK: - Description

    private func descriptionBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Описание")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Meta (date, author, url, probation)

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            metaRow(icon: "calendar", text: item.createdAt.formatted(.dateTime.day().month(.wide).year()))

            if wishlist.isShared, let author = authorLabel() {
                Divider().padding(.leading, 36)
                metaRow(icon: "person", text: author)
            }

            if let urlString = item.url, !urlString.isEmpty, let url = URL(string: urlString) {
                Divider().padding(.leading, 36)
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    metaRow(
                        icon: "link",
                        text: extractDomain(urlString) ?? urlString,
                        accent: true
                    )
                }
                .buttonStyle(.plain)
            }

            if let days = probationDaysLeft() {
                Divider().padding(.leading, 36)
                metaRow(
                    icon: "clock",
                    text: "Испытательный срок: \(days) дн."
                )
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func metaRow(icon: String, text: String, accent: Bool = false) -> some View {
        HStack(spacing: 12) {
            Group {
                if accent {
                    Image(systemName: icon).foregroundStyle(.tint)
                } else {
                    Image(systemName: icon).foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .frame(width: 24)

            Group {
                if accent {
                    Text(text).foregroundStyle(.tint)
                } else {
                    Text(text).foregroundStyle(.primary)
                }
            }
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func authorLabel() -> String? {
        guard let name = item.addedByName, !name.isEmpty else { return nil }
        if let myUID = services.auth.uid, item.addedByUID == myUID {
            return "Добавили вы"
        }
        return "Добавил(а): \(name)"
    }

    private func probationDaysLeft() -> Int? {
        guard let end = item.probationEndAt else { return nil }
        let now = Date.now
        guard end > now else { return nil }
        let comps = Calendar.current.dateComponents([.day], from: now, to: end)
        return comps.day
    }

    private func formatPrice(_ price: Double, currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: price)) ?? "\(Int(price))"
    }

    private func extractDomain(_ urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host() else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}
