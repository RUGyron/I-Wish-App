import UserNotifications
import CryptoKit

/// NotificationServiceExtension — обогащает push-уведомление названием желания.
///
/// E2E-инвариант: сервер (Cloud Function) НЕ знает расшифрованное имя желания. Он пробрасывает в
/// `data.encryptedName` короткое имя, зашифрованное ключом wishlist'а. Это расширение расшифровывает
/// его НА УСТРОЙСТВЕ ключом из shared Keychain (group `$(AppIdentifierPrefix)RUGyron.IWish.shared`)
/// и дописывает в текст уведомления фиксированной длины.
///
/// Любая ошибка / отсутствие ключа / таймаут → отдаём исходный текст (graceful degradation,
/// никакой потери данных и никаких падений).
///
/// Требования к таргету:
///  - В Target Membership добавить файлы `EncryptionService.swift` и `KeychainService.swift` из
///    основного приложения (расшарить исходники, не дублировать).
///  - Entitlement: keychain-access-groups → `$(AppIdentifierPrefix)RUGyron.IWish.shared`.
///  - Info.plist: NSExtensionPointIdentifier = com.apple.usernotifications.service,
///    NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).NotificationService.
final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    /// Максимальная длина имени желания в тексте уведа — фиксируем, чтобы баннер был
    /// предсказуемой длины (требование Влада: "длина чтобы была фиксированной").
    private let maxNameLength = 30

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let best = request.content.mutableCopy() as? UNMutableNotificationContent
        self.bestAttempt = best
        guard let best else { contentHandler(request.content); return }

        let info = request.content.userInfo
        guard let wishlistID = info["wishlistID"] as? String,
              let encB64 = info["encryptedName"] as? String,
              let combined = Data(base64Encoded: encB64),
              let key = KeychainService.load(for: wishlistID),
              let name = decryptName(combined, key: key) else {
            // Нет ключа/данных или не расшифровалось → исходный текст (как от сервера).
            contentHandler(best)
            return
        }

        let trimmed = truncate(name, max: maxNameLength)
        if !trimmed.isEmpty {
            best.body = "\(best.body) · \(trimmed)"
        }
        contentHandler(best)
    }

    override func serviceExtensionTimeWillExpire() {
        // Бюджет расширения вышел — отдаём лучший доступный вариант (исходный либо обогащённый).
        if let handler = contentHandler, let best = bestAttempt {
            handler(best)
        }
    }

    private func decryptName(_ data: Data, key: SymmetricKey) -> String? {
        guard let dict = try? EncryptionService.decrypt(data, using: key) else { return nil }
        let name = dict["n"] as? String
        return (name?.isEmpty == false) ? name : nil
    }

    private func truncate(_ s: String, max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max - 1)) + "…"
    }
}
