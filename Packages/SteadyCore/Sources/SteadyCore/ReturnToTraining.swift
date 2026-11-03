import Foundation

/// After a long gap the app offers (never forces) a lighter first session. Missing sessions is not a failure:
/// the next session in the program simply stays next.
public struct ReturnAdvice: Equatable, Sendable {
    public var daysAway: Int
    public var loadFactor: Double
    public var message: String
    public var code: ReasonCode { .missedReturnReduction }
}

public enum ReturnToTraining {
    public static let thresholdDays = 14
    public static let longGapDays = 28

    public static func advice(lastSession: Date?, now: Date = .now, calendar: Calendar = .current) -> ReturnAdvice? {
        guard let last = lastSession else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
        guard days >= thresholdDays else { return nil }
        var message = "It's been \(days) days since your last session. Starting about 10% lighter is a sensible way back in. You can switch this off."
        if days >= longGapDays { message += " After a longer break, the Low energy version is a gentle first session." }
        return ReturnAdvice(daysAway: days, loadFactor: 0.9, message: message)
    }
}
