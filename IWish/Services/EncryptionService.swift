import Foundation
import CryptoKit

enum EncryptionError: LocalizedError {
    case invalidPayload
    case decryptionFailed
    case invalidFragment

    var errorDescription: String? {
        switch self {
        case .invalidPayload: return "Некорректные зашифрованные данные"
        case .decryptionFailed: return "Не удалось расшифровать"
        case .invalidFragment: return "Некорректный ключ в ссылке"
        }
    }
}

enum EncryptionService {

    // MARK: - Key generation / encoding

    static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    static func key(from data: Data) -> SymmetricKey {
        SymmetricKey(data: data)
    }

    /// URL-safe base64 (без `=`-padding, `+/` → `-_`) для fragment-параметра.
    static func keyFragment(_ key: SymmetricKey) -> String {
        keyData(key).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func key(fromFragment fragment: String) -> SymmetricKey? {
        var b64 = fragment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    // MARK: - Encrypt / decrypt JSON payloads

    /// Сериализует словарь content-полей в JSON, шифрует AES-GCM-256, возвращает combined (nonce+ciphertext+tag).
    /// Для бинарных полей (Data) кладите base64-строку — JSON Data напрямую не поддерживает.
    static func encrypt(_ payload: [String: Any], using key: SymmetricKey) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let sealed = try AES.GCM.seal(json, using: key)
        guard let combined = sealed.combined else {
            throw EncryptionError.invalidPayload
        }
        return combined
    }

    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> [String: Any] {
        let sealed = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(sealed, using: key)
        guard let dict = (try? JSONSerialization.jsonObject(with: plain)) as? [String: Any] else {
            throw EncryptionError.decryptionFailed
        }
        return dict
    }

    // MARK: - Convenience: pack/unpack content with optional Data fields

    /// Упаковка опциональных значений в payload — пропускает nil, конвертит Data в base64.
    static func packPayload(_ values: [String: Any?]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in values {
            guard let v else { continue }
            if let d = v as? Data {
                out[k] = d.base64EncodedString()
            } else {
                out[k] = v
            }
        }
        return out
    }

    /// Извлечь Data из base64-строки в payload.
    static func dataField(_ payload: [String: Any], _ key: String) -> Data? {
        guard let s = payload[key] as? String, !s.isEmpty else { return nil }
        return Data(base64Encoded: s)
    }
}
