import SwiftUI
import SwiftData

struct EditWishlistSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @Environment(\.toast) private var toast

    let wishlist: Wishlist

    @State private var name: String = ""
    @State private var coverImageData: Data?
    @State private var coverEmoji: String?
    @State private var isSaving = false

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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                name = wishlist.name
                coverImageData = wishlist.coverImageData
                coverEmoji = wishlist.coverEmoji
            }
        }
        .loadingOverlay(isSaving)
        .applyTheme()
    }

    private func save() {
        guard !isSaving else { return }

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        Task {
            do {
                try await services.data.updateWishlist(id: wishlist.id.uuidString, name: trimmed, emoji: coverEmoji)
                // Apply cover image locally (not stored in Firestore)
                wishlist.coverImageData = coverImageData
                try? context.save()
                dismiss()
            } catch {
                toast.error(error.localizedDescription)
            }
            isSaving = false
        }
    }
}
