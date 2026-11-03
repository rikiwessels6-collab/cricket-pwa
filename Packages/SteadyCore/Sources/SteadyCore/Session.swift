import Foundation

/// One exercise as it will be done today: a program slot after any session
/// version (express, low-energy, minimum) and any swap has been applied.
/// The program itself is never changed.
public struct PlannedExercise: Identifiable, Sendable, Equatable {
    public var id: Int                 // slot order in the original workout
    public var exerciseId: String
    public var originalExerciseId: String
    public var name: String
    public var sets: Int
    public var reps: RepScheme
    public var perSide: Bool
    public var repsText: String
    public var effortType: IntensityType?
    public var effortMin: Double?
    public var effortMax: Double?
    public var restSeconds: Int
    public var supersetGroup: String?
    public var isMainLift: Bool
    public var pct1RM: Double?         // lower bound of the %1RM range
    public var pctLift: String?
    public var notes: String?

    public init(slot: ExerciseSlot, defaultRest: Int = 90) {
        id = slot.order
        exerciseId = slot.exerciseId
        originalExerciseId = slot.exerciseId
        name = slot.exercise.capitalized
        sets = slot.sets.count ?? 2
        reps = slot.reps.scheme
        perSide = slot.reps.perSide
        repsText = slot.reps.display
        effortType = slot.effort?.type
        effortMin = slot.effort?.min
        effortMax = slot.effort?.max
        if let r = slot.rest, let lo = r.minSec, let hi = r.maxSec { restSeconds = (lo + hi) / 2 } else { restSeconds = defaultRest }
        supersetGroup = slot.superset?.group
        isMainLift = slot.isMainLift ?? false
        pct1RM = slot.pct1RM?.min
        pctLift = slot.pct1RM?.lift
        notes = slot.notes
    }

    /// A slot that comes from a specialisation module rather than a program workbook.
    public init(moduleExerciseId: String, name: String, id: Int, sets: Int, repMin: Int, repMax: Int,
                restSeconds: Int, perSide: Bool = false) {
        self.id = id
        self.exerciseId = moduleExerciseId
        self.originalExerciseId = moduleExerciseId
        self.name = name
        self.sets = sets
        self.reps = .range(Double(repMin), Double(repMax))
        self.perSide = perSide
        self.repsText = repMin == repMax ? "\(repMin)" : "\(repMin)-\(repMax)"
        self.restSeconds = restSeconds
        self.isMainLift = false
    }

    public var effortText: String? {
        guard let t = effortType, let lo = effortMin, let hi = effortMax else { return nil }
        let v = lo == hi ? NumberText.format(lo) : "\(NumberText.format(lo))-\(NumberText.format(hi))"
        return t == .rpe ? "RPE \(v)" : "\(v) RIR"
    }

    /// Reps to aim for on set `index` (top of the range; per-set lists use their own value).
    public func targetReps(set index: Int) -> Int? {
        switch reps {
        case .fixed(let n): return n
        case .range(_, let hi): return Int(hi)
        case .perSet(let list): return list.indices.contains(index) ? list[index] : list.last
        case .plus(let n): return n
        case .restPause(_, let hi, _): return Int(hi)
        case .segments(let list): return list.first
        default: return nil
        }
    }

    public func minimumReps(set index: Int) -> Int? {
        switch reps {
        case .fixed(let n): return n
        case .range(let lo, _): return Int(lo)
        case .perSet(let list): return list.indices.contains(index) ? list[index] : list.last
        case .plus(let n): return n
        case .restPause(let lo, _, _): return Int(lo)
        case .segments(let list): return list.first
        default: return nil
        }
    }
}

public enum SessionVersion: String, CaseIterable, Codable, Sendable, Identifiable {
    case standard, lowEnergy, express, minimum
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .standard: return "Standard"
        case .lowEnergy: return "Low energy"
        case .express: return "Express"
        case .minimum: return "Minimum"
        }
    }

    public var detail: String {
        switch self {
        case .standard: return "The full session as written."
        case .lowEnergy: return "Every exercise, 2 sets, one step easier, same weights."
        case .express: return "Main lifts only, 2 sets each."
        case .minimum: return "Two main lifts and a core exercise. Better than skipping."
        }
    }

    /// Warm-up and cool-down minutes (shorter versions get shorter routines).
    public var routineMinutes: (warmup: Int, cooldown: Int) {
        switch self {
        case .standard, .lowEnergy: return (7, 5)
        case .express: return (5, 3)
        case .minimum: return (3, 2)
        }
    }
}

public enum SessionBuilder {
    static let corePatterns: Set<String> = ["core_flexion", "core_anti_extension", "core_anti_rotation", "core_rotation"]

    /// Port of tools/importer/versions.py `version()`.
    public static func build(_ workout: ProgramWorkout, version: SessionVersion,
                             library: [String: Exercise]) -> [PlannedExercise] {
        var all = workout.slots.map { PlannedExercise(slot: $0) }
        switch version {
        case .standard:
            return all
        case .lowEnergy:
            for i in all.indices {
                all[i].sets = min(all[i].sets, 2)
                if let lo = all[i].effortMin, let hi = all[i].effortMax {
                    if all[i].effortType == .rpe {
                        all[i].effortMin = max(5, lo - 1); all[i].effortMax = max(5, hi - 1)
                    } else {
                        all[i].effortMin = lo + 1; all[i].effortMax = hi + 1
                    }
                }
            }
            return all
        case .express, .minimum:
            var mains = all.filter(\.isMainLift)
            if mains.isEmpty {
                mains = Array(all.filter { library[$0.exerciseId]?.tier != "accessory" }.prefix(2))
                if mains.isEmpty { mains = Array(all.prefix(2)) }
            }
            var keep: [PlannedExercise]
            if version == .express {
                keep = mains
            } else {
                keep = Array(mains.prefix(2))
                if let core = all.first(where: { corePatterns.contains(library[$0.exerciseId]?.pattern ?? "") }) {
                    keep.append(core)
                } else if let bug = library["dead_bug"] {
                    var e = keep.first ?? all[0]
                    e.id = 1000; e.exerciseId = bug.id; e.originalExerciseId = bug.id; e.name = bug.name
                    e.reps = .fixed(8); e.perSide = true; e.repsText = "8 each side"; e.restSeconds = 45
                    e.supersetGroup = nil; e.isMainLift = false; e.pct1RM = nil; e.pctLift = nil
                    e.effortType = nil; e.effortMin = nil; e.effortMax = nil; e.notes = nil
                    keep.append(e)
                }
            }
            for i in keep.indices { keep[i].sets = min(keep[i].sets, 2) }
            // A superset partner that was dropped leaves its mate on its own.
            let groups = Dictionary(grouping: keep.compactMap(\.supersetGroup), by: { $0 })
            for i in keep.indices {
                if let g = keep[i].supersetGroup, groups[g]?.count == 1 {
                    keep[i].supersetGroup = nil
                    keep[i].restSeconds = max(keep[i].restSeconds, 90)
                }
            }
            return keep
        }
    }

    /// Beginner on-ramp (weeks 1-4): at most 2 sets at an easy effort, about RPE 6-7 or 3-4 reps in reserve.
    public static func applyOnRamp(_ plan: [PlannedExercise], week: Int) -> [PlannedExercise] {
        guard (1...4).contains(week) else { return plan }
        return plan.map { item in
            var e = item
            e.sets = min(e.sets, 2)
            if e.effortType == .rir {
                e.effortMin = max(e.effortMin ?? 3, 3)
                e.effortMax = max(e.effortMax ?? 4, 4)
            } else if e.effortType == .rpe {
                e.effortMin = min(e.effortMin ?? 6, 6)
                e.effortMax = min(e.effortMax ?? 7, 7)
            }
            return e
        }
    }

    /// Estimated minutes: sets x (45 s work + rest) + warm-up + cool-down.
    public static func estimatedMinutes(_ plan: [PlannedExercise], version: SessionVersion) -> Int {
        let r = version.routineMinutes
        var sec = Double((r.warmup + r.cooldown) * 60)
        for e in plan {
            let work: Double = e.perSide ? 90 : 45
            sec += Double(e.sets) * (work + Double(e.restSeconds))
        }
        return Int((sec / 60).rounded())
    }
}
