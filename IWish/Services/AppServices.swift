import SwiftUI
import FirebaseAuth

@MainActor
final class AppServices {
    static let shared = AppServices()
    let auth = AuthService()
    let firestore = FirestoreService()
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
