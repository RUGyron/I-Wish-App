import SwiftUI
import SwiftData

struct AddWishlistSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var wishlists: [Wishlist]

    @State private var name: String = ""
    @State private var coverImageData: Data?
    @State private var coverEmoji: String?
    @State private var previewID = UUID()

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: На день рождения", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                CoverPickerSection(
                    imageData: $coverImageData,
                    emoji: $coverEmoji,
                    previewID: previewID
                )
            }
            .navigationTitle("Новый список")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }
                }
            }
        }
        .applyTheme()
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty
            ? "Список \(wishlists.count + 1)"
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
