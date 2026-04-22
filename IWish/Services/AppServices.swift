import SwiftUI
import SwiftData
import FirebaseAuth

@MainActor
final class AppServices {
    static let shared = AppServices()
    let auth = AuthService()
    let firestore = FirestoreService()
    var data: DataService!

    func configure(modelContext: ModelContext) {
        data = DataService(firestore: firestore, modelContext: modelContext, auth: auth)
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
