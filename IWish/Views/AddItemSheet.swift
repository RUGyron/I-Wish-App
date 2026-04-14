import SwiftUI
import SwiftData

struct AddItemSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    let wishlist: Wishlist

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var tier: ItemTier = .maybe
    @State private var priceString: String = ""

    private var defaultCurrency: String {
        settingsList.first?.defaultCurrency ?? "RUB"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Чего хочется?", text: $name)
                        .textInputAutocapitalization(.sentences)
                }
                Section("Важность") {
                    Picker("Важность", selection: $tier) {
                        ForEach(ItemTier.allCases) { tier in
                            Text("\(tier.icon) \(tier.label)").tag(tier)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Цена") {
                    TextField("0", text: $priceString)
                        .keyboardType(.numberPad)
                }
                Section("Описание") {
                    TextField("Опционально", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Новое желание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let nextSortIndex = nextSortIndexForTier(tier)
        let item = Item(
            name: trimmedName,
            tier: tier,
            sortIndex: nextSortIndex,
            currency: defaultCurrency,
            price: parsePrice(priceString),
            descriptionText: descriptionText.isEmpty ? nil : descriptionText
        )
        item.wishlist = wishlist
        context.insert(item)
        try? context.save()
        dismiss()
    }

    /// Новый айтем — в конец своего tier (max(sortIndex) + step).
    private func nextSortIndexForTier(_ tier: ItemTier) -> Double {
        let tierItems = wishlist.items.filter { $0.tier == tier && !$0.isArchived }
        let maxIndex = tierItems.map(\.sortIndex).max()
        return SortIndexCalculator.midpoint(after: maxIndex, before: nil)
    }

    private func parsePrice(_ string: String) -> Decimal? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Wishlist.self, Item.self, AppSettings.self, configurations: config)

    let settings = AppSettings(defaultCurrency: "RUB")
    container.mainContext.insert(settings)

    let wishlist = Wishlist(name: "День рождения")
    container.mainContext.insert(wishlist)
    try? container.mainContext.save()

    return AddItemSheet(wishlist: wishlist)
        .modelContainer(container)
}
