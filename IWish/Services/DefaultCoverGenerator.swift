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

    /// Детерминированный индекс палитры по UUID. Стабильный между запусками.
    static func paletteIndex(for id: UUID) -> Int {
        let bytes = withUnsafeBytes(of: id.uuid) { Data($0) }
        let sum = bytes.reduce(into: 0) { $0 = ($0 &+ Int($1)) }
        return abs(sum) % palettes.count
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
