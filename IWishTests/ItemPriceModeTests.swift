import Testing
@testable import IWish

@Suite("ItemPriceMode")
struct ItemPriceModeTests {
    @Test("none when both nil")
    func priceModeNone() {
        let item = Item(name: "X", price: nil, priceMax: nil)
        if case .none = item.priceMode {
            // OK
        } else {
            Issue.record("Expected .none")
        }
    }

    @Test("exact when only price")
    func priceModeExact() {
        let item = Item(name: "X", price: 1000, priceMax: nil)
        guard case .exact(let p) = item.priceMode else {
            Issue.record("Expected .exact")
            return
        }
        #expect(p == 1000)
    }

    @Test("range when both present")
    func priceModeRange() {
        let item = Item(name: "X", price: 500, priceMax: 1500)
        guard case .range(let min, let max) = item.priceMode else {
            Issue.record("Expected .range")
            return
        }
        #expect(min == 500)
        #expect(max == 1500)
    }

    @Test("range swaps when min > max")
    func priceModeSwaps() {
        let item = Item(name: "X", price: 1500, priceMax: 500)
        guard case .range(let min, let max) = item.priceMode else {
            Issue.record("Expected .range")
            return
        }
        #expect(min == 500)
        #expect(max == 1500)
    }
}
