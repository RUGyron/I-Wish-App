import SwiftUI

@MainActor
final class AppServices {
    static let shared = AppServices()
    let syncStatus = SyncStatusService()
    let userProfile = UserProfileService()
    let sharing = CloudKitSharingService()
    let sharedSync = SharedWishlistSyncService()
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
