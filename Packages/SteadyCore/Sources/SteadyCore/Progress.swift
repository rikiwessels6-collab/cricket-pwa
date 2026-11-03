import Foundation

// Weight trend and check-in maths. Plain numbers in, plain numbers out, so it can be tested.

public struct WeightPoint: Equatable, Sendable {
    public var date: Date
    public var kg: Double
    public init(date: Date, kg: Double) { self.date = date; self.kg = kg }
}

public enum WeightTrend {
    /// A smoothed line through noisy weigh-ins. Each new reading pulls the line towards it by an amount that
    /// depends on how long it has been since the last one (half-life in days), so daily water changes don't dominate.
    public static func smoothed(_ points: [WeightPoint], halfLifeDays: Double = 7) -> [WeightPoint] {
        let sorted = points.sorted { $0.date < $1.date }
        guard var current = sorted.first?.kg else { return [] }
        var out = [WeightPoint(date: sorted[0].date, kg: current)]
        for (prev, p) in zip(sorted, sorted.dropFirst()) {
            let days = max(0, p.date.timeIntervalSince(prev.date) / 86_400)
            let alpha = 1 - pow(0.5, days / halfLifeDays)
            current += alpha * (p.kg - current)
            out.append(WeightPoint(date: p.date, kg: current))
        }
        return out
    }

    /// Kilograms per week from a straight-line fit over the last `days` days. Nil unless there are at least
    /// three weigh-ins spread over at least a week, because less than that says nothing reliable.
    public static func weeklyChange(_ points: [WeightPoint], days: Double = 28, now: Date = .now) -> Double? {
        let cutoff = now.addingTimeInterval(-days * 86_400)
        let recent = points.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        guard recent.count >= 3, let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) >= 7 * 86_400 else { return nil }
        let xs = recent.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = recent.map(\.kg)
        let n = Double(recent.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        return sxy / sxx * 7
    }

    /// Neutral wording. No praise or blame; weight is only one signal.
    public static func describe(weeklyChange: Double?) -> String {
        guard let w = weeklyChange else { return "Add a few weigh-ins over a couple of weeks to see your trend." }
        if abs(w) < 0.1 { return "Steady over the last four weeks." }
        let amount = String(format: "%.1f", abs(w))
        return w > 0 ? "Up about \(amount) kg a week over the last four weeks." : "Down about \(amount) kg a week over the last four weeks."
    }
}

public enum CheckInMath {
    /// Sum of the tape measurements entered (cm). Missing sites are simply left out.
    public static func measurementTotal(_ values: [String: Double]) -> Double {
        values.values.filter { $0 > 0 }.reduce(0, +)
    }

    /// Whether this week's check-in is still to do: the latest occurrence of the check-in weekday
    /// (today counts) is newer than the last check-in. Weekday: 1 = Sunday ... 7 = Saturday.
    public static func isDue(weekday: Int, lastCheckIn: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let today = calendar.component(.weekday, from: now)
        let back = (today - weekday + 7) % 7
        guard let latest = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now)) else { return false }
        guard let last = lastCheckIn else { return true }
        return last < latest
    }
}
