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
    @State private var notificationsEnabled: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("List name", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                CoverPickerSection(imageData: $coverImageData, emoji: $coverEmoji)

                if coverImageData == nil {
                    Section("Cover color") {
                        GradientHuePicker(hue: $gradientHue)
                            .padding(.vertical, 8)
                    }
                }

                Section {
                    Toggle("Change notifications", isOn: $notificationsEnabled)
                } footer: {
                    Text("Receive push when wishes are added/edited/removed in this list. Works only when notifications are enabled in Settings.")
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
            .navigationTitle("Edit list")
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
            .onAppear {
                name = wishlist.name
                coverImageData = wishlist.coverImageData
                coverEmoji = wishlist.coverEmoji
                gradientHue = wishlist.gradientHue ?? Double.random(in: 0...1)
                notificationsEnabled = wishlist.notificationsEnabled
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
        let toggleValue = notificationsEnabled
        Task {
            do {
                let hueToSave: Double? = coverImageData == nil ? gradientHue : nil
                try await services.data.updateWishlist(id: wishlist.id.uuidString, name: trimmed, emoji: coverEmoji, coverImageData: coverImageData, gradientHue: hueToSave)
                // notificationsEnabled: локальный кеш + (для shared) доводим до membership в Firestore,
                // чтобы Cloud Function не слала пуши этому юзеру, если он выключил уведомления списка.
                wishlist.notificationsEnabled = toggleValue
                try? wishlist.modelContext?.save()
                if wishlist.isShared, let sid = wishlist.sharedWishlistID, let myUID = services.auth.uid {
                    try? await services.firestore.updateMembershipNotificationsEnabled(wishlistID: sid, userUID: myUID, enabled: toggleValue)
                }
                dismiss()
            } catch {
                toast.error(error.localizedDescription)
            }
            isSaving = false
        }
    }
}
