import UIKit

/// Fetches og:title and og:image from a URL via direct HTTP request.
/// Uses a mobile User-Agent so works with Russian marketplaces (Ozon, Wildberries)
/// that block LPMetadataProvider's default UA. Follows redirects automatically.
struct URLMetadataService {
    struct PageMetadata {
        var title: String?
        var image: UIImage?
    }

    static func fetch(from url: URL) async -> PageMetadata {
        guard let html = await fetchHTML(from: url) else { return PageMetadata() }

        let title = ogContent(html, property: "og:title") ?? htmlTitle(html)
        var image: UIImage?

        if let imageStr = ogContent(html, property: "og:image"),
           let imageURL = resolveURL(imageStr, base: url),
           let (imgData, _) = try? await URLSession.shared.data(from: imageURL) {
            image = UIImage(data: imgData)
        }

        return PageMetadata(
            title: title.map { $0.htmlDecoded.trimmed },
            image: image
        )
    }

    // MARK: - Private

    /// Hard cap на размер HTML — защита от memory-attack (адверсарный сайт может
    /// слать гигабайты в HTTP body). Метаданных нет нужды искать в больше чем 2МБ:
    /// og:title/og:image обычно в первых 200КБ <head>.
    private static let maxHTMLBytes = 2 * 1024 * 1024

    private static func fetchHTML(from url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("ru-RU,ru;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return nil
        }
        // Truncate если ответ слишком большой — парсить хвост не нужно.
        let bounded = data.count > maxHTMLBytes ? data.prefix(maxHTMLBytes) : data
        let boundedData = Data(bounded)
        return String(data: boundedData, encoding: .utf8)
            ?? String(data: boundedData, encoding: .windowsCP1251)
    }

    /// Extracts content= from <meta property="X" content="Y"> or <meta content="Y" property="X">
    private static func ogContent(_ html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            // property before content
            "(?i)<meta[^>]+property=[\"']?\(escaped)[\"'][^>]+content=[\"']([^\"'<>\\n]+)[\"']",
            // content before property
            "(?i)<meta[^>]+content=[\"']([^\"'<>\\n]+)[\"'][^>]+property=[\"']?\(escaped)[\"']"
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let r = Range(m.range(at: 1), in: html) else { continue }
            let val = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !val.isEmpty { return val }
        }
        return nil
    }

    private static func htmlTitle(_ html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "(?i)<title[^>]*>([^<]+)</title>"),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveURL(_ str: String, base: URL) -> URL? {
        if str.hasPrefix("//") { return URL(string: "https:" + str) }
        if str.hasPrefix("http") { return URL(string: str) }
        return URL(string: str, relativeTo: base)?.absoluteURL
    }
}

// MARK: - String helpers

private extension String {
    var htmlDecoded: String {
        var s = self
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")
        ]
        for (k, v) in named { s = s.replacingOccurrences(of: k, with: v) }
        // Numeric entities: &#1050; or &#x41B;
        if let re = try? NSRegularExpression(pattern: "&#(?:x([0-9a-fA-F]+)|(\\d+));") {
            for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                guard let r = Range(m.range, in: s) else { continue }
                let code: Int?
                if let hex = Range(m.range(at: 1), in: s), !s[hex].isEmpty {
                    code = Int(s[hex], radix: 16)
                } else if let dec = Range(m.range(at: 2), in: s) {
                    code = Int(s[dec])
                } else { code = nil }
                if let c = code, let scalar = Unicode.Scalar(c) {
                    s.replaceSubrange(r, with: String(Character(scalar)))
                }
            }
        }
        return s
    }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
