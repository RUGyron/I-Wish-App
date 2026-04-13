import Testing
import Foundation
@testable import IWish

@Suite("DefaultCoverGenerator")
struct DefaultCoverGeneratorTests {
    @Test("same UUID always returns same palette")
    func deterministic() {
        let id = UUID()
        let first = DefaultCoverGenerator.paletteIndex(for: id)
        let second = DefaultCoverGenerator.paletteIndex(for: id)
        #expect(first == second)
    }

    @Test("different UUIDs distribute across palettes")
    func distribution() {
        var seen = Set<Int>()
        for _ in 0..<200 {
            seen.insert(DefaultCoverGenerator.paletteIndex(for: UUID()))
        }
        // С 200 UUID и 8 палитрами вероятность увидеть <4 разных — околонулевая.
        #expect(seen.count >= 4)
    }

    @Test("palette index in valid range")
    func validRange() {
        for _ in 0..<50 {
            let idx = DefaultCoverGenerator.paletteIndex(for: UUID())
            #expect(idx >= 0)
            #expect(idx < DefaultCoverGenerator.paletteCount)
        }
    }
}
