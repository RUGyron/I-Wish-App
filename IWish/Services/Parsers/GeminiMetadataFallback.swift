import Foundation
import FirebaseAI
import os.log

/// Универсальный fallback на Gemini 2.5 Flash-Lite (Firebase AI Logic, Gemini Developer API backend).
///
/// Используется когда:
/// - HTTP fetch вернул HTML но extractors (JSON-LD/OG/Twitter) ничего не нашли
/// - WKWebView fallback тоже не дал результата
/// - У нас есть какой-то HTML товара (не antibot заглушка)
///
/// Gemini получает усечённый HTML (10КБ head + 30КБ body relevant section) + URL и возвращает
/// структурированный JSON `{title, imageURL, price, currency}`.
///
/// **Spark plan compatible**: Gemini Developer API через Firebase AI Logic — 1500 RPD / 30 RPM / 1M TPM free.
/// **App Store rating требование**: 17+ (free Gemini ToS), Vlad confirmed OK.
enum GeminiMetadataFallback {
    struct Result {
        let title: String?
        let imageURL: String?
        let price: Double?
        let currency: String?
    }

    /// Refined метаданные после Gemini-обработки. Может дополнить description и нормализовать
    /// title/price/currency. Все поля nullable — Gemini может вернуть nil для очевидного шума.
    struct RefinedResult {
        let title: String?
        let imageURL: String?
        let price: Double?
        let currency: String?
        let descriptionText: String?
    }

    private static let log = Logger(subsystem: "RUGyron.IWish", category: "GeminiFallback")

    /// Lazy-init модели (создаётся при первом использовании).
    private static let model: GenerativeModel = {
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let schema = Schema.object(properties: [
            "title": .string(nullable: true),
            "imageURL": .string(nullable: true),
            "price": .double(nullable: true),
            "currency": .string(description: "ISO 4217 like RUB / USD / EUR. nil if no price.", nullable: true)
        ])
        let config = GenerationConfig(
            temperature: 0.1,
            responseMIMEType: "application/json",
            responseSchema: schema
        )
        return ai.generativeModel(modelName: "gemini-2.5-flash-lite", generationConfig: config)
    }()

    /// Расширенный schema для refine endpoint — включает description.
    /// Schema descriptions language-neutral; язык вывода задаётся в prompt через `targetLanguage` параметр.
    private static let refineModel: GenerativeModel = {
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let schema = Schema.object(properties: [
            "title": .string(description: "Clean human-readable product name in the user's language (no 'Buy', no SEO tails, no size/color suffixes if they're options).", nullable: true),
            "imageURL": .string(nullable: true),
            "price": .double(description: "Final purchase price after discounts (for Wildberries — WB Wallet price; for Ozon — Ozon Card price).", nullable: true),
            "currency": .string(description: "ISO 4217: RUB / USD / EUR / ...", nullable: true),
            "description": .string(description: "Short (up to 200 chars) product description in the user's language, only from HTML. No marketing fluff.", nullable: true)
        ])
        let config = GenerationConfig(
            temperature: 0.1,
            responseMIMEType: "application/json",
            responseSchema: schema
        )
        return ai.generativeModel(modelName: "gemini-2.5-flash-lite", generationConfig: config)
    }()

    /// BCP47 → human language name для prompt'ов. Gemini лучше понимает английские имена языков.
    private static func languageName(_ code: String) -> String {
        switch code {
        case "ru": return "Russian (Cyrillic)"
        case "en": return "English"
        case "es": return "Spanish"
        case "de": return "German"
        case "fr": return "French"
        case "it": return "Italian"
        case "ja": return "Japanese"
        case "zh-Hans": return "Simplified Chinese"
        case "ko": return "Korean"
        case "pt-BR": return "Brazilian Portuguese"
        default: return "English"
        }
    }

    /// Refine after successful extract. Cleans up title/price/currency, adds description.
    /// На фейле или rate-limit возвращает nil — caller использует originalMeta.
    ///
    /// `targetLanguage` — BCP47 код (`ru`, `en`, `es`, `de` и т.д.). По умолчанию язык юзера.
    /// title и description возвращаются в этом языке (с учётом исходного — если HTML на другом
    /// языке, Gemini сам переводит/адаптирует).
    static func refine(
        html: String?,
        url: URL,
        title: String?,
        imageURL: String?,
        price: Double?,
        currency: String?,
        targetLanguage: String = CurrentLocale.identifier()
    ) async -> RefinedResult? {
        let snippet: String
        if let html, html.count > 1000 {
            snippet = compactHTML(html)
        } else {
            snippet = "(no HTML available — refine only existing fields)"
        }
        let langName = languageName(targetLanguage)
        let prompt = """
        Refine product metadata from this page. Return strict JSON matching the schema.

        OUTPUT LANGUAGE: \(langName). All text fields (title, description) MUST be in \(langName).
        If the HTML is in a different language, translate/adapt naturally for a \(langName)-speaking user.

        URL: \(url.absoluteString)
        Existing fields (may contain noise / SEO tails — feel free to overwrite):
          title:    \(title ?? "(empty)")
          image:    \(imageURL ?? "(empty)")
          price:    \(price.map { String($0) } ?? "(empty)")
          currency: \(currency ?? "(empty)")

        CRITICAL RULES:
        1. If HTML contains antibot challenge ('Antibot Challenge Page', 'Just a moment', 'Checking your browser', 'Почти готово...', captcha, Cloudflare challenge) → return null for ALL fields. Do NOT guess the product.
        2. If HTML is a marketplace homepage / category page (NOT a specific product) → return null for everything except existing fields that are clearly about this product.
        3. Description: use ONLY information from HTML. If HTML has no description — null. NEVER invent features from general knowledge.
        4. If HTML is absent / nil → refine only existing fields, description=null.

        Title — rewrite into a **human wishlist-style name** (as a user would write it themselves):
        - Marketplace API raw formats like 'Brand. Category for X' (e.g. 'Baseus. Чехол для Apple iPhone 16 Pro' or 'Apple Смартфон iPhone 16 Pro 128 GB Desert Titanium') — these are raw API output, ALWAYS rewrite.
        - Natural structure: '[Category] [Brand] [Model/Spec]'. If brand is implicit in the model (iPhone, MacBook, AirPods) — brand can be dropped.
        - Strip SEO noise: 'Buy', 'in online store', 'best price', '- best price', trailing size/color options if they're slash-separated tails.
        - Keep real specs (memory, color, size) if they're part of the product name.
        - Output title in \(langName).

        Examples (Russian source → Russian output; for other languages adapt analogously):
        - 'Baseus. Чехол для Apple iPhone 16 Pro' → 'Чехол Baseus для iPhone 16 Pro'
        - 'Apple Смартфон iPhone 16 Pro 128 GB Desert Titanium' → 'iPhone 16 Pro 128 GB Desert Titanium'
        - 'Studioakd. Пуфик для туалетного столика и прихожей' → 'Пуфик для туалетного столика Studioakd'
        - 'Buy Apple iPhone 16 Pro 128GB Natural Titanium - best price' → 'iPhone 16 Pro 128GB Natural Titanium'

        Other fields:
        - imageURL: prefer higher-quality from JSON-LD / og:image:secure_url. Otherwise keep original.
        - price: final price after discounts (WB Wallet / Ozon Card). No decimals if round. No currency symbols.
        - currency: ISO 4217.
        - description: up to 200 chars, only quote/condense from HTML, in \(langName). No fluff. null if HTML has none.

        HTML (truncated):
        \(snippet)
        """

        do {
            let response = try await refineModel.generateContent(prompt)
            guard let text = response.text else { return nil }
            guard let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log.warning("Gemini refine returned non-JSON: \(text.prefix(200), privacy: .public)")
                return nil
            }
            let rTitle = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rImage = (obj["imageURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rPrice = parsePriceNumber(obj["price"])
            let rCurrency = (obj["currency"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let rDesc = (obj["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            return RefinedResult(
                title: (rTitle?.isEmpty == false) ? rTitle : nil,
                imageURL: (rImage?.isEmpty == false) ? rImage : nil,
                price: rPrice,
                currency: (rCurrency?.isEmpty == false) ? rCurrency : nil,
                descriptionText: (rDesc?.isEmpty == false) ? rDesc : nil
            )
        } catch {
            log.warning("Gemini refine failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func extract(html: String, url: URL, targetLanguage: String = CurrentLocale.identifier()) async -> Result? {
        let trimmedHTML = compactHTML(html)
        let langName = languageName(targetLanguage)
        let prompt = """
        Extract product metadata from this HTML page. Return strict JSON matching the schema.

        OUTPUT LANGUAGE: \(langName). The `title` field MUST be in \(langName) — translate/adapt if source HTML is in another language.

        URL: \(url.absoluteString)

        Rules:
        - title: product name as a human would read it, in \(langName). Brand prefix OK (e.g. "Apple iPhone 16 Pro 128GB").
          If page is NOT a product page (homepage / search / error / antibot challenge) — return null for all fields.
        - imageURL: absolute URL of the main product image. Prefer high-resolution, prefer og:image / JSON-LD over thumbnails.
        - price: numeric value WITHOUT currency symbol. Prefer final price (after discounts). For Russian marketplaces
          like Wildberries / Ozon — prefer "WB Wallet price" / "Ozon Card price" if shown. No thousands separators in output.
        - currency: ISO 4217 code only (RUB / USD / EUR / ...). Detect from page context (₽ → RUB, $ → USD, € → EUR).

        HTML (truncated):
        \(trimmedHTML)
        """

        do {
            let response = try await model.generateContent(prompt)
            guard let text = response.text else { return nil }
            guard let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log.warning("Gemini returned non-JSON: \(text.prefix(200), privacy: .public)")
                return nil
            }
            let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let imageURL = (obj["imageURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let price = parsePriceNumber(obj["price"])
            let currency = (obj["currency"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

            if (title?.isEmpty ?? true) && (imageURL?.isEmpty ?? true) && price == nil { return nil }
            return Result(
                title: (title?.isEmpty == false) ? title : nil,
                imageURL: (imageURL?.isEmpty == false) ? imageURL : nil,
                price: price,
                currency: (currency?.isEmpty == false) ? currency : nil
            )
        } catch {
            log.error("Gemini call failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Усечь HTML до релевантных частей. Цель — уложиться в ~40KB чтобы не сжечь TPM.
    /// Стратегия:
    /// 1. <head> целиком (там og/jsonld/twitter — самое полезное).
    /// 2. Из <body> вырезать <script>, <style>, <svg>, <noscript>.
    /// 3. Усечь body до первых 30KB после head.
    private static func compactHTML(_ html: String) -> String {
        let headEnd = html.range(of: "</head>", options: .caseInsensitive)?.upperBound ?? html.startIndex
        let head = String(html[..<headEnd]).prefix(15_000)

        let bodyStart = html.range(of: "<body", options: .caseInsensitive)?.lowerBound ?? headEnd
        let body = String(html[bodyStart...])
        // Убрать тяжёлые мусорные блоки.
        var compactBody = body
        for pattern in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>", "<svg[\\s\\S]*?</svg>", "<noscript[\\s\\S]*?</noscript>"] {
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                compactBody = re.stringByReplacingMatches(
                    in: compactBody,
                    range: NSRange(compactBody.startIndex..., in: compactBody),
                    withTemplate: ""
                )
            }
        }
        let bodyTrimmed = compactBody.prefix(30_000)
        return head + "\n" + bodyTrimmed
    }
}
