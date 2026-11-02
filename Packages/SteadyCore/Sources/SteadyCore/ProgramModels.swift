import Foundation

// Codable mirror of Resources/Generated/programs.json (written by
// tools/importer/import_programs.py). Unknown keys are ignored, so the importer
// can add fields without breaking older app builds.

public struct ProgramBundle: Decodable, Sendable {
    public let schemaVersion: Int
    public let programs: [Program]
}

public enum IntensityType: String, Decodable, Sendable {
    case rpe, rir
}

public struct Program: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let author: String?
    public let intensityType: IntensityType
    public let unit: String?
    public let weeks: [ProgramWeek]
    public let status: String
    public let family: String?
    public let optionDaysPerWeek: Int?
    public let whenToUse: String?
    public let maxSwapDifficulty: Int?
    public let usesPercent1RM: Bool?
    public let requires1RM: [String]?
    public let programNotes: [String]?
    public let equipmentNeeded: [String]
    public let equipmentCoverage: [String: EquipmentCoverage]

    /// Fewest and most sessions in any week (the 12-week program alternates 5 and 6).
    public var sessionsPerWeek: ClosedRange<Int> {
        let counts = weeks.map { $0.workouts.count }
        return (counts.min() ?? 0)...(counts.max() ?? 0)
    }

    public var requiresOneRepMax: Bool { !(requires1RM ?? []).isEmpty }

    public var averageSessionMinutes: Int {
        let all = weeks.flatMap { $0.workouts.map(\.estimatedMinutes) }
        guard !all.isEmpty else { return 0 }
        return Int((Double(all.reduce(0, +)) / Double(all.count)).rounded())
    }

    public var sessionsPerWeekText: String {
        let r = sessionsPerWeek
        return r.lowerBound == r.upperBound ? "\(r.lowerBound)" : "\(r.lowerBound)-\(r.upperBound)"
    }
}

public struct EquipmentCoverage: Decodable, Sendable {
    public let asWritten: Int
    public let swapped: Int
    public let unavailable: Int
    public let total: Int
}

public struct ProgramWeek: Decodable, Identifiable, Sendable {
    public let number: Int
    public let label: String
    public let isDeload: Bool?
    public let phase: String?
    public let workouts: [ProgramWorkout]
    public var id: Int { number }
}

public struct ProgramWorkout: Decodable, Identifiable, Sendable {
    public let name: String
    public let rawName: String
    public let position: Int
    public let estimatedMinutes: Int
    public let slots: [ExerciseSlot]
    public var id: Int { position }
}

public struct ExerciseSlot: Decodable, Identifiable, Sendable {
    public let exercise: String
    public let exerciseId: String
    public let order: Int
    public let sets: SetCount
    public let reps: Reps
    public let effort: Effort?
    public let rest: Rest?
    public let notes: String?
    public let superset: Superset?
    public let pct1RM: PercentOneRM?
    public let warmupSets: Int?
    public let isMainLift: Bool?
    public let modifier: String?
    public let lastSetPlus: Bool?
    public let alternativeIds: [String]?
    public var id: Int { order }
}

public struct SetCount: Decodable, Sendable {
    public let count: Int?
    public let perSide: Bool?
}

public struct Effort: Decodable, Sendable {
    public let type: IntensityType
    public let raw: String
    public let min: Double?
    public let max: Double?

    public var display: String {
        guard let lo = min, let hi = max else { return raw }
        let value = lo == hi ? NumberText.format(lo) : "\(NumberText.format(lo))-\(NumberText.format(hi))"
        return type == .rpe ? "RPE \(value)" : "\(value) RIR"
    }
}

public struct Rest: Decodable, Sendable {
    public let raw: String?
    public let minSec: Int?
    public let maxSec: Int?

    public var display: String {
        guard let lo = minSec, let hi = maxSec else { return raw ?? "" }
        if hi == 0 { return "No rest" }
        func text(_ s: Int) -> String { s % 60 == 0 ? "\(s / 60)" : String(format: "%.1f", Double(s) / 60) }
        if hi < 60 { return lo == hi ? "\(hi) s" : "\(lo)-\(hi) s" }
        return lo == hi ? "\(text(hi)) min" : "\(text(lo))-\(text(hi)) min"
    }
}

public struct Superset: Decodable, Sendable {
    public let group: String
    public let label: String?
    public let order: Int
    public let size: Int?
}

public struct PercentOneRM: Decodable, Sendable {
    public let raw: String
    public let min: Double?
    public let max: Double?
    public let lift: String?
}

public enum RepScheme: Sendable, Equatable {
    case fixed(Int)
    case range(Double, Double)
    case perSet([Int])
    case plus(Int)
    case amrap
    case duration(Double, Double)
    case distance(Double, Double)
    case segments([Int])
    case restPause(Double, Double, extras: [Int])
    case unknown
}

public struct Reps: Decodable, Sendable {
    public let raw: String
    public let perSide: Bool
    public let scheme: RepScheme
    public let repairedFrom: String?

    enum CodingKeys: String, CodingKey {
        case raw, perSide, kind, reps, min, max, minSec, maxSec, minM, maxM, extras, repairedFrom
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        raw = try c.decodeIfPresent(String.self, forKey: .raw) ?? ""
        perSide = try c.decodeIfPresent(Bool.self, forKey: .perSide) ?? false
        repairedFrom = try c.decodeIfPresent(String.self, forKey: .repairedFrom)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "fixed": scheme = .fixed(try c.decode(Int.self, forKey: .reps))
        case "range": scheme = .range(try c.decode(Double.self, forKey: .min), try c.decode(Double.self, forKey: .max))
        case "perSet": scheme = .perSet(try c.decode([Int].self, forKey: .reps))
        case "plus": scheme = .plus(try c.decode(Int.self, forKey: .reps))
        case "amrap": scheme = .amrap
        case "duration": scheme = .duration(try c.decode(Double.self, forKey: .minSec), try c.decode(Double.self, forKey: .maxSec))
        case "distance": scheme = .distance(try c.decode(Double.self, forKey: .minM), try c.decode(Double.self, forKey: .maxM))
        case "segments": scheme = .segments(try c.decode([Int].self, forKey: .reps))
        case "restPause":
            scheme = .restPause(try c.decode(Double.self, forKey: .min), try c.decode(Double.self, forKey: .max),
                                extras: try c.decode([Int].self, forKey: .extras))
        default: scheme = .unknown
        }
    }

    /// Short text for a set row, e.g. "8-10", "11, 9, 7", "10+", "20-40 s", "8 each side".
    public var display: String {
        let f = NumberText.format
        let core: String
        switch scheme {
        case .fixed(let n): core = "\(n)"
        case .range(let lo, let hi): core = lo == hi ? f(lo) : "\(f(lo))-\(f(hi))"
        case .perSet(let list): core = list.map(String.init).joined(separator: ", ")
        case .plus(let n): core = "\(n)+"
        case .amrap: core = "AMRAP"
        case .duration(let lo, let hi): core = lo == hi ? "\(f(lo)) s" : "\(f(lo))-\(f(hi)) s"
        case .distance(let lo, let hi): core = lo == hi ? "\(f(lo)) m" : "\(f(lo))-\(f(hi)) m"
        case .segments(let list): core = list.map(String.init).joined(separator: " + ")
        case .restPause(let lo, let hi, let extras):
            core = (lo == hi ? f(lo) : "\(f(lo))-\(f(hi))") + " (" + extras.map { "+\($0)" }.joined() + ")"
        case .unknown: core = raw
        }
        return perSide ? "\(core) each side" : core
    }
}

public enum NumberText {
    /// 8.0 -> "8", 82.5 -> "82.5"
    public static func format(_ d: Double) -> String {
        d.rounded() == d ? String(Int(d)) : String(format: "%g", d)
    }
}
