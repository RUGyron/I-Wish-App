import Foundation
import SwiftData
import os.log

private let mcLog = Logger(subsystem: "RUGyron.IWish", category: "ModelContainer")

enum ModelContainerFactory {
    /// Создаёт production ModelContainer. Если SwiftData store повреждён
    /// (corruption после миграции, prematurely killed processes, и т.п.) —
    /// удаляет store-файлы и пробует ещё раз вместо launch-crash.
    /// Recovery приводит к потере local cache (Firestore догонит на refresh),
    /// что лучше чем app-uninstall как единственный выход для юзера.
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
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            mcLog.error("ModelContainer init failed: \(error.localizedDescription, privacy: .public). Attempting recovery by wiping local store.")
            wipeLocalSwiftDataStore()
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                // Если и после wipe не получилось — это уже системная проблема, fatal acceptable.
                mcLog.fault("ModelContainer init failed even after store wipe: \(error.localizedDescription, privacy: .public)")
                fatalError("Failed to create ModelContainer after recovery: \(error)")
            }
        }
    }

    private static func wipeLocalSwiftDataStore() {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else {
            return
        }
        // SwiftData по умолчанию пишет в Application Support / default.store + sidecar файлы.
        let names = ["default.store", "default.store-shm", "default.store-wal"]
        for name in names {
            let url = appSupport.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
                mcLog.info("removed corrupted SwiftData file: \(name, privacy: .public)")
            }
        }
    }
}
