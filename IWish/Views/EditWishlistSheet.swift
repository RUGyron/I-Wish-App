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
    @State private var gradientHue: Double = 0.5
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Название списка", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                CoverPickerSection(imageData: $coverImageData, emoji: $coverEmoji)

                if coverImageData == nil {
                    Section("Цвет обложки") {
                        GradientHuePicker(hue: $gradientHue)
                            .padding(.vertical, 8)
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
            .navigationTitle("Изменить список")
            .navigationBarTitleDisplayMode(.inline)
            .fontDesign(.rounded)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
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
                gradientHue = wishlist.gradientHue ?? Double.random(in: 0...1)
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
                let hueToSave: Double? = coverImageData == nil ? gradientHue : nil
                try await services.data.updateWishlist(id: wishlist.id.uuidString, name: trimmed, emoji: coverEmoji, coverImageData: coverImageData, gradientHue: hueToSave)
                dismiss()
            } catch {
                toast.error(error.localizedDescription)
            }
            isSaving = false
        }
    }
}
