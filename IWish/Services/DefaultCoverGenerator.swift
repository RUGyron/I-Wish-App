import SwiftUI

enum DefaultCoverGenerator {
    /// Палитры из 3 цветов каждая. Подобраны для соответствия Apple system colors.
    static let palettes: [[Color]] = [
        [.blue, .indigo, .purple],
        [.orange, .pink, .red],
        [.green, .mint, .teal],
        [.purple, .pink, .red],
        [.cyan, .blue, .indigo],
        [.yellow, .orange, .red],
        [.mint, .teal, .cyan],
        [.indigo, .purple, .pink],
    ]

    static var paletteCount: Int { palettes.count }

    /// Стабильный хеш строки — одинаковый на всех устройствах и запусках.
    /// Swift .hashValue нестабилен (random seed per process).
    static func stableHash(_ string: String) -> Int {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte) // djb2
        }
        return Int(hash & 0x7FFFFFFFFFFFFFFF)
    }

    /// Детерминированный индекс палитры по UUID. Стабильный между запусками.
    static func paletteIndex(for id: UUID) -> Int {
        abs(stableHash(id.uuidString)) % palettes.count
    }

    /// Возвращает 3 цвета для данного UUID.
    static func colors(for id: UUID) -> [Color] {
        palettes[paletteIndex(for: id)]
    }

    /// Детерминированный индекс палитры по gradientSeed.
    static func paletteIndex(forSeed seed: Int) -> Int {
        abs(seed) % palettes.count
    }

    /// Возвращает 3 цвета для данного gradientSeed.
    static func colors(forSeed seed: Int) -> [Color] {
        palettes[paletteIndex(forSeed: seed)]
    }
}
