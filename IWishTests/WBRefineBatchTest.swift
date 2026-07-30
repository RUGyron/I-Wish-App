import Testing
import Foundation
import UIKit
@testable import IWish

/// Batch test: парсим 6 разных WB URLs, пишем результат refine в /tmp/iwish-wb-batch.txt
@Suite("WB refine batch")
struct WBRefineBatchTest {
    @MainActor
    @Test("Batch WB items")
    func batch() async {
        let urls: [(String, String)] = [
            ("Защ.стекло UNIQ", "https://www.wildberries.ru/catalog/260535421/detail.aspx"),
            ("Пуфик Studioakd", "https://www.wildberries.ru/catalog/243707290/detail.aspx"),
            ("iPhone 16 Pro Desert", "https://www.wildberries.ru/catalog/260292260/detail.aspx"),
            ("iPhone 16 Pro Max", "https://www.wildberries.ru/catalog/261162757/detail.aspx"),
            ("Чехол Apple iPhone", "https://www.wildberries.ru/catalog/304958398/detail.aspx"),
            ("Сухой завтрак (Влад)", "https://www.wildberries.ru/catalog/559649727/detail.aspx"),
        ]
        var report = "WB refine batch test\n\n"
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
        try? report.write(toFile: "/tmp/iwish-wb-batch.txt", atomically: true, encoding: .utf8)
        print(report)
    }
}
