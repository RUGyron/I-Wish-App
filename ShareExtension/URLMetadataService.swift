import UIKit
import os.log

/// Extracts product metadata from a URL via direct HTTP (URLSession Safari TLS) + on-device parsing.
///
/// **Архитектура (2026-05-16):**
/// 1. **WB rule (Wildberries):** card.wb.ru/cards/v4/detail — официальный публичный API,
///    возвращает JSON с title/brand/price/image без antibot.
/// 2. **Generic HTML fetch + extractors:** JSON-LD (Schema.org Product) → OpenGraph (с product:price:*) →
///    Twitter Card → <title>. iOS URLSession имеет Safari TLS fingerprint — большинство antibot пропустят.
/// 3. **WKWebView fallback:** через `WKWebViewMetadataFetcher` — рендерит JS, обходит Cloudflare-class
///    проверки. Используется когда HTTP fetch вернул 403/redirect-loop. См. WKWebViewMetadataFetcher.swift.
struct URLMetadataService {
    struct PageMetadata {
        var title: String?
        var image: UIImage?
        /// Цена товара (если удалось извлечь). Без копеек/центов.
        var price: Double?
        /// Валюта ISO 4217 (RUB / USD / EUR / ...). nil если price тоже nil.
        var currency: String?
        /// Короткое описание товара (добавляется Gemini-refine, если запустился).
        var descriptionText: String?
        /// Источник для debug/log: "wildberries-api" / "json-ld" / "open-graph" / "webview" / ...
        /// При успешном Gemini-refine добавляется суффикс "+gemini".
        var source: String?
    }

    private static let log = Logger(subsystem: "RUGyron.IWish", category: "URLMetadata")

    static func fetch(from url: URL) async -> PageMetadata {
        // 1. Custom rules под маркетплейсы.
        let host = url.host?.lowercased().replacingOccurrences(of: "www.", with: "") ?? ""
        if host.hasSuffix("wildberries.ru") {
            if let r = await WildberriesRule.fetch(url: url) {
                log.info("URLMetadata: WB API hit for \(url.absoluteString, privacy: .public)")
                // Refine WB-результат через Gemini: чистим title от "BRAND. ..." формата,
                // нормализуем + опционально дополним description. HTML недоступен (WB antibot),
                // refine только на raw API data.
                let refined = await GeminiMetadataFallback.refine(
                    html: nil, url: url,
                    title: r.title,
                    imageURL: nil,
                    price: r.price,
                    currency: r.currency
                )
                return PageMetadata(
                    title: refined?.title?.isEmpty == false ? refined?.title : r.title,
                    image: r.image,
                    price: refined?.price ?? r.price,
                    currency: refined?.currency?.isEmpty == false ? refined?.currency : r.currency,
                    descriptionText: refined?.descriptionText,
                    source: refined != nil ? "wildberries-api+gemini" : "wildberries-api"
                )
            }
            log.info("URLMetadata: WB API miss, falling through to generic")
        }

        // 2. Generic HTTP fetch.
        let fetched = await fetchHTML(from: url)

        // Quick antibot/homepage title check — если title явно antibot или homepage маркетплейса,
        // не используем результат как final, идём дальше в WKWebView fallback.
        func isAntibotOrHomepageTitle(_ t: String?) -> Bool {
            guard let lower = t?.lowercased() else { return true }
            // Antibot challenge pages
            let antibot = ["antibot challenge", "antibot", "почти готово", "just a moment", "checking your browser", "one moment", "ddos-guard", "loading", "redirecting", "captcha", "challenge-platform", "cf-browser-verification"]
            if antibot.contains(where: { lower.contains($0) }) { return true }
            // Marketplace homepages (anti-bot redirect on product page → homepage title)
            let homepages = [
                "интернет-магазин wildberries", "интернет‑магазин wildberries",
                "ozon — интернет-магазин", "ozon — крупнейший", "ozon: онлайн-магазин",
                "яндекс маркет — найти и купить", "яндекс маркет\u{00A0}—", "yandex маркет",
                "aliexpress: онлайн", "aliexpress – интернет",
                "amazon.com: online shopping"
            ]
            if homepages.contains(where: { lower.contains($0) }) { return true }
            // Exact match для гoловных страниц (одно-двусловный title маркетплейса).
            let exactHomepageNames: Set<String> = ["яндекс маркет", "яндекс\u{00A0}маркет", "ozon", "wildberries", "aliexpress", "amazon", "яндекс.маркет"]
            if exactHomepageNames.contains(lower.trimmingCharacters(in: .whitespacesAndNewlines)) { return true }
            return false
        }
        // Legacy alias
        let isAntibotTitle = isAntibotOrHomepageTitle

        if let html = fetched.html {
            let extracted = extractFromHTML(html, baseURL: url)
            // Сильный сигнал — JSON-LD / OG / Twitter с осмысленным title или price/image.
            // Title-tag в одиночку — слабый сигнал: на antibot/homepage страницах он мусорный.
            let isStrongSignal: Bool = {
                if extracted.source != "title-tag" {
                    // Дополнительно — даже сильные signals могут оказаться antibot/homepage stub'ом
                    return !isAntibotOrHomepageTitle(extracted.title) &&
                        (extracted.title != nil || extracted.imageURL != nil || extracted.price != nil)
                }
                // Source = title-tag: возьмём только если не antibot/homepage.
                return !isAntibotOrHomepageTitle(extracted.title)
            }()
            if isStrongSignal {
                // Gemini-refine: чистим title от SEO-хвостов, проверяем price, добавляем description.
                // На rate-limit / Gemini error — silent fallback на raw extracted (никакой блокировки UX).
                let refined = await GeminiMetadataFallback.refine(
                    html: html, url: url,
                    title: extracted.title?.htmlDecoded.trimmed,
                    imageURL: extracted.imageURL,
                    price: extracted.price,
                    currency: extracted.currency
                )
                let finalTitle = (refined?.title?.isEmpty == false ? refined?.title : extracted.title?.htmlDecoded.trimmed)
                let finalImageURL = (refined?.imageURL?.isEmpty == false ? refined?.imageURL : extracted.imageURL)
                let finalPrice = refined?.price ?? extracted.price
                let finalCurrency = (refined?.currency?.isEmpty == false ? refined?.currency : extracted.currency)
                let finalDesc = refined?.descriptionText
                let image = await fetchImage(finalImageURL, base: url)
                return PageMetadata(
                    title: finalTitle,
                    image: image,
                    price: finalPrice,
                    currency: finalCurrency,
                    descriptionText: finalDesc,
                    source: refined != nil ? (extracted.source ?? "extract") + "+gemini" : extracted.source
                )
            }
        }

        // 3. WKWebView fallback — если HTTP вернул 403/empty/redirect-loop, antibot заглушку
        //    или extractors не нашли сильного сигнала. На устройстве Safari TLS + JS rendering
        //    пробивает Ozon/Я.Маркет/Cloudflare-class.
        if shouldTryWebViewFallback(fetched: fetched) || hasOnlyWeakSignal(fetched: fetched) {
            log.info("URLMetadata: WKWebView fallback for \(url.absoluteString, privacy: .public)")
            if let webMeta = await WKWebViewMetadataFetcher.fetch(url: url) {
                // Отбрасываем antibot-результаты — лучше пусто чем "Antibot Challenge Page" в name.
                if isAntibotTitle(webMeta.title) {
                    log.info("URLMetadata: WKWebView вернул antibot title, выкидываем")
                    return PageMetadata()
                }
                let refined = await GeminiMetadataFallback.refine(
                    html: fetched.html, url: url,
                    title: webMeta.title?.htmlDecoded.trimmed,
                    imageURL: webMeta.imageURL,
                    price: webMeta.price,
                    currency: webMeta.currency
                )
                let finalImageURL = (refined?.imageURL?.isEmpty == false ? refined?.imageURL : webMeta.imageURL)
                let image = await fetchImage(finalImageURL, base: url)
                return PageMetadata(
                    title: (refined?.title?.isEmpty == false ? refined?.title : webMeta.title?.htmlDecoded.trimmed),
                    image: image,
                    price: refined?.price ?? webMeta.price,
                    currency: (refined?.currency?.isEmpty == false ? refined?.currency : webMeta.currency),
                    descriptionText: refined?.descriptionText,
                    source: refined != nil ? "webview+gemini" : "webview"
                )
            }
        }

        // 4. Gemini AI fallback — Last-resort если HTML есть, но структурированных данных не нашли.
        //    Подаём HTML в Gemini 2.5 Flash-Lite со strict JSON schema. Обрабатывает React SPA,
        //    нестандартные layouts, страницы без OG/JSON-LD. Free tier 1500 RPD.
        if let html = fetched.html, html.count > 1500 {
            log.info("URLMetadata: Gemini fallback for \(url.absoluteString, privacy: .public)")
            if let geminiMeta = await GeminiMetadataFallback.extract(html: html, url: url) {
                // Refine на extract result чтобы получить description (extract возвращает только базовые поля).
                let refined = await GeminiMetadataFallback.refine(
                    html: html, url: url,
                    title: geminiMeta.title,
                    imageURL: geminiMeta.imageURL,
                    price: geminiMeta.price,
                    currency: geminiMeta.currency
                )
                let finalImageURL = (refined?.imageURL?.isEmpty == false ? refined?.imageURL : geminiMeta.imageURL)
                let image = await fetchImage(finalImageURL, base: url)
                return PageMetadata(
                    title: (refined?.title?.isEmpty == false ? refined?.title : geminiMeta.title?.htmlDecoded.trimmed),
                    image: image,
                    price: refined?.price ?? geminiMeta.price,
                    currency: (refined?.currency?.isEmpty == false ? refined?.currency : geminiMeta.currency),
                    descriptionText: refined?.descriptionText,
                    source: "gemini-extract+refine"
                )
            }
        }

        return PageMetadata()
    }

    // MARK: - HTML fetch

    private struct FetchResult {
        let html: String?
        let statusCode: Int?
        let error: Error?
    }

    /// Hard cap на размер HTML — защита от memory-attack (адверсарный сайт может
    /// слать гигабайты в HTTP body). Метаданных нет нужды искать в больше чем 2МБ.
    private static let maxHTMLBytes = 2 * 1024 * 1024

    private static func fetchHTML(from url: URL) async -> FetchResult {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("ru-RU,ru;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let bounded = data.count > maxHTMLBytes ? data.prefix(maxHTMLBytes) : data
            let boundedData = Data(bounded)
            let html = String(data: boundedData, encoding: .utf8)
                ?? String(data: boundedData, encoding: .windowsCP1251)
            let code = (response as? HTTPURLResponse)?.statusCode
            return FetchResult(html: html, statusCode: code, error: nil)
        } catch {
            return FetchResult(html: nil, statusCode: nil, error: error)
        }
    }

    private static func shouldTryWebViewFallback(fetched: FetchResult) -> Bool {
        // Если получили error → WKWebView попробует ещё раз с другим TLS.
        if fetched.error != nil { return true }
        // 4xx/5xx → fallback.
        if let code = fetched.statusCode, code >= 400 { return true }
        // Пустой / слишком короткий HTML — скорее всего antibot заглушка.
        if let html = fetched.html, html.count < 1024 { return true }
        return false
    }

    /// 200 OK с большим HTML, но title намекает что это antibot challenge: "Почти готово...", "Just a moment...".
    /// Это слабый сигнал — пробуем WKWebView чтобы получить настоящий контент.
    private static func hasOnlyWeakSignal(fetched: FetchResult) -> Bool {
        guard let html = fetched.html else { return false }
        // Быстрый префиксный чек на antibot маркеры в первых 8КБ.
        let head = html.prefix(8_000).lowercased()
        let markers = ["почти готово", "just a moment", "checking your browser", "ddos-guard", "challenge-platform", "cf-browser-verification"]
        return markers.contains(where: { head.contains($0) })
    }

    private static func fetchImage(_ urlStr: String?, base: URL) async -> UIImage? {
        guard let urlStr, let imageURL = resolveURL(urlStr, base: base) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private static func resolveURL(_ str: String, base: URL) -> URL? {
        if str.hasPrefix("//") { return URL(string: "https:" + str) }
        if str.hasPrefix("http") { return URL(string: str) }
        return URL(string: str, relativeTo: base)?.absoluteURL
    }

    // MARK: - HTML extraction

    struct ExtractResult {
        var title: String?
        var imageURL: String?
        var price: Double?
        var currency: String?
        var source: String?
    }

    /// Extract metadata из HTML.
    /// Приоритет: JSON-LD (Product schema, чаще всего с реальной ценой) → OG → Twitter → <title>.
    static func extractFromHTML(_ html: String, baseURL: URL? = nil) -> ExtractResult {
        // 1. JSON-LD.
        if let jld = JsonLdExtractor.extract(from: html) {
            return ExtractResult(
                title: jld.title,
                imageURL: jld.imageURL,
                price: jld.price,
                currency: jld.currency,
                source: "json-ld"
            )
        }
        // 2. OpenGraph (включая product:price:*).
        if let og = OpenGraphExtractor.extract(from: html) {
            return ExtractResult(
                title: og.title,
                imageURL: og.imageURL,
                price: og.price,
                currency: og.currency,
                source: "open-graph"
            )
        }
        // 3. Twitter Card.
        if let tw = TwitterCardExtractor.extract(from: html) {
            return ExtractResult(
                title: tw.title,
                imageURL: tw.imageURL,
                source: "twitter-card"
            )
        }
        // 4. <title>.
        if let t = TitleTagExtractor.extract(from: html) {
            return ExtractResult(title: t, source: "title-tag")
        }
        return ExtractResult()
    }
}

// MARK: - String helpers (used by extractors)

extension String {
    var htmlDecoded: String {
        var s = self
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")
        ]
        for (k, v) in named { s = s.replacingOccurrences(of: k, with: v) }
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

/// Парсит число из строки вида "1234.56" / "1 234,56" / "1,234.56" / "1234".
/// Возвращает nil если число ≤ 0 или не парсится.
func parsePriceNumber(_ raw: Any?) -> Double? {
    if let n = raw as? Double, n.isFinite, n > 0 { return n }
    if let n = raw as? Int, n > 0 { return Double(n) }
    if let n = raw as? NSNumber {
        let d = n.doubleValue
        return d.isFinite && d > 0 ? d : nil
    }
    guard let str = raw as? String else { return nil }
    let cleaned = str.replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "\u{00A0}", with: "")
        .components(separatedBy: CharacterSet(charactersIn: "0123456789.,").inverted)
        .joined()
    guard !cleaned.isEmpty else { return nil }
    var numStr = cleaned
    if cleaned.contains(",") && cleaned.contains(".") {
        // "1,234.56" — запятая=тысячи.
        numStr = cleaned.replacingOccurrences(of: ",", with: "")
    } else if cleaned.contains(",") {
        // "1234,56" — запятая=десятичный.
        numStr = cleaned.replacingOccurrences(of: ",", with: ".")
    }
    guard let d = Double(numStr), d.isFinite, d > 0 else { return nil }
    return d
}
