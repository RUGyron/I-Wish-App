import SwiftUI
import SwiftData

struct AddWishlistSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var wishlists: [Wishlist]

    @State private var name: String = ""
    @State private var coverImageData: Data?
    @State private var coverEmoji: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: На день рождения", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .onChange(of: name) { _, newValue in
                            name = InputLimits.truncate(newValue, to: InputLimits.wishlistName)
                        }
                }

                CoverPickerSection(
                    imageData: $coverImageData,
                    emoji: $coverEmoji
                )
            }
            .warmBackground()
            .navigationTitle("Новый список")
            .fontDesign(.rounded)
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
                }
            }
        }
        .alert("Не удалось создать", isPresented: .constant(errorMessage != nil)) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .applyTheme()
    }

    private static let autoNames = [
        "Мечты на завтра",
        "Список вдохновения",
        "Хотелки",
        "Коллекция желаний",
        "Мои находки",
        "Список идей",
        "Избранное",
        "Заветные мечты",
        "На заметку",
        "Просто хочу",
        "Для души",
        "Собираю на мечту",
        "Приглянулось",
        "Буду копить",
        "Поймал момент",
    ]

    private func generateName() -> String {
        let used = Set(wishlists.map(\.name))
        let available = Self.autoNames.filter { !used.contains($0) }
        return available.randomElement() ?? "Список \(wishlists.count + 1)"
    }

    private func save() {
        let emptyCount = wishlists.filter { ($0.items ?? []).isEmpty }.count
        guard emptyCount < InputLimits.maxEmptyWishlists else {
            errorMessage = "У вас слишком много пустых списков. Сначала удалите или заполните их."
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty
            ? generateName()
            : trimmed

        let wishlist = Wishlist(
            name: finalName,
            coverImageData: coverImageData,
            coverEmoji: coverEmoji
        )
        context.insert(wishlist)
        try? context.save()
        dismiss()
    }
}

#Preview {
    AddWishlistSheet()
        .modelContainer(for: [Wishlist.self, Item.self, AppSettings.self], inMemory: true)
}
