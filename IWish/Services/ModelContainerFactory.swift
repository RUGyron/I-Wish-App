import Foundation
import SwiftData

enum ModelContainerFactory {
    /// Production-контейнер. Phase 1 — без CloudKit, локально.
    /// В Phase 2 здесь добавится `cloudKitDatabase: .private(...)` и `@Attribute(.encrypt)`.
    static func makeProductionContainer() -> ModelContainer {
        let schema = Schema([
            Wishlist.self,
            Item.self,
            AppSettings.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
