import Foundation

// Specialisation modules (6-week blocks, two sessions a week) and the volume maths behind them.
// The module CONTENT is not bundled yet: it is waiting for the reviewed catalogue. This is the engine,
// tested with sample data, so the content can drop in without code changes.

/// Every number here can be changed in one place; the values are placeholders until a qualified reviewer confirms them.
public struct RuleSet: Codable, Equatable, Sendable {
    public var primaryCredit: Double
    public var secondaryCredit: Double
    /// Direct hard sets per muscle per week above which the app shows a review prompt (never a block).
    public var reviewThresholdDirectSets: Double
    public var sessionLimitMinutes: Int

    public init(primaryCredit: Double = 1.0, secondaryCredit: Double = 0.5,
                reviewThresholdDirectSets: Double = 20, sessionLimitMinutes: Int = 60) {
        self.primaryCredit = primaryCredit; self.secondaryCredit = secondaryCredit
        self.reviewThresholdDirectSets = reviewThresholdDirectSets; self.sessionLimitMinutes = sessionLimitMinutes
    }
}

public struct ModuleSlot: Codable, Equatable, Sendable {
    public var exerciseId: String
    public var sets: Int
    public var repMin: Int
    public var repMax: Int
    public var restSeconds: Int
    public init(exerciseId: String, sets: Int, repMin: Int, repMax: Int, restSeconds: Int = 90) {
        self.exerciseId = exerciseId; self.sets = sets; self.repMin = repMin; self.repMax = repMax; self.restSeconds = restSeconds
    }
}

public struct Specialisation: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case lower, upper }
    public var id: String
    public var name: String
    public var kind: Kind
    public var targetMuscles: [String]
    /// Sessions A and B.
    public var sessions: [[ModuleSlot]]
    public var weeks: Int

    public init(id: String, name: String, kind: Kind, targetMuscles: [String], sessions: [[ModuleSlot]], weeks: Int = 6) {
        self.id = id; self.name = name; self.kind = kind; self.targetMuscles = targetMuscles
        self.sessions = sessions; self.weeks = weeks
    }
}

/// What a merge did, so the app can show a "What changed" list. Nothing is ever added or removed silently.
public struct MergeChange: Equatable, Sendable {
    public var added: [String] = []
    public var removed: [String] = []
    public var trimmed: [String] = []
    public var minutesBefore = 0
    public var minutesAfter = 0
    /// False only if even the main lifts alone are over the time limit.
    public var fitsTimeLimit = true
}

public enum ModuleMerger {
    static let moduleIdBase = 2000

    /// Overlays one module session onto a base session:
    ///  a) remove base accessory slots whose primary muscles fall inside the module's targets;
    ///  b) add the module's slots;
    ///  c) if the session is over the time limit, trim the lowest-priority accessories (last first) until it fits.
    /// It is a pure function of the ORIGINAL base session, so activating twice never duplicates sets.
    public static func merge(base: [PlannedExercise], module: [ModuleSlot], targets: Set<String>,
                             library: [String: Exercise], rules: RuleSet = RuleSet(),
                             version: SessionVersion = .standard) -> (plan: [PlannedExercise], change: MergeChange) {
        var change = MergeChange()
        change.minutesBefore = SessionBuilder.estimatedMinutes(base, version: version)
        var plan = base

        plan.removeAll { e in
            guard !e.isMainLift, let ex = library[e.exerciseId], ex.tier == "accessory" else { return false }
            let overlaps = !Set(ex.primaryMuscles).isDisjoint(with: targets)
            if overlaps { change.removed.append(e.name) }
            return overlaps
        }

        for (i, m) in module.enumerated() {
            let name = library[m.exerciseId]?.name ?? m.exerciseId
            plan.append(PlannedExercise(moduleExerciseId: m.exerciseId, name: name, id: moduleIdBase + i, sets: m.sets,
                                        repMin: m.repMin, repMax: m.repMax, restSeconds: m.restSeconds,
                                        perSide: library[m.exerciseId]?.unilateral ?? false))
            change.added.append(name)
        }

        func trimOne(fromModule: Bool) -> Bool {
            let idx = plan.lastIndex { e in
                guard !e.isMainLift, library[e.exerciseId]?.tier != "main" else { return false }
                return fromModule ? e.id >= moduleIdBase : e.id < moduleIdBase
            }
            guard let i = idx else { return false }
            change.trimmed.append(plan[i].name)
            plan.remove(at: i)
            return true
        }
        while SessionBuilder.estimatedMinutes(plan, version: version) > rules.sessionLimitMinutes {
            if !trimOne(fromModule: false) && !trimOne(fromModule: true) { break }
        }
        change.minutesAfter = SessionBuilder.estimatedMinutes(plan, version: version)
        change.fitsTimeLimit = change.minutesAfter <= rules.sessionLimitMinutes
        // Something added and then trimmed again is not a change the user needs to read twice.
        let trimmedNames = change.trimmed
        change.added.removeAll { trimmedNames.contains($0) }
        return (plan, change)
    }

    /// No module active means the base session, exactly.
    public static func resolve(base: [PlannedExercise], module: Specialisation?, sessionIndex: Int,
                               library: [String: Exercise], rules: RuleSet = RuleSet()) -> (plan: [PlannedExercise], change: MergeChange) {
        guard let module, module.sessions.indices.contains(sessionIndex) else {
            var c = MergeChange()
            c.minutesBefore = SessionBuilder.estimatedMinutes(base, version: .standard)
            c.minutesAfter = c.minutesBefore
            return (base, c)
        }
        return merge(base: base, module: module.sessions[sessionIndex], targets: Set(module.targetMuscles),
                     library: library, rules: rules)
    }

    /// Muscles two modules both target: shown as an overlap warning before a second module is confirmed.
    public static func overlap(_ a: Specialisation, _ b: Specialisation) -> [String] {
        Array(Set(a.targetMuscles).intersection(b.targetMuscles)).sorted()
    }
}

public struct MuscleVolume: Equatable, Sendable {
    public var direct: Double = 0
    public var indirect: Double = 0
}

public struct VolumeReview: Equatable, Sendable {
    public var muscle: String
    public var directSets: Double
    public var message: String
}

public enum WeeklyVolume {
    /// Approximate weekly hard sets by muscle, from the week's working sets (warm-ups are not counted).
    /// The prime mover (first listed primary muscle) gets full credit as DIRECT volume. Other primary and
    /// secondary muscles get partial credit as INDIRECT volume, kept separate and never added to direct.
    /// Timed holds and carries are shown elsewhere but don't count towards hypertrophy volume.
    public static func compute(_ sessions: [[PlannedExercise]], library: [String: Exercise],
                               rules: RuleSet = RuleSet()) -> [String: MuscleVolume] {
        var out: [String: MuscleVolume] = [:]
        for session in sessions {
            for e in session {
                guard let ex = library[e.exerciseId], !ex.timed, ex.pattern != "carry", e.sets > 0 else { continue }
                let sets = Double(e.sets)
                if let mover = ex.primaryMuscles.first { out[mover, default: MuscleVolume()].direct += sets * rules.primaryCredit }
                for m in ex.primaryMuscles.dropFirst() + ex.secondaryMuscles {
                    out[m, default: MuscleVolume()].indirect += sets * rules.secondaryCredit
                }
            }
        }
        return out
    }

    /// A review prompt, not a block, when direct sets for a muscle go above the threshold.
    public static func reviewPrompts(_ volume: [String: MuscleVolume], rules: RuleSet = RuleSet()) -> [VolumeReview] {
        volume.filter { $0.value.direct > rules.reviewThresholdDirectSets }
            .map { VolumeReview(muscle: $0.key, directSets: $0.value.direct,
                                message: "About \(Int($0.value.direct.rounded())) direct sets a week for this muscle (approximate). "
                                    + "That suits some people. If recovery, sleep or enjoyment are slipping, consider easing back.") }
            .sorted { $0.directSets > $1.directSets }
    }
}
