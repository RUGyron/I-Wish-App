import Foundation
import SwiftData

enum ModelContainerFactory {
    static let cloudKitContainerID = "iCloud.RUGyron.IWish"

    static func makeProductionContainer() -> ModelContainer {
        let schema = Schema([
            Wishlist.self,
            Item.self,
            AppSettings.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
