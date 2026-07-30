import Foundation

/// Извлекает Product/Offer из <script type="application/ld+json">…</script>.
/// Покрывает Schema.org Product (Apple, Nike, Adidas, большинство e-commerce).
enum JsonLdExtractor {
    struct Result {
        let title: String?
        let imageURL: String?
        let price: Double?
        let currency: String?
    }

    static func extract(from html: String) -> Result? {
        guard let re = try? NSRegularExpression(
            pattern: "<script[^>]*type=[\"']application/ld\\+json[\"'][^>]*>([\\s\\S]*?)</script>",
            options: [.caseInsensitive]
        ) else { return nil }
        let nsHtml = html as NSString
        let matches = re.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
        for m in matches {
            let raw = nsHtml.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let data = raw.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let r = findProduct(in: obj) { return r }
        }
        return nil
    }

    private static func findProduct(in node: Any) -> Result? {
        if let arr = node as? [Any] {
            for item in arr {
                if let r = findProduct(in: item) { return r }
            }
            return nil
        }
        guard let dict = node as? [String: Any] else { return nil }
        // Иногда корень — { "@graph": [...] }.
        if let graph = dict["@graph"] {
            if let r = findProduct(in: graph) { return r }
        }
        let typeRaw = dict["@type"]
        let types: [String] = {
            if let s = typeRaw as? String { return [s] }
            if let a = typeRaw as? [String] { return a }
            return []
        }()
        let isProduct = types.contains { t in
            let lower = t.lowercased()
            return lower.hasSuffix("product") || lower.hasSuffix("individualproduct") || lower.hasSuffix("productgroup")
        }
        if isProduct {
            return normalizeProduct(dict)
        }
        return nil
    }

    private static func normalizeProduct(_ p: [String: Any]) -> Result? {
        let title = pickString(p["name"]) ?? pickString(p["title"])
        var imageURL = pickImage(p["image"])
        if imageURL == nil {
            if let offers = p["offers"] as? [String: Any],
               let itemOffered = offers["itemOffered"] as? [String: Any] {
                imageURL = pickImage(itemOffered["image"])
            }
        }
        let (price, currency) = pickPrice(p["offers"])

        let r = Result(title: title, imageURL: imageURL, price: price, currency: currency)
        if r.title == nil && r.imageURL == nil && r.price == nil { return nil }
        return r
    }

    private static func pickString(_ v: Any?) -> String? {
        if let s = v as? String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        if let arr = v as? [Any], let first = arr.first { return pickString(first) }
        if let d = v as? [String: Any], let val = d["@value"] as? String { return val.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }

    private static func pickImage(_ v: Any?) -> String? {
        if let s = v as? String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        if let arr = v as? [Any], let first = arr.first { return pickImage(first) }
        if let d = v as? [String: Any] {
            if let url = d["url"] as? String { return url }
            if let url = d["contentUrl"] as? String { return url }
        }
        return nil
    }

    private static func pickPrice(_ offersRaw: Any?) -> (Double?, String?) {
        guard let offersRaw else { return (nil, nil) }
        let offers: [[String: Any]] = {
            if let arr = offersRaw as? [[String: Any]] { return arr }
            if let one = offersRaw as? [String: Any] { return [one] }
            return []
        }()
        for off in offers {
            let priceRaw = off["price"] ?? off["lowPrice"]
                ?? (off["priceSpecification"] as? [String: Any])?["price"]
            let currencyRaw = off["priceCurrency"]
                ?? (off["priceSpecification"] as? [String: Any])?["priceCurrency"]
            if let p = parsePriceNumber(priceRaw) {
                let curr = (currencyRaw as? String)?.trimmed.uppercased()
                return (p, curr)
            }
        }
        return (nil, nil)
    }
}
