import Foundation

/// Simple, general warm-up and cool-down checklists. They are a prompt, not a prescription: skip any step.
public struct RoutineStep: Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public init(id: String, text: String) { self.id = id; self.text = text }
}

public enum Routine {
    public enum Kind: String, Sendable { case warmup, cooldown }

    /// Minutes come from the session version (shorter sessions get shorter routines).
    public static func steps(_ kind: Kind, version: SessionVersion) -> [RoutineStep] {
        let minutes = kind == .warmup ? version.routineMinutes.warmup : version.routineMinutes.cooldown
        switch kind {
        case .warmup:
            var s = [
                RoutineStep(id: "w1", text: "Easy movement to warm up: walk, bike or row"),
                RoutineStep(id: "w2", text: "Shoulder rolls and arm circles"),
                RoutineStep(id: "w3", text: "Bodyweight squats and hip hinges"),
            ]
            if minutes >= 5 { s.append(RoutineStep(id: "w4", text: "A few slow reps with an empty bar or light weight")) }
            return s
        case .cooldown:
            var s = [RoutineStep(id: "c1", text: "Slow walk and easy breathing")]
            if minutes >= 3 { s.append(RoutineStep(id: "c2", text: "Gentle stretch of the muscles you worked")) }
            if minutes >= 5 { s.append(RoutineStep(id: "c3", text: "A few slow, deep breaths to settle")) }
            return s
        }
    }

    public static func minutes(_ kind: Kind, version: SessionVersion) -> Int {
        kind == .warmup ? version.routineMinutes.warmup : version.routineMinutes.cooldown
    }
}
