import SwiftUI
import PhotosUI

/// Секция для выбора обложки: галерея, эмодзи, или mesh-дефолт.
/// Reusable — используется и в AddWishlistSheet, и в AddItemSheet.
struct CoverPickerSection: View {
    @Binding var imageData: Data?
    @Binding var emoji: String?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingEmojiInput = false
    @State private var emojiDraft: String = ""

    /// UUID для MeshGradient fallback preview.
    let previewID: UUID

    var body: some View {
        Section("Обложка") {
            HStack(spacing: 12) {
                coverPreview
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    coverStatusText
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Галерея", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        emojiDraft = emoji ?? ""
                        showingEmojiInput = true
                    } label: {
                        Label("Эмодзи", systemImage: "face.smiling")
                    }
                    if imageData != nil || emoji != nil {
                        Divider()
                        Button("Авто (mesh)", systemImage: "paintbrush") {
                            imageData = nil
                            emoji = nil
                        }
                    }
                } label: {
                    Text("Выбрать")
                        .font(.subheadline)
                }
            }

            if showingEmojiInput {
                HStack {
                    TextField("Введи эмодзи", text: $emojiDraft)
                        .onChange(of: emojiDraft) { _, newValue in
                            // Оставляем только последний символ-эмодзи
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

    @ViewBuilder
    private var coverPreview: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            DefaultCoverView(
                id: previewID,
                imageData: nil,
                emoji: emoji
            )
        }
    }

    private var coverStatusText: Text {
        if imageData != nil {
            Text("Фото выбрано")
        } else if let emoji, !emoji.isEmpty {
            Text("Эмодзи: \(emoji)")
        } else {
            Text("Автоматическая")
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
