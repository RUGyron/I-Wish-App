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
    @State private var priceString: String = ""
    @State private var currency: String = "RUB"
    @State private var urlString: String = ""
    @State private var probationEnabled: Bool = false
    @State private var probationDays: Int = 30
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Ссылка") {
                    TextField("URL", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Название") {
                    TextField("Чего хочется?", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                CoverPickerSection(imageData: $coverImageData, emoji: $coverEmoji)

                Section("Важность") {
                    VStack(spacing: 8) {
                        Picker("Важность", selection: $tier) {
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

                Section("Описание") {
                    TextField("Опционально", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .warmBackground()
            .navigationTitle("Изменить")
            .navigationBarTitleDisplayMode(.inline)
            .fontDesign(.rounded)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
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
        priceString = item.price.map { "\($0)" } ?? ""
        currency = item.currency
        urlString = item.url ?? ""
        probationEnabled = item.probationEndAt != nil
        if let end = item.probationEndAt {
            let days = Calendar.current.dateComponents([.day], from: .now, to: end).day ?? 30
            probationDays = max(1, days)
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
                try await services.data.updateItem(
                    id: item.id.uuidString,
                    wishlistID: wishlistID,
                    name: name.trimmingCharacters(in: .whitespaces),
                    tier: tier,
                    price: Double(priceString),
                    currency: currency,
                    url: urlString.isEmpty ? nil : urlString,
                    emoji: coverEmoji,
                    sortIndex: item.sortIndex,
                    isArchived: item.isArchived,
                    descriptionText: descriptionText.isEmpty ? nil : descriptionText,
                    coverImageData: coverImageData,
                    probationEndAt: probEnd
                )
                dismiss()
            } catch {
                toast.error(error.localizedDescription)
            }
            isSaving = false
        }
    }
}
