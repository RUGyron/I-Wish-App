import Foundation

/// Stub в Share Extension. Полный Gemini refine происходит в main app при обработке очереди.
/// Extension избегает FirebaseAI чтобы держаться в memory limit (~16MB).
enum GeminiMetadataFallback {
    struct Result {
        let title: String?
        let imageURL: String?
        let price: Double?
        let currency: String?
    }

    struct RefinedResult {
        let title: String?
        let imageURL: String?
        let price: Double?
        let currency: String?
        let descriptionText: String?
    }

    static func extract(html: String, url: URL) async -> Result? { nil }

    static func refine(
        html: String?,
        url: URL,
        title: String?,
        imageURL: String?,
        price: Double?,
        currency: String?
    ) async -> RefinedResult? {
        nil
    }
}
