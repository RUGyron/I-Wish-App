import Testing
import Foundation
import UIKit
import FirebaseCore
import FirebaseAI
@testable import IWish

/// Live тест Gemini refine — проверка что Firebase AI Logic работает на iOS.
@Suite("Gemini refine — Firebase AI Logic check")
struct GeminiRefineLiveTest {
    @Test("Direct Gemini call")
    func directGemini() async throws {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let model = ai.generativeModel(modelName: "gemini-2.5-flash-lite")
        var out = "=== Direct Gemini ===\n"
        do {
            let resp = try await model.generateContent("Reply with single word: ping")
            out += "✅ Response: \(resp.text ?? "(nil text)")\n"
        } catch {
            out += "❌ Error: \(error)\n"
            out += "Localized: \(error.localizedDescription)\n"
        }
        try? out.write(toFile: "/tmp/iwish-gemini-direct.txt", atomically: true, encoding: .utf8)
        print(out)
    }

    @Test("Refine Apple iPhone page")
    func refineApple() async {
        let url = URL(string: "https://www.apple.com/shop/buy-iphone/iphone-16-pro")!
        let result = await URLMetadataService.fetch(from: url)
        var out = "=== Apple iPhone parser+refine ===\n"
        out += "url:     \(url.absoluteString)\n"
        out += "source:  \(result.source ?? "nil")\n"
        out += "title:   \(result.title ?? "—")\n"
        out += "image:   \(result.image != nil ? "✓ \(Int(result.image!.size.width))×\(Int(result.image!.size.height))" : "—")\n"
        out += "price:   \(result.price.map { "\(Int($0)) \(result.currency ?? "")" } ?? "—")\n"
        out += "desc:    \(result.descriptionText ?? "—")\n"
        try? out.write(toFile: "/tmp/iwish-gemini-test.txt", atomically: true, encoding: .utf8)
        print(out)
        #expect(result.title != nil)
    }
}
