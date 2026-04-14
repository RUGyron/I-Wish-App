import SwiftUI
import PhotosUI

/// Секция для выбора обложки: камера, галерея, эмодзи.
/// Reusable — используется и в AddWishlistSheet, и в AddItemSheet.
struct CoverPickerSection: View {
    @Binding var imageData: Data?
    @Binding var emoji: String?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var showingEmojiInput = false
    @State private var emojiDraft: String = ""

    var body: some View {
        Section("Обложка") {
            // Current selection preview + remove
            if let imageData, let image = UIImage(data: imageData) {
                HStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Spacer()

                    Button("Убрать", role: .destructive) {
                        self.imageData = nil
                    }
                    .font(.subheadline)
                }
            } else if let emoji, !emoji.isEmpty {
                HStack(spacing: 12) {
                    Text(emoji)
                        .font(.largeTitle)

                    Spacer()

                    Button("Убрать", role: .destructive) {
                        self.emoji = nil
                    }
                    .font(.subheadline)
                }
            }

            // Camera
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Камера", systemImage: "camera")
                }
            }

            // Gallery
            Button {
                showingPhotoPicker = true
            } label: {
                Label("Галерея", systemImage: "photo.on.rectangle")
            }

            // Emoji
            Button {
                emojiDraft = emoji ?? ""
                showingEmojiInput.toggle()
            } label: {
                Label("Эмодзи", systemImage: "face.smiling")
            }

            // Inline emoji input
            if showingEmojiInput {
                HStack {
                    TextField("Введи эмодзи", text: $emojiDraft)
                        .onChange(of: emojiDraft) { _, newValue in
                            if let last = newValue.last, last.isEmoji {
                                emoji = String(last)
                                imageData = nil
                            }
                        }
                        .onSubmit {
                            showingEmojiInput = false
                        }
                    Button("Готово") {
                        showingEmojiInput = false
                    }
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
        }
        .onChange(of: selectedPhoto) { _, item in
            Task {
                guard let item else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    if let compressed = ImageCompressor.compress(UIImage(data: data) ?? UIImage()) {
                        imageData = compressed
                        emoji = nil
                        showingEmojiInput = false
                    }
                }
            }
        }
    }
}

// MARK: - CameraImagePicker (UIImagePickerController wrapper)

struct CameraImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
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
