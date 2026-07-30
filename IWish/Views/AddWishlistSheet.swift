import SwiftUI
import SwiftData

struct AddWishlistSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @Query private var wishlists: [Wishlist]

    @State private var name: String = ""
    @State private var coverImageData: Data?
    @State private var coverEmoji: String?
    @State private var gradientHue: Double = Double.random(in: 0...1)
    @State private var errorMessage: String?
    @State private var isSaving = false
    @Query private var settingsList: [AppSettings]
    private var appSettings: AppSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Birthday", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .onChange(of: name) { _, newValue in
                            name = InputLimits.truncate(newValue, to: InputLimits.wishlistName)
                        }
                }

                CoverPickerSection(
                    imageData: $coverImageData,
                    emoji: $coverEmoji
                )

                if coverImageData == nil {
                    Section("Cover color") {
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
            .navigationTitle("New list")
            .fontDesign(.rounded)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(isSaving)
                }
            }
        }
        .loadingOverlay(isSaving)
        .alert("Couldn’t create", isPresented: .constant(errorMessage != nil)) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .applyTheme()
    }

    private func generateName() -> String {
        let used = Set(wishlists.map(\.name))
        // Берём культурно-релевантный набор для текущей локали (см. AutoListNames).
        let localized = AutoListNames.current()
        let available = localized.filter { !used.contains($0) }
        return available.randomElement() ?? String(format: String(localized: "List %lld"), wishlists.count + 1)
    }

    private func save() {
        guard !isSaving else { return }

        let emptyCount = wishlists.filter { ($0.items ?? []).isEmpty }.count
        guard emptyCount < InputLimits.maxEmptyWishlists else {
            errorMessage = String(localized: "You have too many empty lists. Delete or fill them first.")
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty
            ? generateName()
            : trimmed

        isSaving = true
        let pushDefault = appSettings?.newWishlistNotificationsDefault ?? true
        Task {
            do {
                // gradientHue только если нет фото (фото — главная обложка).
                let hueToSave: Double? = coverImageData == nil ? gradientHue : nil
                let wishlist = try await services.data.createWishlist(name: finalName, emoji: coverEmoji, gradientHue: hueToSave)
                if let coverImageData {
                    wishlist.coverImageData = coverImageData
                }
                // Применяем default уведомлений для нового списка из глобальных настроек.
                wishlist.notificationsEnabled = pushDefault
                try? context.save()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    AddWishlistSheet()
        .modelContainer(for: [Wishlist.self, Item.self, AppSettings.self], inMemory: true)
}
