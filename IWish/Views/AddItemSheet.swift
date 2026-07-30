import SwiftUI
import SwiftData

struct AddItemSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @Query private var settingsList: [AppSettings]

    let wishlist: Wishlist

    // MARK: - Form state

    @State private var urlString: String = ""
    @State private var name: String = ""
    @State private var coverImageData: Data?
    @State private var coverEmoji: String?
    @State private var tier: ItemTier = .maybe
    @State private var priceMinString: String = ""
    @State private var priceMaxString: String = ""
    @State private var priceMode: PriceModeUI = .exact
    @State private var currency: String = ""
    @State private var descriptionText: String = ""
    @State private var probationEnabled: Bool = false
    @State private var probationDays: Int = 30
    @State private var gradientHue: Double = Double.random(in: 0...1)

    private enum PriceModeUI: String, CaseIterable, Identifiable {
        case exact, range
        var id: String { rawValue }
        var label: String { self == .exact ? String(localized: "Exact") : String(localized: "Range") }
    }

    @State private var urlStatus: URLPasteStatus = .idle
    @State private var fetchedTitle: String?
    @State private var isFetchingMetadata = false
    @State private var errorMessage: String?
    @State private var isSaving = false

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
                if coverImageData == nil {
                    gradientSection
                }
                tierSection
                priceSection
                descriptionSection
                probationSection
            }
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
            )
            .warmBackground()
            .navigationTitle("New wish")
            .fontDesign(.rounded)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(!nameIsValid || isSaving)
                }
            }
            .onAppear { prefillFromSettings() }
            .onChange(of: name) { _, newValue in
                name = InputLimits.truncate(newValue, to: InputLimits.itemName)
            }
            .onChange(of: descriptionText) { _, newValue in
                descriptionText = InputLimits.truncate(newValue, to: InputLimits.itemDescription)
            }
            .onChange(of: urlString) { _, newValue in
                urlString = InputLimits.truncate(newValue, to: InputLimits.itemURL)
            }
        }
        .loadingOverlay(isSaving)
        .alert("Couldn’t add", isPresented: .constant(errorMessage != nil)) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .applyTheme()
    }

    // MARK: - Sections

    private var urlSection: some View {
        URLPasteSection(
            urlString: $urlString,
            fetchedTitle: $fetchedTitle,
            onPasted: { url in fetchMetadata(for: url) },
            isFetching: isFetchingMetadata
        )
    }

    private var nameSection: some View {
        Section("Name") {
            HStack {
                TextField("What do you wish for?", text: $name)
                    .textInputAutocapitalization(.sentences)
                if !name.isEmpty {
                    Button {
                        name = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear name")
                }
            }
        }
    }

    private var coverSection: some View {
        CoverPickerSection(
            imageData: $coverImageData,
            emoji: $coverEmoji
        )
    }

    private var gradientSection: some View {
        Section("Background color") {
            GradientHuePicker(hue: $gradientHue)
                .padding(.vertical, 8)
        }
    }

    private var tierSection: some View {
        Section("Importance") {
            VStack(spacing: 8) {
                Picker("Importance", selection: $tier) {
                    ForEach(ItemTier.allCases) { t in
                        Text(t.emoji).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 2)

                Text(tier.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var priceSection: some View {
        Section("Price") {
            Picker("Type", selection: $priceMode) {
                ForEach(PriceModeUI.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)

            if priceMode == .exact {
                HStack {
                    TextField("0", text: $priceMinString)
                        .keyboardType(.numberPad)

                    Picker("Currency", selection: $currency) {
                        Text(verbatim: "\u{20BD}").tag("RUB")
                        Text(verbatim: "$").tag("USD")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            } else {
                HStack(spacing: 8) {
                    TextField("From", text: $priceMinString)
                        .keyboardType(.numberPad)
                    Text(verbatim: "—")
                        .foregroundStyle(.secondary)
                    TextField("To", text: $priceMaxString)
                        .keyboardType(.numberPad)

                    Picker("Currency", selection: $currency) {
                        Text(verbatim: "\u{20BD}").tag("RUB")
                        Text(verbatim: "$").tag("USD")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var descriptionSection: some View {
        Section("Description") {
            ZStack(alignment: .topTrailing) {
                TextField("Optional", text: $descriptionText, axis: .vertical)
                    .lineLimit(2...6)
                if !descriptionText.isEmpty {
                    Button {
                        descriptionText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear description")
                }
            }
        }
    }

    private var probationSection: some View {
        Section {
            Toggle("Probation period", isOn: $probationEnabled)

            if probationEnabled {
                Picker("Duration", selection: $probationDays) {
                    ForEach(1...365, id: \.self) { day in
                        Text(String(format: NSLocalizedString("%lld дней", comment: ""), day)).tag(day)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
            }
        } footer: {
            if probationEnabled {
                Text("The wish stays hidden until the period ends — if you don’t change your mind, it stays.")
            }
        }
    }

    // MARK: - URL Metadata

    private func fetchMetadata(for url: URL) {
        isFetchingMetadata = true
        let s = settings
        let mode = s?.parseFillMode ?? .empty
        let fillTitle = s?.parseFillTitle ?? true
        let fillImage = s?.parseFillImage ?? true
        let fillPrice = s?.parseFillPrice ?? true
        let fillDesc = s?.parseFillDescription ?? true

        Task {
            let meta = await URLMetadataService.fetch(from: url)
            await MainActor.run {
                isFetchingMetadata = false
                fetchedTitle = meta.title

                guard mode != .off else { return }
                let overwrite = (mode == .overwrite)

                let nameEmpty = name.trimmingCharacters(in: .whitespaces).isEmpty
                if fillTitle, let title = meta.title, (overwrite || nameEmpty) {
                    name = title
                }
                if fillImage, let image = meta.image, (overwrite || coverImageData == nil) {
                    coverImageData = ImageCompressor.compress(image)
                }
                if fillPrice, let price = meta.price, (overwrite || priceMinString.isEmpty) {
                    priceMode = .exact
                    priceMinString = String(Int(price.rounded()))
                }
                if fillPrice, let curr = meta.currency, (overwrite || currency.isEmpty) {
                    currency = curr
                }
                let descEmpty = descriptionText.trimmingCharacters(in: .whitespaces).isEmpty
                if fillDesc, let desc = meta.descriptionText, (overwrite || descEmpty) {
                    descriptionText = desc
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
        guard !isSaving else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let activeCount = (wishlist.items ?? []).filter { !$0.isArchived && !$0.isTombstoned }.count
        guard activeCount < InputLimits.maxItemsPerWishlist else {
            errorMessage = String(format: String(localized: "Limit reached: %lld wishes per list."), InputLimits.maxItemsPerWishlist)
            return
        }

        let trimmedURL = urlString.trimmingCharacters(in: .whitespaces)
        let nextSortIndex = nextSortIndexForTier(tier)
        let probEnd: Date? = probationEnabled
            ? Date.now.addingTimeInterval(Double(probationDays) * 86400)
            : nil

        isSaving = true
        Task {
            do {
                let priceMin = parsePrice(priceMinString)
                let priceMax: Double? = priceMode == .range ? parsePrice(priceMaxString) : nil

                _ = try await services.data?.addItem(
                    to: wishlist.id.uuidString,
                    name: trimmedName,
                    tier: tier,
                    price: priceMin,
                    priceMax: priceMax,
                    currency: currency.isEmpty ? "RUB" : currency,
                    url: trimmedURL.isEmpty ? nil : trimmedURL,
                    emoji: coverEmoji,
                    sortIndex: nextSortIndex,
                    descriptionText: descriptionText.isEmpty ? nil : descriptionText,
                    probationEndAt: probEnd,
                    coverImageData: coverImageData,
                    gradientHue: coverImageData == nil ? gradientHue : nil
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    // MARK: - Helpers

    private func nextSortIndexForTier(_ tier: ItemTier) -> Double {
        let tierItems = (wishlist.items ?? []).filter { $0.tier == tier && !$0.isArchived }
        let maxIndex = tierItems.map(\.sortIndex).max()
        return SortIndexCalculator.midpoint(after: maxIndex, before: nil)
    }

    private func parsePrice(_ string: String) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed).map(Double.init)
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
