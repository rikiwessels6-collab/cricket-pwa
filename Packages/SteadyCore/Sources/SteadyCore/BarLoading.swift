import Foundation

/// A kind of plate you own: its weight and how many PAIRS you have.
public struct PlateStock: Equatable, Sendable, Identifiable {
    public var weight: Double
    public var pairs: Int
    public var id: Double { weight }
    public init(weight: Double, pairs: Int) { self.weight = weight; self.pairs = pairs }
}

public struct PlateCount: Equatable, Sendable, Identifiable {
    public var weight: Double
    public var count: Int
    public var id: Double { weight }
}

public struct BarLoad: Equatable, Sendable {
    /// Plates for ONE side, heaviest first.
    public var perSide: [PlateCount]
    /// Bar plus plates on both sides.
    public var loaded: Double
    /// What is still missing from the target (never negative).
    public var shortfall: Double
    public var isExact: Bool { shortfall < 0.001 }
}

public enum BarLoading {
    public static let defaultStock: [PlateStock] = [
        PlateStock(weight: 25, pairs: 4), PlateStock(weight: 20, pairs: 2), PlateStock(weight: 15, pairs: 2),
        PlateStock(weight: 10, pairs: 4), PlateStock(weight: 5, pairs: 4), PlateStock(weight: 2.5, pairs: 4),
        PlateStock(weight: 1.25, pairs: 2),
    ]

    /// The plates for a target total weight, heaviest plates first. If the target can't be made exactly
    /// with the plates you have, this loads as much as it can and reports the shortfall.
    public static func load(target: Double, bar: Double, stock: [PlateStock]) -> BarLoad {
        guard target > bar else { return BarLoad(perSide: [], loaded: bar, shortfall: max(0, target - bar)) }
        var remaining = (target - bar) / 2
        var out: [PlateCount] = []
        for plate in stock.filter({ $0.weight > 0 && $0.pairs > 0 }).sorted(by: { $0.weight > $1.weight }) {
            let n = min(plate.pairs, Int((remaining / plate.weight) + 1e-9))
            if n > 0 {
                out.append(PlateCount(weight: plate.weight, count: n))
                remaining -= Double(n) * plate.weight
            }
        }
        let perSideLoaded = out.reduce(0) { $0 + $1.weight * Double($1.count) }
        return BarLoad(perSide: out, loaded: bar + 2 * perSideLoaded, shortfall: max(0, remaining * 2))
    }
}
