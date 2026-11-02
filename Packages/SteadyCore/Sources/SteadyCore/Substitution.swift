import Foundation

/// Picks the exercise to do today given the equipment available.
/// Swift port of `choose` / `options` in tools/importer/substitution.py;
/// SubstitutionTests checks both give the same answers.
public enum Substitution {
    public static let alwaysAvailable: Set<String> = ["bodyweight", "mat", "towel"]

    /// Every requirement met. A requirement "a/b" is met by either item.
    public static func satisfied(_ requirements: [String], available: Set<String>) -> Bool {
        let have = available.union(alwaysAvailable)
        return requirements.allSatisfy { item in
            item.split(separator: "/").contains { have.contains(String($0)) }
        }
    }

    public enum Reason: Equatable, Sendable {
        case asWritten, programAlternative, coachSwap, sameMovement, closestMovement
        case unavailable(missing: [String])
    }

    public static func choose(_ exerciseId: String, library: [String: Exercise], available: Set<String>,
                              maxDifficulty: Int = 3, exclude: Set<String> = [],
                              slotAlternatives: [String] = []) -> (id: String?, reason: Reason) {
        guard let src = library[exerciseId] else { return (nil, .unavailable(missing: [])) }
        if !exclude.contains(exerciseId), satisfied(src.equipment, available: available) {
            return (exerciseId, .asWritten)
        }
        for alt in slotAlternatives {
            if let e = library[alt], !exclude.contains(alt), satisfied(e.equipment, available: available) {
                return (alt, .programAlternative)
            }
        }
        for sub in src.substitutes {
            guard let cand = library[sub.id], !exclude.contains(sub.id), cand.difficulty <= maxDifficulty else { continue }
            if satisfied(cand.equipment, available: available) {
                return (sub.id, sub.curated ? .coachSwap : sub.samePattern ? .sameMovement : .closestMovement)
            }
        }
        let have = available.union(alwaysAvailable)
        let missing = src.equipment.filter { item in !item.split(separator: "/").contains { have.contains(String($0)) } }
        return (nil, .unavailable(missing: missing))
    }

    /// Stand-ins that work with today's equipment, best first, for the swap sheet.
    public static func options(_ exerciseId: String, library: [String: Exercise], available: Set<String>,
                               maxDifficulty: Int = 3, limit: Int = 5) -> [Exercise] {
        guard let src = library[exerciseId] else { return [] }
        return src.substitutes.compactMap { library[$0.id] }
            .filter { $0.difficulty <= maxDifficulty && satisfied($0.equipment, available: available) }
            .prefix(limit).map { $0 }
    }
}
