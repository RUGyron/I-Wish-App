import Foundation
import Security
import CryptoKit
import os.log

private let kcLog = Logger(subsystem: "RUGyron.IWish", category: "Keychain")

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let s): return "Keychain ошибка: \(s)"
        }
    }
}

/// iCloud-синхронизируемый Keychain для AES-ключей wishlist'ов.
/// `kSecAttrSynchronizable: true` → Apple end-to-end синкает ключи между девайсами одного Apple ID.
/// Apple ключи видит только зашифрованными; разраб (Firebase Console) — не имеет к ним доступа.
enum KeychainService {

    private static let service = "RUGyron.IWish.WishlistKeys"

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
    }
}
