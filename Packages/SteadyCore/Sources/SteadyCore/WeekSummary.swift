import Foundation

/// "Last time" for an exercise: the previous session's sets in one short line.
public enum LastTime {
    /// "60 kg × 8, 8, 7 · 65 kg × 5". Bodyweight sets (no load) read "10, 10, 8 reps".
    public static func summary(_ sets: [LoggedSet]) -> String {
        var groups: [(weight: Double, reps: [Int])] = []
        for s in sets {
            if let last = groups.last, last.weight == s.weight {
                groups[groups.count - 1].reps.append(s.reps)
            } else {
                groups.append((s.weight, [s.reps]))
            }
        }
        guard !groups.isEmpty else { return "" }
        if groups.count == 1 && groups[0].weight == 0 {
            return groups[0].reps.map(String.init).joined(separator: ", ") + " reps"
        }
        return groups.map { g in
            (g.weight == 0 ? "" : "\(NumberText.format(g.weight)) kg × ") + g.reps.map(String.init).joined(separator: ", ")
        }
        .joined(separator: " · ")
    }
}

/// Everything the weekly summary reads, already reduced to numbers.
public struct WeekFacts: Equatable, Sendable {
    public var sessions = 0
    public var plannedSessions = 0
    public var sets = 0
    public var volumeKg = 0.0
    public var records: [String] = []
    public var foodDays = 0
    public var avgKcal: Double?
    public var avgProtein: Double?
    public var daysProteinHit = 0
    public var kcalTarget: Int?
    public var proteinTarget: Int?
    public var goal: Goal?
    /// Average check-in weight this week and the week before.
    public var weightThisWeek: Double?
    public var weightPrevious: Double?
    public init() {}
}

public enum WeekSummary {
    /// A day counts as hitting protein at this share of the target.
    public static let proteinHitShare = 0.9

    public static func headline(_ f: WeekFacts) -> String {
        if f.plannedSessions == 0 { return f.sessions == 1 ? "1 session this week" : "\(f.sessions) sessions this week" }
        if f.sessions >= f.plannedSessions { return "All \(f.plannedSessions) sessions done" }
        if f.sessions == 0 { return "A rest week" }
        return "\(f.sessions) of \(f.plannedSessions) sessions"
    }

    /// Plain observations, in the order worth reading. Suggestions, never instructions or medical advice.
    public static func notes(_ f: WeekFacts) -> [String] {
        var out: [String] = []

        if f.sessions == 0 {
            out.append("No sessions logged. A Minimum session still keeps the habit going.")
        } else if f.plannedSessions > 0 && f.sessions < f.plannedSessions {
            out.append("You trained \(f.sessions) of \(f.plannedSessions) planned days. If the week was busy, a shorter version keeps progress moving.")
        } else if f.plannedSessions > 0 {
            out.append("Every planned session done. That consistency is what drives progress.")
        }

        if !f.records.isEmpty {
            out.append("New best on " + f.records.joined(separator: ", ") + ".")
        }

        if let target = f.proteinTarget, let avg = f.avgProtein, f.foodDays > 0 {
            let t = Double(target)
            if avg >= t * proteinHitShare {
                out.append("Protein averaged \(Int(avg.rounded())) g against a \(target) g target, on target for \(f.daysProteinHit) of \(f.foodDays) logged days.")
            } else {
                out.append("Protein averaged \(Int(avg.rounded())) g against a \(target) g target. A serve of protein at breakfast is the easiest gap to close.")
            }
        }

        if let target = f.kcalTarget, let avg = f.avgKcal, f.foodDays > 0, target > 0 {
            let diff = Int((avg - Double(target)).rounded())
            if abs(Double(diff)) <= Double(target) * 0.05 {
                out.append("Calories averaged \(Int(avg.rounded())), right on your \(target) target.")
            } else {
                out.append("Calories averaged \(Int(avg.rounded())), \(abs(diff)) \(diff > 0 ? "over" : "under") your \(target) target.")
            }
        }

        if let now = f.weightThisWeek, let before = f.weightPrevious {
            let change = now - before
            let size = String(format: "%.1f", abs(change))
            var line = abs(change) < 0.15 ? "Weight is steady at about \(String(format: "%.1f", now)) kg."
                : "Weight averaged \(String(format: "%.1f", now)) kg, \(change < 0 ? "down" : "up") \(size) kg on the week before."
            switch f.goal {
            case .fatLoss?:
                if change <= -0.15 { line += " That's the direction you're aiming for." }
                else if change >= 0.15 { line += " One week is noisy; look at two or three weeks before changing your targets." }
            case .buildMuscle?:
                if change >= 0.15 { line += " That fits building." }
                else if change <= -0.15 { line += " If it keeps falling for a couple of weeks, you may need a little more food." }
            default: break
            }
            out.append(line)
        } else if f.weightThisWeek == nil {
            out.append("No weight logged this week. A check-in gives next week's summary a trend to read.")
        }

        if f.foodDays > 0 && f.foodDays < 4 {
            out.append("Food was logged on \(f.foodDays) day\(f.foodDays == 1 ? "" : "s"). More days gives a clearer picture.")
        } else if f.foodDays == 0 {
            out.append("No food logged this week.")
        }
        return out
    }
}
