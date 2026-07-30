import Testing
import Foundation
import UIKit
@testable import IWish

/// Comprehensive batch: реальные товарные URL разных РФ и иностранных маркетплейсов.
@Suite("Comprehensive marketplace batch")
struct ComprehensiveBatchTest {
    @MainActor
    @Test("Big batch")
    func bigBatch() async {
        let urls: [(String, String)] = [
            // WB — стабильно работают (через card.wb.ru/v4)
            ("WB UNIQ стекло",      "https://www.wildberries.ru/catalog/260535421/detail.aspx"),
            ("WB Пуфик",            "https://www.wildberries.ru/catalog/243707290/detail.aspx"),
            ("WB Чехол Baseus",     "https://www.wildberries.ru/catalog/304958398/detail.aspx"),
            ("WB iPhone 16 Pro",    "https://www.wildberries.ru/catalog/260292260/detail.aspx"),
            ("WB iPhone Pro Max",   "https://www.wildberries.ru/catalog/261162757/detail.aspx"),
            // Ozon — antibot
            ("Ozon iPhone 16",      "https://www.ozon.ru/product/apple-smartfon-iphone-16-esim-sim-8-128-gb-siniy-1720312800/"),
            ("Ozon short link",     "https://ozon.ru/t/hop4BXg"),
            // Я.Маркет — antibot
            ("Я.Маркет iPhone",     "https://market.yandex.ru/product--smartfon-apple-iphone-16-pro/100000000"),
            // AliExpress
            ("AliExpress placeholder", "https://aliexpress.ru/item/1005006000000000.html"),
            // Apple Store
            ("Apple iPhone 16 Pro", "https://www.apple.com/shop/buy-iphone/iphone-16-pro"),
            ("Apple AirPods Pro",   "https://www.apple.com/shop/buy-airpods/airpods-pro-2"),
            // Lamoda
            ("Lamoda пример",        "https://www.lamoda.ru/p/RTLABG175201/"),
            // М.Видео
            ("М.Видео пример",       "https://www.mvideo.ru/products/smartfon-apple-iphone-16-pro-128gb-natural-titanium-10001234567"),
            // DNS Shop
            ("DNS пример",           "https://www.dns-shop.ru/product/abc123/smartfon-iphone-16-pro/"),
            // Amazon
            ("Amazon iPhone B0...", "https://www.amazon.com/dp/B0DGJ5XSPZ"),
            // Generic non-marketplace
            ("GitHub repo",         "https://github.com/swiftlang/swift"),
            ("Wikipedia article",   "https://en.wikipedia.org/wiki/IPhone_16_Pro"),
        ]
        var report = "Comprehensive marketplace batch — \(urls.count) URLs\n\n"
        for (label, urlStr) in urls {
            guard let url = URL(string: urlStr) else { continue }
            let t0 = Date()
            let meta = await URLMetadataService.fetch(from: url)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            report += "=== \(label) (\(ms)ms) ===\n"
            report += "  url:    \(urlStr)\n"
            report += "  source: \(meta.source ?? "—")\n"
            report += "  title:  \(meta.title ?? "—")\n"
            report += "  image:  \(meta.image != nil ? "✓ \(Int(meta.image!.size.width))×\(Int(meta.image!.size.height))" : "—")\n"
            report += "  price:  \(meta.price.map { "\(Int($0)) \(meta.currency ?? "")" } ?? "—")\n"
            report += "  desc:   \(meta.descriptionText ?? "—")\n\n"
        }
        try? report.write(toFile: "/tmp/iwish-comprehensive-batch.txt", atomically: true, encoding: .utf8)
        print(report)
    }
}
