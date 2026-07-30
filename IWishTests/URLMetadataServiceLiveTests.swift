import Testing
import Foundation
import UIKit
@testable import IWish

/// Live-network тесты парсера. НЕ запускать на CI без интернета.
/// Запуск: xcodebuild test -only-testing:IWishTests/URLMetadataServiceLiveTests
@Suite("URLMetadataService — live network tests")
struct URLMetadataServiceLiveTests {
    private func run(_ urlString: String, label: String) async -> URLMetadataService.PageMetadata {
        guard let url = URL(string: urlString) else { return URLMetadataService.PageMetadata() }
        let start = Date()
        let meta = await URLMetadataService.fetch(from: url)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("=== \(label) (\(ms)ms) ===")
        print("  url:    \(urlString)")
        print("  source: \(meta.source ?? "nil")")
        print("  title:  \(meta.title ?? "—")")
        print("  image:  \(meta.image != nil ? "✓ \(Int(meta.image!.size.width))×\(Int(meta.image!.size.height))" : "—")")
        if let p = meta.price { print("  price:  \(Int(p)) \(meta.currency ?? "")") } else { print("  price:  —") }
        return meta
    }

    @Test("WB iPhone 16 Pro 128GB Desert (in-stock)")
    func wbInStock() async {
        let m = await run("https://www.wildberries.ru/catalog/260535421/detail.aspx", label: "WB защ. стекло")
        #expect(m.source == "wildberries-api")
        #expect(m.title != nil)
        #expect(m.price != nil)
    }

    @Test("WB URL из чата Влада")
    func wbVladURL() async {
        let m = await run("https://www.wildberries.ru/catalog/243707290/detail.aspx?size=382423654", label: "WB Влад")
        #expect(m.source == "wildberries-api")
        #expect(m.title != nil)
    }

    @Test("Apple iPhone 16 Pro shop")
    func apple() async {
        let m = await run("https://www.apple.com/shop/buy-iphone/iphone-16-pro", label: "Apple")
        #expect(m.title != nil)
    }

    @Test("GitHub repo")
    func github() async {
        let m = await run("https://github.com/swiftlang/swift", label: "GitHub")
        #expect(m.title != nil)
    }

    @Test("Wikipedia article")
    func wiki() async {
        let m = await run("https://en.wikipedia.org/wiki/IPhone", label: "Wikipedia")
        #expect(m.title != nil)
    }

    @Test("Ozon short link от Влада")
    func ozonShort() async {
        // Может не пройти на сервере — antibot. WKWebView fallback должен сработать.
        _ = await run("https://ozon.ru/t/hop4BXg", label: "Ozon short")
    }

    @Test("Ozon long product URL")
    func ozonLong() async {
        _ = await run("https://www.ozon.ru/product/apple-smartfon-iphone-16-esim-sim-8-128-gb-siniy-1720312800/", label: "Ozon long")
    }

    @Test("Я.Маркет product")
    func yamarket() async {
        _ = await run("https://market.yandex.ru/product--smartfon-apple-iphone-16-pro-128-gb-2-sim-natural-titanium/100000000", label: "Я.Маркет")
    }

    @Test("AliExpress product")
    func aliExpress() async {
        _ = await run("https://aliexpress.ru/item/1005006000000000.html", label: "AliExpress")
    }

    @Test("Generic Russian blog")
    func generic() async {
        _ = await run("https://habr.com/ru/articles/", label: "Habr")
    }
}
