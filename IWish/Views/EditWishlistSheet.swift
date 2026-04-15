import SwiftUI
import SwiftData

struct EditWishlistSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let wishlist: Wishlist

    @State private var name: String = ""
    @State private var coverImageData: Data?
    @State private var coverEmoji: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Название списка", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                CoverPickerSection(imageData: $coverImageData, emoji: $coverEmoji)
            }
            .warmBackground()
            .navigationTitle("Изменить список")
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
            .onAppear {
                name = wishlist.name
                coverImageData = wishlist.coverImageData
                coverEmoji = wishlist.coverEmoji
            }
        }
        .applyTheme()
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        wishlist.name = trimmed
        wishlist.coverImageData = coverImageData
        wishlist.coverEmoji = coverEmoji
        wishlist.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
