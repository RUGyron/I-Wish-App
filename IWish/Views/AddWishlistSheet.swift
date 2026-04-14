import SwiftUI
import SwiftData

struct AddWishlistSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: На день рождения", text: $name)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .navigationTitle("Новый список")
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
        let wishlist = Wishlist(name: name.trimmingCharacters(in: .whitespaces))
        context.insert(wishlist)
        try? context.save()
        dismiss()
    }
}

#Preview {
    AddWishlistSheet()
        .modelContainer(for: [Wishlist.self, Item.self, AppSettings.self], inMemory: true)
}
