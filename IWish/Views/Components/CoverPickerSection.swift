import SwiftUI
import PhotosUI

/// Одна кнопка "Обложка" → меню (камера/галерея/эмодзи/убрать).
struct CoverPickerSection: View {
    @Binding var imageData: Data?
    @Binding var emoji: String?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var showingEmojiInput = false
    @State private var emojiDraft: String = ""

    private var hasSelection: Bool {
        imageData != nil || (emoji != nil && emoji?.isEmpty == false)
    }

    var body: some View {
        Section {
            HStack {
                // Preview thumbnail (if any)
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.title2)
                        .frame(width: 36, height: 36)
                }

                // Menu button
                Menu {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showingCamera = true } label: {
                            Label("Камера", systemImage: "camera")
                        }
                    }
                    Button { showingPhotoPicker = true } label: {
                        Label("Галерея", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        emojiDraft = emoji ?? ""
                        showingEmojiInput = true
                    } label: {
                        Label("Эмодзи", systemImage: "face.smiling")
                    }
                    if hasSelection {
                        Divider()
                        Button(role: .destructive) {
                            imageData = nil
                            emoji = nil
                        } label: {
                            Label("Убрать обложку", systemImage: "trash")
                        }
                    }
                } label: {
                    Label(hasSelection ? "Сменить обложку" : "Выбрать обложку",
                          systemImage: "photo")
                }
            }

            // Inline emoji input (only when active)
            if showingEmojiInput {
                HStack {
                    TextField("Введи эмодзи", text: $emojiDraft)
                        .onChange(of: emojiDraft) { _, newValue in
                            if let last = newValue.last, last.isEmoji {
                                emoji = String(last)
                                imageData = nil
                            }
                        }
                        .onSubmit { showingEmojiInput = false }
                    Button("Готово") { showingEmojiInput = false }
                        .font(.subheadline)
                }
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .images)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraImagePicker { image in
                if let compressed = ImageCompressor.compress(image) {
                    imageData = compressed
                    emoji = nil
                    showingEmojiInput = false
                }
            }
            .ignoresSafeArea(.all)
        }
        .onChange(of: selectedPhoto) { _, item in
            Task {
                guard let item else { return }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let compressed = ImageCompressor.compress(UIImage(data: data) ?? UIImage()) {
                    imageData = compressed
                    emoji = nil
                    showingEmojiInput = false
                }
            }
        }
    }
}

// MARK: - CameraImagePicker

struct CameraImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.overrideUserInterfaceStyle = .dark
        picker.modalPresentationStyle = .fullScreen
        picker.edgesForExtendedLayout = .all
        picker.extendedLayoutIncludesOpaqueBars = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onImageCaptured: onImageCaptured)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let dismiss: DismissAction
        let onImageCaptured: (UIImage) -> Void

        init(dismiss: DismissAction, onImageCaptured: @escaping (UIImage) -> Void) {
            self.dismiss = dismiss
            self.onImageCaptured = onImageCaptured
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - Character emoji check

private extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && scalar.value > 0x238C
    }
}
