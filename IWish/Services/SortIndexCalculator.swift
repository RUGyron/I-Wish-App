import Foundation

enum SortIndexCalculator {
    static let initialStep: Double = 1000.0
    static let minGap: Double = 0.001

    /// Возвращает midpoint между двумя соседями. nil = край списка.
    static func midpoint(after lower: Double?, before upper: Double?) -> Double {
        switch (lower, upper) {
        case (nil, nil):
            return initialStep
        case let (l?, nil):
            return l + initialStep
        case let (nil, u?):
            return u - initialStep
        case let (l?, u?):
            return (l + u) / 2.0
        }
    }

    /// true если хотя бы одна пара соседних значений сблизилась меньше чем на minGap.
    static func needsRebalance(_ sortedIndexes: [Double]) -> Bool {
        guard sortedIndexes.count >= 2 else { return false }
        for i in 1..<sortedIndexes.count {
            if sortedIndexes[i] - sortedIndexes[i - 1] < minGap {
                return true
            }
        }
        return false
    }

    /// Возвращает последовательность 1000, 2000, ... step * count.
    static func rebalanced(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        return (1...count).map { Double($0) * initialStep }
    }
}
