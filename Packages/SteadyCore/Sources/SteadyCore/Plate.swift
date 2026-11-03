import Foundation

// Plate-photo estimates. The relay (relay/src/index.ts) returns these shapes; the app only ever
// treats them as an estimate the person confirms before anything is logged.

public enum PlateConfidence: String, Codable, Sendable, Comparable, CaseIterable {
    case low, medium, high
    var rank: Int { switch self { case .low: return 0; case .medium: return 1; case .high: return 2 } }
    public static func < (a: PlateConfidence, b: PlateConfidence) -> Bool { a.rank < b.rank }

    public var label: String {
        switch self {
        case .high: return "Good estimate"
        case .medium: return "Check the amount"
        case .low: return "Rough guess"
        }
    }
}

public struct PlateItem: Codable, Equatable, Sendable {
    public var name: String
    public var grams: Double
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fibre: Double
    public var confidence: PlateConfidence
    public var basis: String

    public init(name: String, grams: Double, kcal: Double, protein: Double, carbs: Double, fat: Double,
                fibre: Double, confidence: PlateConfidence, basis: String = "") {
        self.name = name; self.grams = grams; self.kcal = kcal; self.protein = protein
        self.carbs = carbs; self.fat = fat; self.fibre = fibre; self.confidence = confidence; self.basis = basis
    }

    public var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat, fibre: fibre) }

    /// The same food at a different weight (nutrition scales in proportion).
    public func scaled(toGrams newGrams: Double) -> PlateItem {
        guard grams > 0, newGrams >= 0 else { var c = self; c.grams = max(0, newGrams); return c }
        let f = newGrams / grams
        var c = self
        c.grams = newGrams; c.kcal *= f; c.protein *= f; c.carbs *= f; c.fat *= f; c.fibre *= f
        return c
    }

    /// Per 100 g, for saving the item like any other food.
    public var per100: Per100? {
        guard grams > 0 else { return nil }
        let f = 100 / grams
        return Per100(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f, fibre: fibre * f)
    }
}

public struct PlateOption: Codable, Equatable, Sendable {
    public var label: String
    public var kcal: Double
    public var fat: Double
    public var carbs: Double
    public var protein: Double
    public var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
}

/// A question about something a photo can't show (oil, butter, dressing).
public struct PlateQuestion: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var options: [PlateOption]
}

public struct PlateResult: Codable, Equatable, Sendable {
    public var items: [PlateItem]
    public var questions: [PlateQuestion]
    public var notFood: Bool

    public static func decode(_ data: Data) throws -> PlateResult {
        try JSONDecoder().decode(PlateResult.self, from: data)
    }
}

public struct PlateRegion: Codable, Equatable, Sendable {
    public var label: String?
    public var areaCm2: Double
    public var heightCm: Double
    public init(label: String? = nil, areaCm2: Double, heightCm: Double) {
        self.label = label; self.areaCm2 = areaCm2; self.heightCm = heightCm
    }
}

public struct PlateDepth: Codable, Equatable, Sendable {
    public var distanceCm: Double?
    public var plateDiameterCm: Double?
    public var regions: [PlateRegion]?
    public init(distanceCm: Double? = nil, plateDiameterCm: Double? = nil, regions: [PlateRegion]? = nil) {
        self.distanceCm = distanceCm; self.plateDiameterCm = plateDiameterCm; self.regions = regions
    }
}

/// What the app sends. Only the photo, optional size hints and an optional note; no personal details.
public struct PlateRequest: Codable, Equatable, Sendable {
    public var imageBase64: String
    public var mediaType: String
    public var depth: PlateDepth?
    public var note: String?
    public init(imageBase64: String, mediaType: String = "image/jpeg", depth: PlateDepth? = nil, note: String? = nil) {
        self.imageBase64 = imageBase64; self.mediaType = mediaType; self.depth = depth
        self.note = note.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : String($0.prefix(300)) }
    }
}

public enum PlateMath {
    /// Items plus the option chosen for each question (index into the question's options; default is the first, "None").
    public static func total(items: [PlateItem], questions: [PlateQuestion], answers: [String: Int]) -> Macros {
        var sum = items.reduce(Macros()) { $0 + $1.macros }
        for q in questions {
            let i = answers[q.id] ?? 0
            if q.options.indices.contains(i) { sum = sum + q.options[i].macros }
        }
        return sum
    }

    /// The least certain item decides how much to trust the whole plate.
    public static func overall(_ items: [PlateItem]) -> PlateConfidence? { items.map(\.confidence).min() }
}
