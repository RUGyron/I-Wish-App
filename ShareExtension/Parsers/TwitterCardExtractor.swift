import Foundation

/// Twitter Card. Многие сайты дублируют OG ↔ twitter:* — этот extractor fallback для случаев когда OG пуст.
enum TwitterCardExtractor {
    struct Result {
        let title: String?
        let imageURL: String?
    }

    static func extract(from html: String) -> Result? {
        let meta = OpenGraphExtractor.parseMetaTags(html: html)
        let title = meta["twitter:title"]
        let imageURL = meta["twitter:image"] ?? meta["twitter:image:src"]
        if title == nil && imageURL == nil { return nil }
        return Result(title: title?.trimmed, imageURL: imageURL?.trimmed)
    }
}
