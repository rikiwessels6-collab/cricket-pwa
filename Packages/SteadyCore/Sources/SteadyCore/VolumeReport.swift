import Foundation

/// Where a muscle's weekly direct sets sit against a general guide. A guide, not a rule: it depends on the person.
public enum VolumeBand: String, Sendable, Equatable {
    case none, low, inRange, high
}

public struct MuscleWeek: Equatable, Sendable, Identifiable {
    public var muscle: String
    public var direct: Double
    public var indirect: Double
    public var band: VolumeBand
    public var id: String { muscle }
}

public enum VolumeReport {
    /// A common guide for hypertrophy: roughly 10 to 20 hard sets per muscle per week.
    public static let lowerTarget = 10.0
    public static let upperTarget = 20.0

    public static func band(direct: Double, low: Double = lowerTarget, high: Double = upperTarget) -> VolumeBand {
        if direct <= 0 { return .none }
        if direct < low { return .low }
        if direct > high { return .high }
        return .inRange
    }

    /// One row per muscle in `muscles` (even if untrained), most direct sets first, then by name.
    public static func week(setCounts: [String: Int], library: [String: Exercise], muscles: [String],
                            rules: RuleSet = RuleSet()) -> [MuscleWeek] {
        let volume = WeeklyVolume.compute(setCounts: setCounts, library: library, rules: rules)
        var ids = muscles
        for m in volume.keys where !ids.contains(m) { ids.append(m) }
        return ids.map { m in
            let v = volume[m] ?? MuscleVolume()
            return MuscleWeek(muscle: m, direct: v.direct, indirect: v.indirect, band: band(direct: v.direct))
        }
        .sorted { ($0.direct, $1.muscle) > ($1.direct, $0.muscle) }
    }

    /// "upper_chest" becomes "Upper chest".
    public static func prettyName(_ muscle: String) -> String {
        let spaced = muscle.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    /// The start of the calendar week containing `date`, and the start of the next one.
    public static func weekRange(containing date: Date, weeksBack: Int = 0, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: date)
        let start = thisWeek?.start ?? calendar.startOfDay(for: date)
        let shifted = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: start) ?? start
        let end = calendar.date(byAdding: .weekOfYear, value: 1, to: shifted) ?? shifted
        return (shifted, end)
    }
}
