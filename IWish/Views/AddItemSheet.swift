import SwiftUI
import SwiftData

struct AddItemSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    let wishlist: Wishlist

    // MARK: - Form state

    @State private var urlString: String = ""
    @State private var name: String = ""
    @State private var coverImageData: Data?
    @State private var coverEmoji: String?
    @State private var previewID = UUID()
    @State private var tier: ItemTier = .maybe
    @State private var priceString: String = ""
    @State private var currency: String = ""
    @State private var descriptionText: String = ""
    @State private var probationEnabled: Bool = false
    @State private var probationDays: Int = 30

    // MARK: - Derived

    private var settings: AppSettings? { settingsList.first }

    private var nameIsValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                urlSection
                nameSection
                coverSection
                tierSection
                priceSection
                descriptionSection
                probationSection
            }
            .navigationTitle("Новое желание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }
                        .disabled(!nameIsValid)
                }
            }
            .onAppear { prefillFromSettings() }
        }
        .applyTheme()
    }

    // MARK: - Sections

    private var urlSection: some View {
        Section("Ссылка") {
            TextField("https://...", text: $urlString)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var nameSection: some View {
        Section("Название") {
            TextField("Чего хочется?", text: $name)
                .textInputAutocapitalization(.sentences)
        }
    }

    private var coverSection: some View {
        CoverPickerSection(
            imageData: $coverImageData,
            emoji: $coverEmoji,
            previewID: previewID
        )
    }

    private var tierSection: some View {
        Section("Важность") {
            TierPicker(selection: $tier)
        }
    }

    private var priceSection: some View {
        Section("Цена") {
            HStack {
                TextField("0", text: $priceString)
                    .keyboardType(.numberPad)

                Picker("Валюта", selection: $currency) {
                    Text("RUB").tag("RUB")
                    Text("USD").tag("USD")
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var descriptionSection: some View {
        Section("Описание") {
            TextField("Опционально", text: $descriptionText, axis: .vertical)
                .lineLimit(2...6)
        }
    }

    private var probationSection: some View {
        Section {
            Toggle("Испытательный срок", isOn: $probationEnabled)

            if probationEnabled {
                Stepper(
                    "\(probationDays) \(daysDeclension(probationDays))",
                    value: $probationDays,
                    in: 1...365
                )
            }
        } footer: {
            if probationEnabled {
                Text("Желание скроется до окончания срока — если за это время не передумаешь, оно останется.")
            }
        }
    }

    // MARK: - Prefill

    private func prefillFromSettings() {
        guard let settings else { return }
        currency = settings.defaultCurrency
        probationEnabled = settings.probationEnabledByDefault
        probationDays = settings.probationDurationDays
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let trimmedURL = urlString.trimmingCharacters(in: .whitespaces)
        let nextSortIndex = nextSortIndexForTier(tier)

        let item = Item(
            name: trimmedName,
            tier: tier,
            sortIndex: nextSortIndex,
            currency: currency.isEmpty ? "RUB" : currency,
            price: parsePrice(priceString),
            descriptionText: descriptionText.isEmpty ? nil : descriptionText,
            url: trimmedURL.isEmpty ? nil : trimmedURL,
            coverImageData: coverImageData,
            coverEmoji: coverEmoji
        )

        if probationEnabled {
            item.probationEndAt = Date.now.addingTimeInterval(Double(probationDays) * 86400)
        }

        item.wishlist = wishlist
        context.insert(item)
        try? context.save()
        dismiss()
    }

    // MARK: - Helpers

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

    private func daysDeclension(_ n: Int) -> String {
        let mod10 = n % 10
        let mod100 = n % 100
        if mod10 == 1 && mod100 != 11 {
            return "день"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            return "дня"
        } else {
            return "дней"
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Wishlist.self, Item.self, AppSettings.self,
        configurations: config
    )

    let settings = AppSettings(
        defaultCurrency: "RUB",
        probationEnabledByDefault: true,
        defaultProbationDuration: 30 * 86400
    )
    container.mainContext.insert(settings)

    let wishlist = Wishlist(name: "День рождения")
    container.mainContext.insert(wishlist)
    try? container.mainContext.save()

    return AddItemSheet(wishlist: wishlist)
        .modelContainer(container)
}
