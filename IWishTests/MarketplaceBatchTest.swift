import Testing
import Foundation
import UIKit
@testable import IWish

/// Multi-marketplace batch: WB + Ozon + Я.Маркет + AliExpress + Apple + Amazon.
@Suite("Multi-marketplace refine batch")
struct MarketplaceBatchTest {
    @MainActor
    @Test("Batch")
    func batch() async {
        let urls: [(String, String)] = [
            ("WB Чехол Baseus", "https://www.wildberries.ru/catalog/304958398/detail.aspx"),
            ("WB iPhone 16 Pro", "https://www.wildberries.ru/catalog/260292260/detail.aspx"),
            ("Ozon iPhone 16", "https://www.ozon.ru/product/apple-smartfon-iphone-16-esim-sim-8-128-gb-siniy-1720312800/"),
            ("Ozon short link", "https://ozon.ru/t/hop4BXg"),
            ("Я.Маркет iPhone", "https://market.yandex.ru/product--smartfon-apple-iphone-16-pro/100000000"),
            ("Apple iPhone 16 Pro", "https://www.apple.com/shop/buy-iphone/iphone-16-pro"),
            ("AliExpress", "https://aliexpress.ru/item/1005006000000000.html"),
        ]
        var report = "Multi-marketplace refine batch\n\n"
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
        try? report.write(toFile: "/tmp/iwish-marketplace-batch.txt", atomically: true, encoding: .utf8)
        print(report)
    }
}
