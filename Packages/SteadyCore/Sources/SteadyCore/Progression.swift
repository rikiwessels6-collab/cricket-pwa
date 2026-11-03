import Foundation

/// A completed set as logged.
public struct LoggedSet: Sendable, Equatable {
    public var weight: Double
    public var reps: Int
    public var rpe: Double?
    public init(weight: Double, reps: Int, rpe: Double? = nil) {
        self.weight = weight; self.reps = reps; self.rpe = rpe
    }
}

/// One past session of a single exercise.
public struct ExerciseHistory: Sendable, Equatable {
    public var date: Date
    public var sets: [LoggedSet]
    public var targetSets: Int
    public var targetTop: [Int?]       // per set
    public var targetMin: [Int?]       // per set
    public var maxRPE: Double?         // prescribed ceiling, if RPE-based
    public init(date: Date, sets: [LoggedSet], targetSets: Int, targetTop: [Int?], targetMin: [Int?], maxRPE: Double?) {
        self.date = date; self.sets = sets; self.targetSets = targetSets
        self.targetTop = targetTop; self.targetMin = targetMin; self.maxRPE = maxRPE
    }

    /// The weight every completed set was done at (the lightest one).
    public var workingWeight: Double? { sets.map(\.weight).min() }

    /// Any set felt harder than the prescribed ceiling (RPE-based programs only).
    public var wasTooHard: Bool { sets.contains { ($0.rpe ?? 0) > (maxRPE ?? 10) + 0.5 } }

    public enum Outcome: Equatable, Sendable { case hitTop, inRange, missed }

    public var outcome: Outcome {
        guard sets.count >= targetSets else { return .missed }
        let tooHard = sets.contains { s in (s.rpe ?? 0) > (maxRPE ?? 10) + 0.5 }
        var top = true, inRange = true
        for (i, s) in sets.enumerated() {
            let hi = i < targetTop.count ? targetTop[i] : targetTop.last ?? nil
            let lo = i < targetMin.count ? targetMin[i] : targetMin.last ?? nil
            if let hi, s.reps < hi { top = false }
            if let lo, s.reps < lo { inRange = false }
        }
        if top && !tooHard { return .hitTop }
        return inRange ? .inRange : .missed
    }
}

/// Why the engine suggested what it did. Weekly increases are never forced.
public enum ReasonCode: String, Codable, Sendable, CaseIterable {
    case topOfRangeAtRir = "TOP_OF_RANGE_AT_RIR"          // suggest the smallest increase
    case belowRepMin = "BELOW_REP_MIN"                    // hold
    case rirTooLow = "RIR_TOO_LOW"                        // hold, ease off
    case dropTwoExposures = "DROP_TWO_EXPOSURES"          // hold or reduce, review recovery
    case newExerciseBaseline = "NEW_EXERCISE_BASELINE"
    case techniqueFlag = "TECHNIQUE_FLAG"
    case discomfortFlag = "DISCOMFORT_FLAG"
    case readinessLow = "READINESS_LOW"
    case missedReturnReduction = "MISSED_RETURN_REDUCTION"
    case userDeclined = "USER_DECLINED"
}

public struct LoadSuggestion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case byFeel, percent, increase, hold, retry, deload }
    public var weight: Double?
    public var kind: Kind
    public var reason: String
    public var code: ReasonCode? = nil
    /// The weight used last time, so the app can offer "keep" next to "use the suggestion".
    public var previousWeight: Double? = nil

    /// Increases and deloads change the weight, so the user confirms them; holds and first-time picks don't need to.
    public var needsConfirmation: Bool { kind == .increase || kind == .deload }
}

/// Progressive overload on top of the program. It only suggests: the program
/// and the user's own choice of weight always win.
public enum Progression {
    static let lowerPatterns: Set<String> = ["squat", "single_leg", "hinge", "glute_bridge", "calf"]

    /// Default jump: 5 kg for lower-body main lifts (squat, deadlift, hip thrust...), 2.5 kg otherwise.
    public static func increment(for exercise: Exercise?, upper: Double = 2.5, lower: Double = 5) -> Double {
        guard let e = exercise else { return upper }
        return lowerPatterns.contains(e.pattern) && e.tier == "main" ? lower : upper
    }

    public static func roundDown(_ w: Double, to step: Double) -> Double {
        guard step > 0 else { return w }
        return ((w / step) + 1e-9).rounded(.down) * step
    }

    /// Suggested working weight for today.
    /// - history: this exercise's past sessions, oldest first.
    public static func suggest(for planned: PlannedExercise, exercise: Exercise?, history: [ExerciseHistory],
                               oneRepMaxes: [String: Double], increment step: Double? = nil) -> LoadSuggestion {
        let inc = step ?? increment(for: exercise)
        if let pct = planned.pct1RM, let lift = planned.pctLift, let orm = oneRepMaxes[lift],
           planned.exerciseId == planned.originalExerciseId {
            let w = Strength.load(percent: pct, oneRepMax: orm, increment: 2.5)
            return .init(weight: w, kind: .percent, reason: "\(Int((pct * 100).rounded()))% of your \(lift) 1RM")
        }
        let usable = history.filter { $0.workingWeight != nil }
        guard let last = usable.last, let w = last.workingWeight else {
            let effort = planned.effortText.map { " at \($0)" } ?? ""
            return .init(weight: nil, kind: .byFeel, reason: "First time: pick a weight you can do for \(planned.repsText)\(effort).",
                         code: .newExerciseBaseline)
        }
        switch last.outcome {
        case .hitTop:
            return .init(weight: w + inc, kind: .increase, reason: "You hit every rep last time. Add \(NumberText.format(inc)) kg.",
                         code: .topOfRangeAtRir, previousWeight: w)
        case .inRange:
            if last.wasTooHard {
                return .init(weight: w, kind: .hold, reason: "That felt harder than planned. Same weight; ease off a little.",
                             code: .rirTooLow, previousWeight: w)
            }
            return .init(weight: w, kind: .hold, reason: "Same weight; aim for more reps.", previousWeight: w)
        case .missed:
            if usable.count >= 2, let prev = usable.dropLast().last, prev.outcome == .missed, prev.workingWeight == w {
                let d = max(0, roundDown(w * 0.9, to: inc))
                return .init(weight: d, kind: .deload, reason: "Missed twice in a row. Drop about 10% and build back up; check sleep, food and technique.",
                             code: .dropTwoExposures, previousWeight: w)
            }
            return .init(weight: w, kind: .retry, reason: "Missed reps last time. Same weight again.", code: .belowRepMin, previousWeight: w)
        }
    }

    /// Warm-up ramp before a main lift (12-week pyramid: bar x15, 40%, 60%, 70-75%).
    public static func warmupSets(working: Double, barWeight: Double = 20) -> [LoggedSet] {
        guard working > barWeight else { return [] }
        let steps: [(Double, Int)] = [(0.4, 5), (0.6, 3), (0.725, 2)]
        var out = [LoggedSet(weight: barWeight, reps: 15)]
        for (p, r) in steps {
            let w = max(barWeight, roundDown(working * p, to: 2.5))
            if w > (out.last?.weight ?? 0) { out.append(LoggedSet(weight: w, reps: r)) }
        }
        return out
    }
}
