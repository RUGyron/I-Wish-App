import Foundation

/// OpenGraph + product Open Graph extensions.
/// https://ogp.me/ + https://ogp.me/#type_product
enum OpenGraphExtractor {
    struct Result {
        let title: String?
        let imageURL: String?
        let price: Double?
        let currency: String?
    }

    static func extract(from html: String) -> Result? {
        let meta = parseMetaTags(html: html)

        let title = meta["og:title"]
        let imageURL = meta["og:image"] ?? meta["og:image:url"] ?? meta["og:image:secure_url"]
        let priceRaw: String? = meta["product:price:amount"]
            ?? meta["og:price:amount"]
            ?? meta["twitter:data1"]
        let currency = meta["product:price:currency"]
            ?? meta["og:price:currency"]

        let price = parsePriceNumber(priceRaw as Any?)

        let r = Result(
            title: title?.trimmed,
            imageURL: imageURL?.trimmed,
            price: price,
            currency: currency?.trimmed.uppercased()
        )
        if r.title == nil && r.imageURL == nil && r.price == nil { return nil }
        return r
    }

    /// Парсит все <meta property/name="..." content="..."> в dict. Поддерживает обратный порядок аттрибутов.
    static func parseMetaTags(html: String) -> [String: String] {
        var meta: [String: String] = [:]
        let nsHtml = html as NSString

        let patterns = [
            // property/name → content
            "<meta\\s+[^>]*?(?:property|name)=[\"']([^\"']+)[\"']\\s+[^>]*?content=[\"']([^\"']*)[\"']",
            // content → property/name
            "<meta\\s+[^>]*?content=[\"']([^\"']*)[\"']\\s+[^>]*?(?:property|name)=[\"']([^\"']+)[\"']"
        ]

        for (i, pattern) in patterns.enumerated() {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = re.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for m in matches {
                let keyGroup = i == 0 ? 1 : 2
                let valGroup = i == 0 ? 2 : 1
                let key = nsHtml.substring(with: m.range(at: keyGroup)).lowercased().trimmed
                let val = nsHtml.substring(with: m.range(at: valGroup))
                if meta[key] == nil { meta[key] = val }
            }
        }
        return meta
    }
}
