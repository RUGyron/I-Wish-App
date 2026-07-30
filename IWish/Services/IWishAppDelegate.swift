import UIKit
import os.log

/// Минимальный UIApplicationDelegate для прокидывания APNs callbacks в PushNotificationService.
/// SwiftUI App не имеет нативных UIApplicationDelegate-методов, поэтому используем proxy через
/// `@UIApplicationDelegateAdaptor` в IWishApp.
final class IWishAppDelegate: NSObject, UIApplicationDelegate {
    private let log = Logger(subsystem: "RUGyron.IWish", category: "AppDelegate")

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            AppServices.shared.push.didRegisterAPNs(token: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            AppServices.shared.push.didFailToRegisterAPNs(error: error)
        }
    }
}
