import Testing
@testable import IWish

@Suite("ItemTier")
struct ItemTierTests {
    @Test("default tier is .maybe")
    func defaultIsMaybe() {
        #expect(ItemTier.defaultTier == .maybe)
    }

    @Test("each tier has unique icon")
    func uniqueIcons() {
        let icons = Set(ItemTier.allCases.map(\.icon))
        #expect(icons.count == ItemTier.allCases.count)
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
