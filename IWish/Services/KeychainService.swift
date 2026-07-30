import Foundation
import Security
import CryptoKit
import os.log

private let kcLog = Logger(subsystem: "RUGyron.IWish", category: "Keychain")

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let s): return String(format: String(localized: "Keychain error: %d"), Int(s))
        }
    }
}

/// iCloud-синхронизируемый Keychain для AES-ключей wishlist'ов.
/// `kSecAttrSynchronizable: true` → Apple end-to-end синкает ключи между девайсами одного Apple ID.
/// Apple ключи видит только зашифрованными; разраб (Firebase Console) — не имеет к ним доступа.
enum KeychainService {

    private static let service = "RUGyron.IWish.WishlistKeys"
    fileprivate static let userProfileService = "RUGyron.IWish.UserProfile"

    /// Shared keychain access group для расшаривания ключей с NotificationServiceExtension
    /// (NSE расшифровывает имя желания на устройстве). Должен совпадать с entitlement
    /// `keychain-access-groups` → `$(AppIdentifierPrefix)RUGyron.IWish.shared` (team N8VX7T6P4D).
    private static let sharedAccessGroup = "N8VX7T6P4D.RUGyron.IWish.shared"

    /// Сохранить ключ wishlist в iCloud Keychain.
    static func save(key: SymmetricKey, for wishlistID: String) throws {
        let data = key.withUnsafeBytes { Data($0) }

        // Удалить существующий (любой synchronizable атрибут) перед записью
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: wishlistID,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: wishlistID,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            kcLog.error("Keychain save failed: \(status) for \(wishlistID, privacy: .public)")
            throw KeychainError.unexpectedStatus(status)
        }

        // Дублируем ключ в shared access group, чтобы NSE мог его прочитать. Best-effort:
        // оригинал в дефолтной группе НЕ трогаем (app читает ключ из любой своей группы), поэтому
        // даже если копия не запишется (entitlement/provisioning не настроены) — потери ключа нет.
        copyToSharedGroup(data: data, wishlistID: wishlistID)
    }

    /// Аддитивно кладёт копию ключа в shared access group. НЕ удаляет оригинал.
    /// errSecDuplicateItem (уже скопирован) и errSecMissingEntitlement (группа не настроена) — норма.
    /// Возвращает OSStatus для определения, доступна ли группа (нужно для one-time флага миграции).
    @discardableResult
    private static func copyToSharedGroup(data: Data, wishlistID: String) -> OSStatus {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: wishlistID,
            kSecAttrAccessGroup as String: sharedAccessGroup,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess && status != errSecDuplicateItem {
            kcLog.debug("copyToSharedGroup non-fatal status \(status) for \(wishlistID, privacy: .public)")
        }
        return status
    }

    /// One-time миграция: копирует ключи существующих wishlist'ов в shared access group,
    /// чтобы NSE показывал имя желания и для списков, созданных до внедрения NSE.
    /// Безопасно — только аддитивные копии, оригиналы остаются.
    /// Возвращает false если shared access group ещё не настроена (entitlement отсутствует) —
    /// тогда миграцию нужно повторить позже (caller не ставит one-time флаг).
    @discardableResult
    static func migrateKeysToSharedGroup(wishlistIDs: [String]) -> Bool {
        var entitlementOK = true
        for id in wishlistIDs {
            guard let key = load(for: id) else { continue }
            let data = key.withUnsafeBytes { Data($0) }
            if copyToSharedGroup(data: data, wishlistID: id) == errSecMissingEntitlement {
                entitlementOK = false
            }
        }
        return entitlementOK
    }

    /// Загрузить ключ wishlist (если есть на этом девайсе или подтянулся из iCloud).
    static func load(for wishlistID: String) -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: wishlistID,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            return nil
        }
        return SymmetricKey(data: data)
    }

    /// Удалить ключ wishlist (на всех Apple ID девайсах через iCloud).
    static func delete(for wishlistID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: wishlistID,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Полная очистка (для wipe при логауте/reset). Удаляет все ключи приложения.
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)

        let profileQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: userProfileService,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(profileQuery as CFDictionary)
    }
}

extension KeychainService {

    /// Сохранить displayName юзера в iCloud Keychain (sync между Apple ID девайсами).
    static func saveUserName(_ name: String) {
        let data = Data(name.utf8)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: userProfileService,
            kSecAttrAccount as String: "displayName",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: userProfileService,
            kSecAttrAccount as String: "displayName",
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        _ = SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Загрузить displayName юзера (sync между Apple ID девайсами через iCloud Keychain).
    static func loadUserName() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: userProfileService,
            kSecAttrAccount as String: "displayName",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Удалить displayName юзера (на всех Apple ID девайсах через iCloud).
    static func deleteUserName() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: userProfileService,
            kSecAttrAccount as String: "displayName",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }
}
