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
        Section("Link") {
            if urlString.isEmpty {
                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Paste link", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())

                if noURLFlash {
                    Text("No link in clipboard")
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
                                Image(systemName: "doc.on.clipboard.fill")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Paste new link")
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
                        .accessibilityLabel("Remove link")
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
        let clipboardRaw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clipboardRaw.isEmpty,
              let url = Self.extractFirstURL(from: clipboardRaw) else {
            noURLFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                noURLFlash = false
            }
            return
        }
        urlString = url.absoluteString
        fetchedTitle = nil // сброс — новая метадата подтянется через onPasted
        noURLFlash = false
        onPasted(url)
    }

    /// Smart URL extraction: ищет первую валидную http(s) ссылку внутри текста.
    /// WB / Ozon / Я.Маркет "Поделиться" обычно даёт что-то вроде:
    ///   "🔥 Apple iPhone 16 Pro по супер цене! https://www.wildberries.ru/catalog/260535421/detail.aspx"
    /// или Telegram-форвард с emoji + ссылка. Чистый URL.parse такое не возьмёт.
    /// Стратегия:
    ///   1. NSDataDetector(types: .link) — native iOS детектор URL в произвольном тексте.
    ///   2. Если в тексте несколько ссылок — берём первую http/https.
    ///   3. Fallback: если в тексте только URL без префикса — стандартный URL(string:).
    static func extractFirstURL(from text: String) -> URL? {
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = detector.matches(in: text, range: range)
            for m in matches {
                if let url = m.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    return url
                }
            }
        }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return url
        }
        return nil
    }
}
