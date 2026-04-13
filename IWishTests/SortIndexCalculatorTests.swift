import Testing
@testable import IWish

@Suite("SortIndexCalculator")
struct SortIndexCalculatorTests {
    @Test("midpoint between two values")
    func midpointBetween() {
        #expect(SortIndexCalculator.midpoint(after: 1000, before: 2000) == 1500)
    }

    @Test("midpoint when no upper neighbor — append step")
    func midpointAppend() {
        #expect(SortIndexCalculator.midpoint(after: 5000, before: nil) == 6000)
    }

    @Test("midpoint when no lower neighbor — prepend step")
    func midpointPrepend() {
        #expect(SortIndexCalculator.midpoint(after: nil, before: 1000) == 0)
    }

    @Test("midpoint when list is empty — initial step")
    func midpointEmpty() {
        #expect(SortIndexCalculator.midpoint(after: nil, before: nil) == 1000)
    }

    @Test("needsRebalance is false for spaced values")
    func noRebalanceForSpaced() {
        #expect(!SortIndexCalculator.needsRebalance([1000, 2000, 3000]))
    }

    @Test("needsRebalance is true for collapsing values")
    func rebalanceForCollapsed() {
        #expect(SortIndexCalculator.needsRebalance([1000, 1000.0001, 2000]))
    }

    @Test("rebalanced returns step-spaced sequence")
    func rebalancedSequence() {
        #expect(SortIndexCalculator.rebalanced(count: 3) == [1000, 2000, 3000])
    }

    @Test("rebalanced of zero returns empty")
    func rebalancedZero() {
        #expect(SortIndexCalculator.rebalanced(count: 0) == [])
    }
}
