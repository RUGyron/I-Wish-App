import SwiftUI
import SwiftData
import FirebaseAuth

@MainActor
final class AppServices {
    static let shared = AppServices()
    let auth = AuthService()
    let firestore = FirestoreService()
    let networkMonitor = NetworkMonitor()
    let push = PushNotificationService()
    let sync = SyncEngine()
    var data: DataService!
    var accountDeletion: AccountDeletionService!

    init() {
        // Bi-directional wire: monitor получает outcome через firestore, и сам может пинговать firestore.
        firestore.networkMonitor = networkMonitor
        networkMonitor.attach(firestore: firestore)
        push.attach(auth: auth)
        auth.attach(firestore: firestore)
        networkMonitor.attach(syncEngine: sync)
    }

    func configure(modelContext: ModelContext) {
        data = DataService(firestore: firestore, modelContext: modelContext, auth: auth, sync: sync)
        accountDeletion = AccountDeletionService(auth: auth, firestore: firestore, data: data)
        sync.configure(firestore: firestore, modelContext: modelContext, networkMonitor: networkMonitor, auth: auth)
    }
}

private struct AppServicesKey: EnvironmentKey {
    @MainActor
    static let defaultValue: AppServices = .shared
}

extension EnvironmentValues {
    var appServices: AppServices {
        get { self[AppServicesKey.self] }
        set { self[AppServicesKey.self] = newValue }
    }
}
