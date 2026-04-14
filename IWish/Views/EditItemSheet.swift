import SwiftUI
import SwiftData
import LinkPresentation

struct EditItemSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Ссылка") {
                    TextField("URL", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                    Button("Сохранить") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { prefill() }
        }
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
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.descriptionText = descriptionText.isEmpty ? nil : descriptionText
        item.coverImageData = coverImageData
        item.coverEmoji = coverEmoji
        item.tier = tier
        item.price = Decimal(string: priceString)
        item.currency = currency
        item.url = urlString.isEmpty ? nil : urlString
        item.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
