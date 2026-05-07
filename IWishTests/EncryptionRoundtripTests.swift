import Testing
import Foundation
import CryptoKit
@testable import IWish

@Suite("EncryptionRoundtrip")
struct EncryptionRoundtripTests {
    @Test("v1.1 payload roundtrip preserves all new fields")
    func roundtripV11Fields() throws {
        let key = EncryptionService.generateKey()
        let original: [String: Any] = [
            "name": "Mac Studio",
            "tier": "must",
            "price": 250000.0,
            "priceMax": 350000.0,
            "currency": "RUB",
            "url": "https://apple.com",
            "coverEmoji": "💻",
            "description": "Хочу самый топ M3 Ultra",
            "addedByUID": "uid123",
            "addedByName": "Влад"
        ]
        let encrypted = try EncryptionService.encrypt(original, using: key)
        let decrypted = try EncryptionService.decrypt(encrypted, using: key)

        #expect(decrypted["name"] as? String == "Mac Studio")
        #expect(decrypted["price"] as? Double == 250000.0)
        #expect(decrypted["priceMax"] as? Double == 350000.0)
        #expect(decrypted["description"] as? String == "Хочу самый топ M3 Ultra")
        #expect(decrypted["addedByName"] as? String == "Влад")
    }

    @Test("payload with unknown future keys decrypts without loss")
    func forwardCompatUnknownKeys() throws {
        let key = EncryptionService.generateKey()
        let payload: [String: Any] = [
            "name": "Test",
            "tier": "maybe",
            "newFutureField_v1_2": "some-value",
            "another_unknown": 42
        ]
        let encrypted = try EncryptionService.encrypt(payload, using: key)
        let decrypted = try EncryptionService.decrypt(encrypted, using: key)
        #expect(decrypted["name"] as? String == "Test")
        #expect(decrypted["newFutureField_v1_2"] as? String == "some-value")
        #expect((decrypted["another_unknown"] as? Int) == 42)
    }

    @Test("Data fields packed via packPayload roundtrip via dataField")
    func dataFieldRoundtrip() throws {
        let key = EncryptionService.generateKey()
        let imageBytes = Data((0..<200).map { _ in UInt8.random(in: 0...255) })

        let payload = EncryptionService.packPayload([
            "name": "Photo item",
            "coverImageData": imageBytes
        ])
        let encrypted = try EncryptionService.encrypt(payload, using: key)
        let decrypted = try EncryptionService.decrypt(encrypted, using: key)

        let restored = EncryptionService.dataField(decrypted, "coverImageData")
        #expect(restored == imageBytes)
    }
}
