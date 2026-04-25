import SwiftUI

enum DefaultCoverGenerator {
    /// 24 палитры из 3 цветов. Разнообразные, контрастные, подобраны вручную.
    static let palettes: [[Color]] = [
        // Cool
        [.blue, .indigo, .purple],
        [.cyan, .blue, .indigo],
        [.mint, .teal, .cyan],
        [.teal, .blue, .purple],
        [Color(red: 0.2, green: 0.4, blue: 0.8), Color(red: 0.4, green: 0.2, blue: 0.9), Color(red: 0.6, green: 0.3, blue: 1.0)],
        [Color(red: 0.0, green: 0.6, blue: 0.7), Color(red: 0.1, green: 0.4, blue: 0.8), Color(red: 0.3, green: 0.2, blue: 0.7)],

        // Warm
        [.orange, .pink, .red],
        [.yellow, .orange, .red],
        [.pink, .red, .purple],
        [Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 1.0, green: 0.3, blue: 0.3), Color(red: 0.8, green: 0.2, blue: 0.5)],
        [Color(red: 0.9, green: 0.7, blue: 0.1), Color(red: 1.0, green: 0.5, blue: 0.0), Color(red: 0.9, green: 0.3, blue: 0.1)],
        [Color(red: 0.95, green: 0.4, blue: 0.5), Color(red: 0.85, green: 0.2, blue: 0.6), Color(red: 0.7, green: 0.15, blue: 0.7)],

        // Earth & Nature
        [.green, .mint, .teal],
        [Color(red: 0.2, green: 0.7, blue: 0.3), Color(red: 0.1, green: 0.5, blue: 0.5), Color(red: 0.0, green: 0.4, blue: 0.6)],
        [Color(red: 0.6, green: 0.8, blue: 0.2), Color(red: 0.3, green: 0.7, blue: 0.4), Color(red: 0.1, green: 0.6, blue: 0.6)],
        [Color(red: 0.5, green: 0.35, blue: 0.2), Color(red: 0.7, green: 0.45, blue: 0.2), Color(red: 0.85, green: 0.6, blue: 0.3)],

        // Pastel
        [Color(red: 0.7, green: 0.85, blue: 1.0), Color(red: 0.85, green: 0.7, blue: 1.0), Color(red: 1.0, green: 0.75, blue: 0.85)],
        [Color(red: 1.0, green: 0.85, blue: 0.7), Color(red: 1.0, green: 0.7, blue: 0.75), Color(red: 0.9, green: 0.7, blue: 0.9)],
        [Color(red: 0.7, green: 1.0, blue: 0.85), Color(red: 0.7, green: 0.9, blue: 1.0), Color(red: 0.8, green: 0.75, blue: 1.0)],

        // Vivid
        [.indigo, .purple, .pink],
        [Color(red: 1.0, green: 0.0, blue: 0.5), Color(red: 0.8, green: 0.0, blue: 1.0), Color(red: 0.4, green: 0.0, blue: 1.0)],
        [Color(red: 0.0, green: 0.8, blue: 1.0), Color(red: 0.0, green: 1.0, blue: 0.6), Color(red: 0.4, green: 1.0, blue: 0.2)],

        // Dark & Moody
        [Color(red: 0.15, green: 0.1, blue: 0.3), Color(red: 0.3, green: 0.1, blue: 0.4), Color(red: 0.5, green: 0.15, blue: 0.5)],
        [Color(red: 0.1, green: 0.2, blue: 0.3), Color(red: 0.15, green: 0.3, blue: 0.4), Color(red: 0.2, green: 0.4, blue: 0.5)],
        [Color(red: 0.3, green: 0.1, blue: 0.1), Color(red: 0.5, green: 0.15, blue: 0.1), Color(red: 0.7, green: 0.25, blue: 0.15)],
    ]

    static var paletteCount: Int { palettes.count }

    /// Стабильный хеш строки — одинаковый на всех устройствах и запусках.
    static func stableHash(_ string: String) -> Int {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash & 0x7FFFFFFFFFFFFFFF)
    }

    static func paletteIndex(for id: UUID) -> Int {
        abs(stableHash(id.uuidString)) % palettes.count
    }

    static func colors(for id: UUID) -> [Color] {
        palettes[paletteIndex(for: id)]
    }

    static func paletteIndex(forSeed seed: Int) -> Int {
        abs(seed) % palettes.count
    }

    static func colors(forSeed seed: Int) -> [Color] {
        palettes[paletteIndex(forSeed: seed)]
    }
}
