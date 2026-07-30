import Foundation

/// Последний fallback: <title>...</title>. Используется когда ни OG/JSON-LD/Twitter не нашлось.
/// Опасно: для antibot-страниц может вернуть имя сайта ("Яндекс Маркет") вместо товара.
/// Caller должен с осторожностью использовать.
enum TitleTagExtractor {
    static func extract(from html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "<title[^>]*>([\\s\\S]*?)</title>", options: [.caseInsensitive]),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        let raw = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }
}
