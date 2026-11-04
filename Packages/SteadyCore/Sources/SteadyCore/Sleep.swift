import Foundation

/// Sleep per night, from the asleep periods Apple Health reports. Watches and phones can both record the same
/// night, so overlapping periods are merged first and never counted twice.
public struct SleepNight: Equatable, Sendable, Identifiable {
    /// The day the night STARTED (the evening you went to bed).
    public var night: Date
    public var hours: Double
    public var id: Date { night }
    public init(night: Date, hours: Double) { self.night = night; self.hours = hours }
}

public enum SleepMath {
    /// Groups asleep periods into nights. A period belongs to the night that began in the 12 hours before it ended,
    /// so 23:00 to 07:00 counts as one night. Daytime naps land in that day's bucket and are small.
    public static func nights(_ intervals: [DateInterval], calendar: Calendar = .current) -> [SleepNight] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        var buckets: [Date: TimeInterval] = [:]
        for m in merged {
            let key = calendar.startOfDay(for: m.end.addingTimeInterval(-12 * 3600))
            buckets[key, default: 0] += m.duration
        }
        return buckets.map { SleepNight(night: $0.key, hours: $0.value / 3600) }.sorted { $0.night < $1.night }
    }

    /// Average hours over nights of at least `minHours` (so a short nap doesn't drag the average down). Nil if none.
    public static func average(_ nights: [SleepNight], minHours: Double = 2) -> Double? {
        let valid = nights.filter { $0.hours >= minHours }
        guard !valid.isEmpty else { return nil }
        return valid.map(\.hours).reduce(0, +) / Double(valid.count)
    }
}
