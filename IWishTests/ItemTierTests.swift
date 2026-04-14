import Testing
@testable import IWish

@Suite("ItemTier")
struct ItemTierTests {
    @Test("default tier is .maybe")
    func defaultIsMaybe() {
        #expect(ItemTier.defaultTier == .maybe)
    }

    @Test("each tier has unique SF Symbol name")
    func uniqueSymbolNames() {
        let symbols = Set(ItemTier.allCases.map(\.symbolName))
        #expect(symbols.count == ItemTier.allCases.count)
    }

    @Test("each tier has non-empty russian label")
    func labelsPresent() {
        for tier in ItemTier.allCases {
            #expect(!tier.label.isEmpty)
        }
    }

    @Test("rawValue round-trip")
    func rawValueRoundTrip() {
        for tier in ItemTier.allCases {
            #expect(ItemTier(rawValue: tier.rawValue) == tier)
        }
    }
}
