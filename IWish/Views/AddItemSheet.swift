import SwiftUI
import SwiftData
import LinkPresentation

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
    @State private var tier: ItemTier = .maybe
    @State private var priceString: String = ""
    @State private var currency: String = ""
    @State private var descriptionText: String = ""
    @State private var probationEnabled: Bool = false
    @State private var probationDays: Int = 30

    @State private var urlStatus: URLPasteStatus = .idle
    @State private var isFetchingMetadata = false

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
            .warmBackground()
            .navigationTitle("Новое желание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .padding(.trailing, 4)
                }
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
            if urlString.isEmpty {
                Button {
                    pasteURL()
                } label: {
                    Label("Вставить ссылку", systemImage: "doc.on.clipboard")
                }

                if case .noURL = urlStatus {
                    Text("Нет ссылки в буфере")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Text(urlString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if isFetchingMetadata {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        urlString = ""
                        urlStatus = .idle
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
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
            emoji: $coverEmoji
        )
    }

    private var tierSection: some View {
        Section("Важность") {
            VStack(spacing: 8) {
                GlassSegmentedPicker(selection: $tier) { t in
                    Image(systemName: t.symbolName)
                }

                Text(tier.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var priceSection: some View {
        Section("Цена") {
            HStack {
                TextField("0", text: $priceString)
                    .keyboardType(.numberPad)

                Picker("Валюта", selection: $currency) {
                    Text("\u{20BD}").tag("RUB")
                    Text("$").tag("USD")
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
                Picker("Длительность", selection: $probationDays) {
                    ForEach(1...365, id: \.self) { day in
                        Text("\(day) \(daysDeclension(day))").tag(day)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
            }
        } footer: {
            if probationEnabled {
                Text("Желание скроется до окончания срока — если за это время не передумаешь, оно останется.")
            }
        }
    }

    // MARK: - URL Paste + Metadata

    private func pasteURL() {
        guard let clipboard = UIPasteboard.general.string,
              let url = URL(string: clipboard),
              url.scheme != nil else {
            urlStatus = .noURL
            return
        }

        urlString = clipboard
        urlStatus = .pasted
        fetchMetadata(for: url)
    }

    private func fetchMetadata(for url: URL) {
        isFetchingMetadata = true
        let provider = LPMetadataProvider()

        provider.startFetchingMetadata(for: url) { metadata, _ in
            Task { @MainActor in
                isFetchingMetadata = false
                guard let metadata else { return }

                // Auto-fill name if empty
                if name.trimmingCharacters(in: .whitespaces).isEmpty,
                   let title = metadata.title {
                    name = title
                }

                // Auto-fill cover image if none selected
                if let imageProvider = metadata.imageProvider {
                    imageProvider.loadObject(ofClass: UIImage.self) { object, _ in
                        if let image = object as? UIImage {
                            Task { @MainActor in
                                if coverImageData == nil {
                                    coverImageData = ImageCompressor.compress(image)
                                }
                            }
                        }
                    }
                }
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

// MARK: - URL paste status

private enum URLPasteStatus {
    case idle
    case pasted
    case noURL
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
