import Foundation

public enum Strength {
    /// Epley estimated one-rep max: weight x (1 + reps / 30); a single is itself.
    public static func epley(weight: Double, reps: Int) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    /// Load for a %1RM prescription, rounded down to the nearest plate jump.
    public static func load(percent: Double, oneRepMax: Double, increment: Double = 2.5) -> Double {
        let raw = percent * oneRepMax
        guard increment > 0 else { return raw }
        return (raw / increment + 1e-9).rounded(.down) * increment
    }

    /// The lifts a %1RM program needs, with display names.
    public static let oneRepMaxLifts: [(id: String, name: String)] = [
        ("squat", "Squat"), ("bench", "Bench press"), ("deadlift", "Deadlift"), ("ohp", "Overhead press"),
    ]
}

public enum Experience: String, Codable, CaseIterable, Sendable {
    case new, returning, intermediate, advanced

    public var label: String {
        switch self {
        case .new: return "New to lifting"
        case .returning: return "Returning after a break"
        case .intermediate: return "Lifting consistently for 1-3 years"
        case .advanced: return "Lifting for 3+ years"
        }
    }
}

public struct ProgramRecommendation: Equatable, Sendable {
    public let programId: String
    public let reason: String
}

/// Suggests programs; the user always makes the final choice.
public enum ProgramAdvisor {
    public static func recommend(experience: Experience, daysPerWeek: Int, programs: [Program]) -> [ProgramRecommendation] {
        let ids = Set(programs.map(\.id))
        var out: [ProgramRecommendation] = []
        func add(_ id: String, _ reason: String) {
            if ids.contains(id), !out.contains(where: { $0.programId == id }) { out.append(.init(programId: id, reason: reason)) }
        }
        switch experience {
        case .new, .returning:
            if daysPerWeek <= 2 {
                add("beginner-12wk-option-a", "Two full-body sessions a week; ideal for busy weeks.")
            }
            add("beginner-12wk-option-b", "The recommended start: three full-body sessions a week. Move to Option C after about 8 weeks.")
            if daysPerWeek >= 4 {
                add("beginner-12wk-option-c", "Four days (upper/lower), best after about 8 weeks of Option B.")
            }
            add("beginner-12wk-option-a", "Two days a week for busy weeks.")
        case .intermediate:
            if daysPerWeek <= 3 { add("rw-full-body-3day-8wk", "Three full-body sessions a week.") }
            if daysPerWeek == 4 { add("rw-upper-lower-4day-8wk", "Four days: upper and lower body.") }
            if daysPerWeek >= 5 { add("rw-body-part-split-5day-8wk", "Five days, one or two muscle groups each.") }
            add("rw-upper-lower-4day-8wk", "Four days: upper and lower body.")
            add("rw-full-body-3day-8wk", "Three full-body sessions a week.")
        case .advanced:
            if daysPerWeek >= 5 {
                add("rw-intermediate-18wk", "Five days, 18 weeks, RIR-based with supersets.")
                add("rw-12-week", "5-6 sessions a week with %1RM loading; needs your squat, bench, deadlift and press 1RMs.")
            }
            if daysPerWeek == 4 { add("rw-upper-lower-4day-8wk", "Four days: upper and lower body.") }
            if daysPerWeek <= 3 { add("rw-full-body-3day-8wk", "Three full-body sessions a week.") }
            add("rw-12-week", "5-6 sessions a week with %1RM loading.")
            add("rw-body-part-split-5day-8wk", "Five days, one or two muscle groups each.")
        }
        return out
    }
}

/// When the app locks after being in the background.
public struct LockPolicy: Equatable, Sendable {
    public var timeout: TimeInterval
    public init(timeout: TimeInterval) { self.timeout = timeout }

    public func shouldLock(backgroundedAt: Date?, now: Date) -> Bool {
        guard let b = backgroundedAt else { return false }
        return now.timeIntervalSince(b) >= timeout
    }

    public static let timeoutChoices: [(seconds: Int, label: String)] = [
        (0, "Immediately"), (60, "After 1 minute"), (300, "After 5 minutes"), (900, "After 15 minutes"),
    ]
}
