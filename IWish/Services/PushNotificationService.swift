import UIKit
import UserNotifications
import FirebaseMessaging
import FirebaseFirestore
import os.log

/// Push notifications: APNs registration + FCM token sync + handle taps.
///
/// Flow:
/// 1. Запрашиваем permission у юзера (опционально, после первого share).
/// 2. UIApplication регистрируется для APNs → AppDelegate proxy ловит device token.
/// 3. Firebase Messaging SDK получает APNs token + выдаёт FCM token.
/// 4. FCM token синкается в Firestore `users/{uid}/fcmTokens/{tokenHash}` чтобы Cloud Function
///    знала кому слать пуш.
/// 5. При тапе на push — `userNotificationCenter(_:didReceive:)` декодирует payload и роутит.
///
/// APNs key в Firebase Console должен быть загружен Владом (manual step):
/// Developer Portal → Keys → Create (Apple Push Notifications service) → скачать .p8 →
/// Firebase Console → Project Settings → Cloud Messaging → Apple app config → Upload APNs Auth Key.
@MainActor
@Observable
final class PushNotificationService: NSObject {
    private let log = Logger(subsystem: "RUGyron.IWish", category: "Push")

    /// Разрешил ли юзер уведомления (запоминаем для UI). Обновляется при `refreshAuthorizationStatus()`.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Последний известный FCM token. Используется для cleanup при sign out.
    private(set) var currentFCMToken: String?

    private weak var auth: AuthService?
    private var pendingDeeplink: PushDeeplink?
    private var deeplinkHandler: ((PushDeeplink) -> Void)?

    enum PushDeeplink: Equatable {
        case wishlist(id: String)
        case item(wishlistID: String, itemID: String)
    }

    override init() {
        super.init()
    }

    func attach(auth: AuthService) {
        self.auth = auth
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
    }

    /// Установить handler для deeplink при тапе на push. Если pending deeplink есть — вызвать сразу.
    func onDeeplink(_ handler: @escaping (PushDeeplink) -> Void) {
        deeplinkHandler = handler
        if let pending = pendingDeeplink {
            handler(pending)
            pendingDeeplink = nil
        }
    }

    /// Запросить разрешение у юзера. Возвращает granted.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            if granted {
                await registerForRemoteNotifications()
            }
            return granted
        } catch {
            log.error("requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Регистрируем UIApplication для remote notifications. Безопасно вызывать многократно.
    func registerForRemoteNotifications() async {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Auto-start при старте app.
    /// - Если granted → registerForRemoteNotifications.
    /// - Если notDetermined → автоматом просим permission (system показывает диалог).
    ///   Если юзер деклайнит — UI в Settings.notificationsSection показывает "Системные уведомления отключены".
    /// - Если denied → ничего не делаем, юзер должен включить в iOS Settings.
    func bootstrapIfAuthorized() async {
        await refreshAuthorizationStatus()
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            await registerForRemoteNotifications()
        case .notDetermined:
            // Auto-request при первом запуске. iOS показывает system dialog один раз.
            _ = await requestAuthorization()
        default:
            break // denied — оставляем на usability юзера через Settings
        }
    }

    // MARK: - AppDelegate callbacks

    /// Прокидывается из AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:).
    func didRegisterAPNs(token: Data) {
        Messaging.messaging().apnsToken = token
        log.info("APNs token registered: \(token.count, privacy: .public) bytes")
    }

    func didFailToRegisterAPNs(error: Error) {
        log.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Firestore sync

    private func syncFCMTokenToFirestore(_ token: String) async {
        guard let uid = auth?.uid, !uid.isEmpty else {
            log.debug("syncFCMToken: no uid, deferring")
            return
        }
        let db = Firestore.firestore()
        let hash = tokenHash(token)
        let ref = db.collection("users").document(uid).collection("fcmTokens").document(hash)
        do {
            try await ref.setData([
                "token": token,
                "platform": "ios",
                "updatedAt": FieldValue.serverTimestamp(),
                // App version хранится для будущей фильтрации (kill-switch старых клиентов).
                "appBuild": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            ], merge: true)
            log.info("FCM token synced for uid=\(uid, privacy: .public), hash=\(hash, privacy: .public)")
        } catch {
            log.error("FCM token sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Вызывать при заходе в приложение (scenePhase == .active):
    ///  - убирает доставленные уведы из Центра уведомлений (баг #5: висели после захода),
    ///  - обнуляет системный badge на иконке,
    ///  - обнуляет серверный unread-счётчик (users/{uid}.unreadCount), чтобы следующий пуш
    ///    считал badge с нуля. Идемпотентно; .active не дёргается при показе/закрытии sheet'ов.
    func clearDeliveredAndResetBadge() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        Task { try? await center.setBadgeCount(0) }
        guard let uid = auth?.uid, !uid.isEmpty else { return }
        let db = Firestore.firestore()
        Task {
            try? await db.collection("users").document(uid).setData(["unreadCount": 0], merge: true)
        }
    }

    /// Записывает глобальный тоггл уведомлений в users/{uid}.pushEnabled — CF фильтрует по нему.
    /// Best-effort: при отсутствии сети/uid просто no-op (значение подтянется при следующем вызове).
    func syncPushEnabledPreference(_ enabled: Bool) {
        guard let uid = auth?.uid, !uid.isEmpty else { return }
        let db = Firestore.firestore()
        Task {
            try? await db.collection("users").document(uid).setData(["pushEnabled": enabled], merge: true)
        }
    }

    /// Стирает FCM-токен из Firestore при sign-out. Не критично если упало — auth уже разлогинил.
    func removeFCMTokenOnSignOut() async {
        guard let uid = auth?.uid, !uid.isEmpty, let token = currentFCMToken else { return }
        let db = Firestore.firestore()
        let hash = tokenHash(token)
        try? await db.collection("users").document(uid).collection("fcmTokens").document(hash).delete()
        currentFCMToken = nil
    }

    private func tokenHash(_ token: String) -> String {
        // Простой стабильный hash для document-id (SwiftCrypto SHA-256 prefix).
        var h: UInt64 = 5381
        for byte in token.utf8 {
            h = ((h &<< 5) &+ h) &+ UInt64(byte)
        }
        return String(h, radix: 16)
    }

    // MARK: - Deeplink parsing

    /// Декодирует FCM payload в deeplink. Если payload содержит `wishlistID` + `itemID` →
    /// открываем item; если только `wishlistID` → wishlist; иначе nil.
    private func extractDeeplink(_ userInfo: [AnyHashable: Any]) -> PushDeeplink? {
        let wishlistID = (userInfo["wishlistID"] as? String) ?? (userInfo["wishlist_id"] as? String)
        let itemID = (userInfo["itemID"] as? String) ?? (userInfo["item_id"] as? String)
        if let wishlistID, !wishlistID.isEmpty {
            if let itemID, !itemID.isEmpty {
                return .item(wishlistID: wishlistID, itemID: itemID)
            }
            return .wishlist(id: wishlistID)
        }
        return nil
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Показываем баннер даже когда app foreground.
        completionHandler([.banner, .sound, .badge, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler()
                return
            }
            if let deeplink = self.extractDeeplink(userInfo) {
                if let handler = self.deeplinkHandler {
                    handler(deeplink)
                } else {
                    self.pendingDeeplink = deeplink
                }
            }
            completionHandler()
        }
    }
}

// MARK: - MessagingDelegate

extension PushNotificationService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentFCMToken = fcmToken
            self.log.info("FCM token received, length=\(fcmToken.count, privacy: .public)")
            await self.syncFCMTokenToFirestore(fcmToken)
        }
    }
}
