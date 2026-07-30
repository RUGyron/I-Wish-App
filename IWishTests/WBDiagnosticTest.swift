import Testing
import Foundation
import UIKit
@testable import IWish

/// Diagnostic тест для WB — записывает каждый этап парсинга в /tmp/iwish-wb-diag.txt.
/// Запуск: xcodebuild test -only-testing:IWishTests/WBDiagnosticTest
@Suite("WB diagnostic — пошаговый разбор")
struct WBDiagnosticTest {
    @MainActor
    @Test("WB полный flow с записью этапов")
    func diagFlow() async {
        let url = URL(string: "https://www.wildberries.ru/catalog/260535421/detail.aspx")!
        var report = "WB diagnostic for \(url.absoluteString)\n\n"

        // Step 1: WildberriesRule (URLSession to card.wb.ru/v4)
        let t1 = Date()
        let wbResult = await WildberriesRule.fetch(url: url)
        let ms1 = Int(Date().timeIntervalSince(t1) * 1000)
        report += "Step 1 — WildberriesRule (URLSession card.wb.ru/v4): \(ms1)ms\n"
        if let r = wbResult {
            report += "  title:    \(r.title ?? "—")\n"
            report += "  image:    \(r.image != nil ? "✓" : "—")\n"
            report += "  price:    \(r.price.map { "\(Int($0)) \(r.currency ?? "")" } ?? "—")\n"
        } else {
            report += "  ❌ returned nil (API call failed / no product)\n"
        }
        report += "\n"

        // Step 2: Direct URLSession to wildberries.ru/catalog/...
        let t2 = Date()
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let ms2 = Int(Date().timeIntervalSince(t2) * 1000)
            let http = (response as? HTTPURLResponse)?.statusCode ?? -1
            let html = String(data: data.prefix(500), encoding: .utf8) ?? "(non-utf8)"
            report += "Step 2 — Direct URLSession wildberries.ru: \(ms2)ms, HTTP \(http), \(data.count) bytes\n"
            report += "  first 300 chars: \(html.prefix(300))\n\n"
        } catch {
            report += "Step 2 — URLSession failed: \(error.localizedDescription)\n\n"
        }

        // Step 3: WKWebView fallback
        let t3 = Date()
        let webResult = await WKWebViewMetadataFetcher.fetch(url: url)
        let ms3 = Int(Date().timeIntervalSince(t3) * 1000)
        report += "Step 3 — WKWebView (pre-warm + poller): \(ms3)ms\n"
        if let r = webResult {
            report += "  title:    \(r.title ?? "—")\n"
            report += "  image:    \(r.imageURL ?? "—")\n"
            report += "  price:    \(r.price.map { "\(Int($0)) \(r.currency ?? "")" } ?? "—")\n"
        } else {
            report += "  ❌ returned nil\n"
        }
        report += "\n"

        // Step 4: Full URLMetadataService (includes Gemini fallback)
        let t4 = Date()
        let full = await URLMetadataService.fetch(from: url)
        let ms4 = Int(Date().timeIntervalSince(t4) * 1000)
        report += "Step 4 — URLMetadataService.fetch (full pipeline): \(ms4)ms\n"
        report += "  source:   \(full.source ?? "—")\n"
        report += "  title:    \(full.title ?? "—")\n"
        report += "  image:    \(full.image != nil ? "✓ \(Int(full.image!.size.width))×\(Int(full.image!.size.height))" : "—")\n"
        report += "  price:    \(full.price.map { "\(Int($0)) \(full.currency ?? "")" } ?? "—")\n"

        try? report.write(toFile: "/tmp/iwish-wb-diag.txt", atomically: true, encoding: .utf8)
        print(report)
    }
}
