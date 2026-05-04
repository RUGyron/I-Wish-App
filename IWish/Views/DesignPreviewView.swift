import SwiftUI

// MARK: - Mock data

private struct MockItem: Identifiable {
    let id = UUID()
    let name: String
    let price: Double?
    let currency: String
    let tier: ItemTier
    let dateText: String
    let url: String?
    let probationDays: Int?
    /// nil — personal wishlist (без подписи); иначе строка отображается как имя автора.
    let authorLabel: String?
    let coverEmoji: String?
    let coverImageData: Data? = nil
    let gradientSeed: Int

    static let samples: [MockItem] = [
        MockItem(
            name: "Кофе-машина De'Longhi",
            price: 89_990,
            currency: "RUB",
            tier: .must,
            dateText: "4 мая",
            url: "https://wildberries.ru/p/12345",
            probationDays: 5,
            authorLabel: "Anastasia",
            coverEmoji: "☕",
            gradientSeed: 12345
        ),
        MockItem(
            name: "Очень длинное название желания которое не должно ломать высоту карточки в списке",
            price: 159_990,
            currency: "RUB",
            tier: .must,
            dateText: "вчера",
            url: "https://aliexpress.ru/very-long-product-id",
            probationDays: nil,
            authorLabel: "Влад Пивош",
            coverEmoji: nil,
            gradientSeed: 9876
        ),
        MockItem(
            name: "Стикеры с котиками",
            price: nil,
            currency: "RUB",
            tier: .idea,
            dateText: "2 мая",
            url: nil,
            probationDays: nil,
            authorLabel: "Anastasia",
            coverEmoji: "🐱",
            gradientSeed: 4242
        ),
        MockItem(
            name: "Книга «Дюна» Фрэнк Герберт",
            price: nil,
            currency: "RUB",
            tier: .maybe,
            dateText: "1 мая",
            url: "https://ozon.ru/dune",
            probationDays: nil,
            authorLabel: "Вы",
            coverEmoji: "📕",
            gradientSeed: 7777
        ),
        MockItem(
            name: "Записная книжка Moleskine",
            price: 2_490,
            currency: "RUB",
            tier: .must,
            dateText: "30 апр",
            url: nil,
            probationDays: nil,
            authorLabel: nil, // personal wishlist
            coverEmoji: nil,
            gradientSeed: 22222
        ),
        MockItem(
            name: "AirPods Pro 2",
            price: 24_990,
            currency: "RUB",
            tier: .maybe,
            dateText: "29 апр",
            url: "https://apple.com/airpods-pro",
            probationDays: 14,
            authorLabel: "Anastasia",
            coverEmoji: "🎧",
            gradientSeed: 333
        ),
        MockItem(
            name: "Подарок-сюрприз",
            price: nil,
            currency: "RUB",
            tier: .idea,
            dateText: "сегодня",
            url: nil,
            probationDays: nil,
            authorLabel: "Вы",
            coverEmoji: "🎁",
            gradientSeed: 11111
        ),
    ]
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

// MARK: - Финальная карточка (зеркало `WishlistDetailView.itemRow`)

private struct FinalCard: View {
    let item: MockItem

    private let stripeWidth: CGFloat = 4
    private let coverSize: CGFloat = 52
    private let topRowHeight: CGFloat = 16
    private let titleRowHeight: CGFloat = 22
    private let bottomRowHeight: CGFloat = 16

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(item.tier.stripeColor)
                .frame(width: stripeWidth)

            HStack(alignment: .top, spacing: 12) {
                DefaultCoverView(
                    id: item.id,
                    imageData: item.coverImageData,
                    emoji: item.coverEmoji
                )
                .frame(width: coverSize, height: coverSize)

                VStack(alignment: .leading, spacing: 2) {
                    topRow
                    titleRow
                    bottomRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 10)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private var topRow: some View {
        HStack(spacing: 6) {
            if let author = item.authorLabel {
                Text(author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(item.dateText)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 4)

            if let price = item.price {
                Text(formatPrice(price, currency: item.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .layoutPriority(1)
                    .lineLimit(1)
            }
        }
        .frame(height: topRowHeight)
    }

    private var titleRow: some View {
        Text(item.name)
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: titleRowHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomRow: some View {
        HStack(spacing: 8) {
            if let urlString = item.url, let domain = extractDomain(urlString) {
                HStack(spacing: 3) {
                    Image(systemName: "link")
                    Text(domain)
                }
                .foregroundStyle(.tint)
                .lineLimit(1)
            }
            if let days = item.probationDays {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                    Text("\(days) дн.")
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .frame(height: bottomRowHeight)
    }
}

// MARK: - Preview screen

struct DesignPreviewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Превью карточки желания")
                    .font(.headline)
                Text("Зеркало того, что в реальном списке. 7 кейсов с разным наполнением — для проверки что ничего не ломает высоту и не теряется.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                VStack(spacing: 0) {
                    ForEach(Array(MockItem.samples.enumerated()), id: \.offset) { idx, item in
                        FinalCard(item: item)
                        if idx < MockItem.samples.count - 1 {
                            Divider()
                                .padding(.leading, 78)
                        }
                    }
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                legend
                    .padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Превью карточки")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Тестовые кейсы (все семь карточек разные):")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            legendRow("1", "всё заполнено: цена, ссылка, испытательный срок, автор, фото-эмодзи")
            legendRow("2", "длинное название (truncate'ится — высота не растёт)")
            legendRow("3", "минимум: только название и tier=Идея")
            legendRow("4", "без цены, со ссылкой, автор «Вы»")
            legendRow("5", "personal — нет автора, нет фото")
            legendRow("6", "с probation, без описания")
            legendRow("7", "только название, idea, автор «Вы»")
        }
    }

    private func legendRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(num + ".")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
