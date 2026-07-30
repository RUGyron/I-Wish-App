import UIKit
import WebKit
import os.log

/// Fallback парсер на WKWebView. Используется когда URLSession 403/redirect-loop/antibot-stub.
/// WKWebView с настоящим Safari TLS + JS rendering обходит большинство antibot (Ozon, Я.Маркет, Cloudflare).
///
/// Стратегия для тяжёлых anti-bot (WB):
/// 1. **Pre-warm**: при первом запуске сессии WB — грузим главную wildberries.ru/ → получаем cookies
///    в `WKWebsiteDataStore.default()`. Cookies живут между fetch'ами одного домена.
/// 2. **JS-poller** вместо `didFinish`: каждые 700мс проверяем что DOM содержит реальный товар
///    (title не "Почти готово...", есть OG/JSON-LD/.product-selector). Anti-bot challenge сам
///    проходится JS'ом WB через несколько секунд — JS continueт работать в фоне.
/// 3. Timeout 25 сек total.
///
/// **Тонкости:**
/// - WebView прикреплён к key window — иначе JS не выполняется.
/// - Memory: 1-3 MB на инстанс — создаём only-on-demand, уничтожаем после.
@MainActor
enum WKWebViewMetadataFetcher {
    struct Result {
        let title: String?
        let imageURL: String?
        let price: Double?
        let currency: String?
    }

    private static let log = Logger(subsystem: "RUGyron.IWish", category: "WKWebViewFetcher")

    /// Глобальный shared cookie store — переживает между fetch'ами, прогревается на главных.
    private static let sharedDataStore: WKWebsiteDataStore = .default()
    /// Доменные хосты для которых уже сделан pre-warm в текущей сессии.
    private static var prewarmedHosts: Set<String> = []

    static func fetch(url: URL) async -> Result? {
        let fetcher = Fetcher(dataStore: sharedDataStore)
        // Pre-warm для WB: если ещё не грели — загрузить главную wildberries.ru/.
        if let host = url.host, host.hasSuffix("wildberries.ru"), !prewarmedHosts.contains(host) {
            prewarmedHosts.insert(host)
            log.info("Pre-warming cookies for \(host, privacy: .public)")
            _ = await Fetcher(dataStore: sharedDataStore).warmup(host: host, timeout: 8)
        }
        return await fetcher.run(url: url, timeout: 25)
    }
}

@MainActor
private final class Fetcher: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<WKWebViewMetadataFetcher.Result?, Never>?
    private var didFinish = false
    private var pollTask: Task<Void, Never>?
    private let dataStore: WKWebsiteDataStore
    private let log = Logger(subsystem: "RUGyron.IWish", category: "WKWebViewFetcher")

    init(dataStore: WKWebsiteDataStore) {
        self.dataStore = dataStore
        super.init()
    }

    /// Pre-warm: загрузить главную домена, дать JS отработать → cookies в `dataStore`.
    func warmup(host: String, timeout: TimeInterval) async -> Bool {
        guard let url = URL(string: "https://\(host)/") else { return false }
        let config = makeConfig()
        let wv = makeWebView(config: config, frame: CGRect(x: -10000, y: -10000, width: 320, height: 600))
        webView = wv
        attachToWindow(wv)

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            var finished = false
            let timer = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !finished {
                    finished = true
                    self.cleanup()
                    cont.resume(returning: false)
                }
            }
            // Слушаем didFinish — pre-warm не требует extraction.
            self.continuation = nil
            wv.navigationDelegate = WarmupDelegate { [weak self] in
                guard !finished else { return }
                finished = true
                timer.cancel()
                Task { @MainActor in
                    // Дать JS ещё 2 сек чтобы поставить challenge cookies.
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.cleanup()
                    cont.resume(returning: true)
                }
            }
            wv.load(URLRequest(url: url, timeoutInterval: timeout - 1))
        }
    }

    func run(url: URL, timeout: TimeInterval) async -> WKWebViewMetadataFetcher.Result? {
        await withCheckedContinuation { (cont: CheckedContinuation<WKWebViewMetadataFetcher.Result?, Never>) in
            self.continuation = cont
            setupAndLoad(url: url, timeout: timeout)
        }
    }

    private func makeConfig() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.suppressesIncrementalRendering = false
        config.websiteDataStore = dataStore
        return config
    }

    private func makeWebView(config: WKWebViewConfiguration, frame: CGRect) -> WKWebView {
        let wv = WKWebView(frame: frame, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
        wv.isHidden = true
        wv.isUserInteractionEnabled = false
        return wv
    }

    private func attachToWindow(_ wv: WKWebView) {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            window.addSubview(wv)
        }
    }

    private var originalURL: URL?

    private func setupAndLoad(url: URL, timeout: TimeInterval) {
        self.originalURL = url
        let config = makeConfig()
        let wv = makeWebView(config: config, frame: CGRect(x: -10000, y: -10000, width: 375, height: 800))
        wv.navigationDelegate = self
        attachToWindow(wv)
        self.webView = wv

        // Timeout страховка.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self else { return }
            if !self.didFinish {
                self.log.warning("WKWebView timeout for \(url.absoluteString, privacy: .public)")
                self.finish(with: nil)
            }
        }

        wv.load(URLRequest(url: url, timeoutInterval: timeout - 1))

        // JS-poller: после первого didCommit запускаем polling extraction каждые 700мс.
        // Останавливаем при first successful extract либо при timeout.
        pollTask = Task { @MainActor [weak self] in
            // Дать первый рендер хотя бы 1 сек.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for _ in 0..<30 {
                if Task.isCancelled { return }
                guard let self, !self.didFinish, let webView = self.webView else { return }
                let currentURL = webView.url
                if let r = await self.tryExtract(from: webView), self.isPlausible(r, originalURL: self.originalURL, currentURL: currentURL) {
                    self.finish(with: r)
                    return
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    /// Считаем результат правдоподобным если есть title который не похож на antibot challenge,
    /// и (для маркетплейсов) не похож на главную страницу.
    private func isPlausible(_ r: WKWebViewMetadataFetcher.Result, originalURL: URL?, currentURL: URL?) -> Bool {
        guard let t = r.title?.lowercased() else { return false }
        let antibot = ["почти готово", "just a moment", "checking your browser", "ddos-guard", "one moment", "loading", "redirecting"]
        if antibot.contains(where: { t.contains($0) }) { return false }
        // Главные страницы маркетплейсов — anti-bot перенаправил с товара на главную.
        let homepagePatterns = [
            "интернет-магазин wildberries",
            "интернет‑магазин wildberries",
            "ozon — интернет-магазин",
            "ozon — крупнейший",
            "яндекс маркет",
            "aliexpress: онлайн"
        ]
        if homepagePatterns.contains(where: { t.contains($0) }) { return false }
        // Если URL изменился на главную (path = "/" или пустой) — это редирект, не товар.
        if let cur = currentURL, let orig = originalURL,
           orig.host == cur.host,
           orig.path.contains("/catalog/") || orig.path.contains("/product/") {
            let currentPath = cur.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if currentPath.isEmpty { return false }
            // Проверяем что в path остался ID товара из original URL.
            let origNumericIDs = orig.path.split(separator: "/").compactMap { Int($0) }
            if !origNumericIDs.isEmpty {
                let curHasOrigID = origNumericIDs.contains { cur.path.contains(String($0)) }
                if !curHasOrigID { return false }
            }
        }
        return !t.isEmpty
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Не финиш сразу — pollerу всё равно будет результат через JS-poller.
        // Но дадим ему лишний chance: если poller к моменту finish уже нашёл — finish() уже вызван.
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.log.warning("WKWebView didFail: \(error.localizedDescription, privacy: .public)")
            self?.finish(with: nil)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.log.warning("WKWebView didFailProvisional: \(error.localizedDescription, privacy: .public)")
            self?.finish(with: nil)
        }
    }

    private func tryExtract(from wv: WKWebView) async -> WKWebViewMetadataFetcher.Result? {
        let js = """
        (function() {
          function getMeta(prop) {
            const el = document.querySelector(`meta[property="${prop}"]`) || document.querySelector(`meta[name="${prop}"]`);
            return el ? el.getAttribute('content') : null;
          }
          let title = getMeta('og:title') || getMeta('twitter:title') || document.title;
          let image = getMeta('og:image') || getMeta('og:image:url') || getMeta('twitter:image');
          let price = getMeta('product:price:amount') || getMeta('og:price:amount');
          let currency = getMeta('product:price:currency') || getMeta('og:price:currency');

          // JSON-LD Product
          const scripts = document.querySelectorAll('script[type="application/ld+json"]');
          for (const s of scripts) {
            try {
              const obj = JSON.parse(s.textContent);
              const stack = [obj];
              while (stack.length) {
                const n = stack.shift();
                if (!n || typeof n !== 'object') continue;
                if (Array.isArray(n)) { stack.push(...n); continue; }
                const t = n['@type'];
                const types = Array.isArray(t) ? t : [t];
                if (types.some(x => typeof x === 'string' && /product/i.test(x))) {
                  if (!title && n.name) title = n.name;
                  if (!image && n.image) image = typeof n.image === 'string' ? n.image : (Array.isArray(n.image) ? n.image[0] : n.image.url);
                  const offers = Array.isArray(n.offers) ? n.offers : (n.offers ? [n.offers] : []);
                  for (const o of offers) {
                    if (!price && (o.price || o.lowPrice)) price = String(o.price ?? o.lowPrice);
                    if (!currency && o.priceCurrency) currency = o.priceCurrency;
                  }
                }
                if (n['@graph']) stack.push(n['@graph']);
                for (const v of Object.values(n)) {
                  if (v && typeof v === 'object') stack.push(v);
                }
              }
            } catch {}
          }

          // Wildberries-specific: на странице товара есть .product-page__title и .price-block__final-price.
          if (!title) {
            const wbTitle = document.querySelector('h1.product-page__title') || document.querySelector('h1');
            if (wbTitle) title = wbTitle.textContent.trim();
          }
          if (!price) {
            const wbPrice = document.querySelector('.price-block__final-price, .price-block__wallet-price, ins.price-block__final-price');
            if (wbPrice) price = wbPrice.textContent.replace(/[^\\d.,]/g, '');
          }
          if (!image) {
            const wbImg = document.querySelector('.photo-zoom__preview, .slide__content img, .product-page__gallery img');
            if (wbImg) image = wbImg.src || wbImg.getAttribute('data-src') || wbImg.getAttribute('srcset')?.split(' ')[0];
          }

          return JSON.stringify({ title, image, price, currency });
        })();
        """

        let raw: Any?
        do {
            raw = try await wv.evaluateJavaScript(js)
        } catch {
            return nil
        }
        guard let str = raw as? String,
              let data = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = (obj["image"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let priceRaw = obj["price"]
        let currency = (obj["currency"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let price = parsePriceNumber(priceRaw)

        if (title?.isEmpty ?? true) && (image?.isEmpty ?? true) && price == nil { return nil }
        return WKWebViewMetadataFetcher.Result(
            title: (title?.isEmpty == false) ? title : nil,
            imageURL: (image?.isEmpty == false) ? image : nil,
            price: price,
            currency: (currency?.isEmpty == false) ? currency : nil
        )
    }

    private func cleanup() {
        pollTask?.cancel()
        pollTask = nil
        webView?.removeFromSuperview()
        webView?.navigationDelegate = nil
        webView = nil
    }

    private func finish(with result: WKWebViewMetadataFetcher.Result?) {
        guard !didFinish else { return }
        didFinish = true
        cleanup()
        continuation?.resume(returning: result)
        continuation = nil
    }
}

/// Дёрнули отдельный delegate для warmup чтобы не путать с основным polling state.
@MainActor
private final class WarmupDelegate: NSObject, WKNavigationDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.onFinish() }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.onFinish() }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.onFinish() }
    }
}
