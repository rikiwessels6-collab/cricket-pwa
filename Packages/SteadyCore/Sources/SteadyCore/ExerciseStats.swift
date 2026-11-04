import Foundation

/// One logged set, reduced to what the charts need.
public struct StatSet: Equatable, Sendable {
    public var date: Date
    public var weight: Double
    public var reps: Int
    public init(date: Date, weight: Double, reps: Int) { self.date = date; self.weight = weight; self.reps = reps }
}

/// One exercise on one day.
public struct SessionStat: Equatable, Sendable, Identifiable {
    public var date: Date
    public var topWeight: Double
    public var estimatedOneRepMax: Double
    public var volume: Double
    public var bestReps: Int
    public var id: Date { date }
}

public enum StatMetric: String, CaseIterable, Sendable, Identifiable {
    case weight, oneRepMax, volume, reps
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .weight: return "Weight"
        case .oneRepMax: return "Est. 1RM"
        case .volume: return "Volume"
        case .reps: return "Reps"
        }
    }
    public func value(_ s: SessionStat) -> Double {
        switch self {
        case .weight: return s.topWeight
        case .oneRepMax: return s.estimatedOneRepMax
        case .volume: return s.volume
        case .reps: return Double(s.bestReps)
        }
    }
}

public enum StatRange: String, CaseIterable, Sendable, Identifiable {
    case threeMonths, sixMonths, year, all
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .year: return "1Y"
        case .all: return "All"
        }
    }
    var days: Int? {
        switch self {
        case .threeMonths: return 92
        case .sixMonths: return 183
        case .year: return 366
        case .all: return nil
        }
    }
}

public enum ExerciseStats {
    /// Estimated 1RM only trusts sets of up to 12 reps; higher-rep sets say little about a one-rep max.
    static let maxRepsForEstimate = 12

    /// Groups sets by calendar day, oldest first. Sets with no reps are ignored.
    public static func sessions(_ sets: [StatSet], calendar: Calendar = .current) -> [SessionStat] {
        let valid = sets.filter { $0.reps > 0 }
        let byDay = Dictionary(grouping: valid) { calendar.startOfDay(for: $0.date) }
        return byDay.map { day, list in
            let est = list.filter { $0.reps <= maxRepsForEstimate }.map { Strength.epley(weight: $0.weight, reps: $0.reps) }.max() ?? 0
            return SessionStat(date: day,
                               topWeight: list.map(\.weight).max() ?? 0,
                               estimatedOneRepMax: est,
                               volume: list.reduce(0) { $0 + $1.weight * Double($1.reps) },
                               bestReps: list.map(\.reps).max() ?? 0)
        }
        .sorted { $0.date < $1.date }
    }

    /// The best day for heaviest weight and for estimated 1RM. Earliest day wins a tie.
    public static func records(_ sessions: [SessionStat]) -> (weight: SessionStat?, oneRepMax: SessionStat?) {
        var w: SessionStat?, e: SessionStat?
        for s in sessions {
            if s.topWeight > (w?.topWeight ?? 0) { w = s }
            if s.estimatedOneRepMax > (e?.estimatedOneRepMax ?? 0) { e = s }
        }
        return (w, e)
    }

    public static func filter(_ sessions: [SessionStat], range: StatRange, now: Date = .now) -> [SessionStat] {
        guard let days = range.days else { return sessions }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return sessions.filter { $0.date >= cutoff }
    }
}
