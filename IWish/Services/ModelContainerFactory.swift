import Foundation
import SwiftData

enum ModelContainerFactory {
    static let cloudKitContainerID = "iCloud.com.rugyron.iwish"

    static func makeProductionContainer() -> ModelContainer {
        let fullSchema = Schema([
            Wishlist.self,
            Item.self,
            AppSettings.self,
        ])

        // Wishlists + Items → CloudKit private database (syncs across user's devices)
        let cloudConfig = ModelConfiguration(
            "CloudStore",
            schema: Schema([Wishlist.self, Item.self]),
            cloudKitDatabase: .private(cloudKitContainerID)
        )

        // AppSettings → local only (no sync)
        let localConfig = ModelConfiguration(
            "LocalStore",
            schema: Schema([AppSettings.self]),
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(
                for: fullSchema,
                configurations: [cloudConfig, localConfig]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
