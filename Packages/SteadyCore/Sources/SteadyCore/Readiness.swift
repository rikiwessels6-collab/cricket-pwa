import Foundation

/// The optional three-question check before a session: sleep, energy, and anything that bothers you today.
/// It never diagnoses and never blocks; it only offers choices. Answers stay on the phone.
public struct ReadinessAnswers: Equatable, Sendable {
    public enum Level: Int, CaseIterable, Sendable {
        case low = 0, okay, good
        public var label: String { ["Poor", "Okay", "Good"][rawValue] }
    }

    public enum Concern: String, CaseIterable, Sendable {
        case nothing, soreness, tired, stress, jointDiscomfort, pain, dizzy
        public var label: String {
            switch self {
            case .nothing: return "Nothing"
            case .soreness: return "Sore muscles"
            case .tired: return "Very tired"
            case .stress: return "Stressed"
            case .jointDiscomfort: return "Joint discomfort"
            case .pain: return "Pain"
            case .dizzy: return "Dizzy or unwell"
            }
        }
    }

    public var sleep: Level
    public var energy: Level
    public var concern: Concern
    public var note: String

    public init(sleep: Level = .good, energy: Level = .good, concern: Concern = .nothing, note: String = "") {
        self.sleep = sleep; self.energy = energy; self.concern = concern; self.note = note
    }
}

public enum Readiness {
    public static let stopMessage = "Stop and speak to a doctor or qualified professional."

    public enum Choice: String, CaseIterable, Sendable, Identifiable {
        case asPlanned, lowerLoad, fewerSets, comfortableSubstitute, rest
        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .asPlanned: return "Do it as planned"
            case .lowerLoad: return "Lower the load"
            case .fewerSets: return "Fewer sets"
            case .comfortableSubstitute: return "Swap what doesn't feel right"
            case .rest: return "Rest today"
            }
        }

        public var detail: String {
            switch self {
            case .asPlanned: return "The full session."
            case .lowerLoad: return "Same sets, about 10% less weight."
            case .fewerSets: return "Two sets per exercise, one step easier (about a third fewer sets)."
            case .comfortableSubstitute: return "Tap the swap button on any exercise for an alternative."
            case .rest: return "Skipping is fine. Your next session stays next."
            }
        }

        /// The session version this choice runs.
        public var version: SessionVersion { self == .fewerSets ? .lowEnergy : .standard }
        /// Multiplier applied to suggested weights.
        public var loadFactor: Double { self == .lowerLoad ? 0.9 : 1.0 }
    }

    public struct Advice: Equatable, Sendable {
        public var suggested: Choice
        public var stopMessage: String?
        public var code: ReasonCode?
    }

    static let stopWords = ["pain", "dizz", "chest", "faint", "numb", "short of breath", "breathless", "palpitation"]

    /// Wording avoids medical claims: these are suggestions, not assessments.
    public static func advise(_ a: ReadinessAnswers) -> Advice {
        let text = a.note.lowercased()
        let stop = a.concern == .pain || a.concern == .dizzy || stopWords.contains { text.contains($0) }
        if stop { return Advice(suggested: .rest, stopMessage: stopMessage, code: .discomfortFlag) }
        let score = a.sleep.rawValue + a.energy.rawValue
        if a.concern == .jointDiscomfort { return Advice(suggested: .comfortableSubstitute, stopMessage: nil, code: .discomfortFlag) }
        if score <= 1 { return Advice(suggested: .fewerSets, stopMessage: nil, code: .readinessLow) }
        if score <= 3 || a.concern != .nothing { return Advice(suggested: .lowerLoad, stopMessage: nil, code: .readinessLow) }
        return Advice(suggested: .asPlanned, stopMessage: nil, code: nil)
    }
}
