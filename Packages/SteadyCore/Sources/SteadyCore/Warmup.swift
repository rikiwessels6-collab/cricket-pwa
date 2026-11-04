import Foundation

/// Warm-up sets before a heavy lift. A guide only: skip or change any of it.
public enum Warmup {
    public enum Style: String, CaseIterable, Sendable, Identifiable {
        case percent, ramp
        public var id: String { rawValue }
        public var label: String { self == .percent ? "Percent of working weight" : "Even ramp up" }
    }

    public static let percents: [(percent: Double, reps: Int)] = [(0.45, 5), (0.65, 3), (0.85, 2)]

    /// Warm-up sets (weight and reps) that end below the working weight. Weights are rounded down to `increment`
    /// and never go below the empty bar.
    public static func sets(style: Style, working: Double, bar: Double = 20, increment: Double = 2.5) -> [LoggedSet] {
        guard working > bar else { return [] }
        switch style {
        case .ramp:
            return Progression.warmupSets(working: working, barWeight: bar)
        case .percent:
            var out: [LoggedSet] = []
            for step in percents {
                let w = max(bar, Progression.roundDown(working * step.percent, to: increment))
                if w < working, w > (out.last?.weight ?? 0) { out.append(LoggedSet(weight: w, reps: step.reps)) }
            }
            return out
        }
    }
}
