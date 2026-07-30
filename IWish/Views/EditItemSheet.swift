import SwiftUI
import SwiftData
import LinkPresentation

struct EditItemSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @Environment(\.toast) private var toast

    let item: Item

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var coverImageData: Data?
    @State private var coverEmoji: String?
    @State private var tier: ItemTier = .maybe
    @State private var priceMinString: String = ""
    @State private var priceMaxString: String = ""
    @State private var priceMode: PriceModeUI = .exact
    @State private var currency: String = "RUB"
    @State private var urlString: String = ""
    @State private var fetchedTitle: String?
    @State private var isFetchingMetadata = false
    @State private var probationEnabled: Bool = false
    @State private var probationDays: Int = 30
    @State private var isSaving = false
    @State private var gradientHue: Double = 0.5

    private enum PriceModeUI: String, CaseIterable, Identifiable {
        case exact, range
        var id: String { rawValue }
        var label: String { self == .exact ? String(localized: "Exact") : String(localized: "Range") }
    }

    var body: some View {
        NavigationStack {
            Form {
                URLPasteSection(
                    urlString: $urlString,
                    fetchedTitle: $fetchedTitle,
                    onPasted: { url in fetchMetadata(for: url) },
                    isFetching: isFetchingMetadata
                )

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

                CoverPickerSection(imageData: $coverImageData, emoji: $coverEmoji)

                if coverImageData == nil {
                    Section("Background color") {
                        GradientHuePicker(hue: $gradientHue)
                            .padding(.vertical, 8)
                    }
                }

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
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
            )
            .warmBackground()
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .fontDesign(.rounded)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { prefill() }
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
        .applyTheme()
    }

    private func prefill() {
        name = item.name
        descriptionText = item.descriptionText ?? ""
        coverImageData = item.coverImageData
        coverEmoji = item.coverEmoji
        tier = item.tier
        priceMinString = item.priceValue.map { String(Int($0)) } ?? ""
        priceMaxString = item.priceMaxValue.map { String(Int($0)) } ?? ""
        priceMode = item.priceMaxValue != nil ? .range : .exact
        currency = item.currency
        urlString = item.url ?? ""
        probationEnabled = item.probationEndAt != nil
        if let end = item.probationEndAt {
            let days = Calendar.current.dateComponents([.day], from: .now, to: end).day ?? 30
            probationDays = max(1, days)
        }
        gradientHue = item.gradientHue ?? Double.random(in: 0...1)
    }

    private func fetchMetadata(for url: URL) {
        isFetchingMetadata = true
        Task {
            let meta = await URLMetadataService.fetch(from: url)
            await MainActor.run {
                isFetchingMetadata = false
                fetchedTitle = meta.title
                // В EditItemSheet НЕ перезатираем существующее имя/обложку — юзер уже выбрал.
                // Цену и валюту тоже не трогаем — могут быть выставлены вручную.
            }
        }
    }

    private func save() {
        guard !isSaving else { return }

        let wishlistID = item.wishlist?.id.uuidString ?? ""
        let probEnd: Date? = probationEnabled
            ? Date.now.addingTimeInterval(Double(probationDays) * 86400)
            : nil

        isSaving = true
        Task {
            do {
                let priceMin = parsePrice(priceMinString)
                let priceMax: Double? = priceMode == .range ? parsePrice(priceMaxString) : nil

                try await services.data?.updateItem(
                    id: item.id.uuidString,
                    wishlistID: wishlistID,
                    name: name.trimmingCharacters(in: .whitespaces),
                    tier: tier,
                    price: priceMin,
                    priceMax: priceMax,
                    currency: currency,
                    url: urlString.isEmpty ? nil : urlString,
                    emoji: coverEmoji,
                    sortIndex: item.sortIndex,
                    isArchived: item.isArchived,
                    descriptionText: descriptionText.isEmpty ? nil : descriptionText,
                    coverImageData: coverImageData,
                    linkMetadataData: item.linkMetadataData,
                    probationEndAt: probEnd,
                    gradientHue: coverImageData == nil ? gradientHue : nil
                )
                dismiss()
            } catch {
                toast.error(error.localizedDescription)
            }
            isSaving = false
        }
    }

    private func parsePrice(_ string: String) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed).map(Double.init)
    }
}
