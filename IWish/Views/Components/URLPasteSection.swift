import SwiftUI
import UIKit

/// Универсальная секция вставки/отображения URL для AddItemSheet / EditItemSheet.
/// - Если URL ещё нет: одна кнопка «Вставить ссылку».
/// - Если URL установлен: caption (host / title из метаданных) + raw URL мелким шрифтом,
///   рядом — кнопка «Обновить» (повторно paste из буфера) и кнопка очистки.
struct URLPasteSection: View {
    @Binding var urlString: String
    /// Опциональный caption — title из мета (или ранее извлечённый); если nil — host из URL.
    @Binding var fetchedTitle: String?
    /// Callback при успешной вставке URL — должен запустить fetchMetadata + autofill name/cover.
    let onPasted: (URL) -> Void
    /// Indicator metadata fetch'а в процессе.
    let isFetching: Bool

    @State private var noURLFlash = false

    var body: some View {
        Section("Ссылка") {
            if urlString.isEmpty {
                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Вставить ссылку", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())

                if noURLFlash {
                    Text("Нет ссылки в буфере")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(captionText)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(urlString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)

                        if isFetching {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                pasteFromClipboard()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Обновить ссылку")
                        }

                        Button {
                            urlString = ""
                            fetchedTitle = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Удалить ссылку")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Logic

    private var captionText: String {
        if let title = fetchedTitle?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            return title
        }
        // Fallback на host из URL — это всегда более читаемо чем raw URL.
        if let url = URL(string: urlString), let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return urlString
    }

    private func pasteFromClipboard() {
        guard let clipboard = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboard.isEmpty,
              let url = URL(string: clipboard),
              url.scheme != nil else {
            noURLFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                noURLFlash = false
            }
            return
        }
        urlString = clipboard
        fetchedTitle = nil // сброс — новая метадата подтянется через onPasted
        noURLFlash = false
        onPasted(url)
    }
}
