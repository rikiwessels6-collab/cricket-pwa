import Foundation

public enum Sex: String, Codable, CaseIterable, Sendable {
    case male, female
    public var label: String { self == .male ? "Male" : "Female" }
}

public enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary, light, moderate, veryActive

    public var factor: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .veryActive: return 1.725
        }
    }

    public var label: String {
        switch self {
        case .sedentary: return "Mostly sitting"
        case .light: return "Lightly active"
        case .moderate: return "Moderately active"
        case .veryActive: return "Very active"
        }
    }

    public var detail: String {
        switch self {
        case .sedentary: return "Desk job, little walking, training under 3 times a week."
        case .light: return "Desk job with some walking, training 3-4 times a week."
        case .moderate: return "On your feet a fair bit, training 4-5 times a week."
        case .veryActive: return "Physical job or lots of extra activity, training most days."
        }
    }
}

public enum Goal: String, Codable, CaseIterable, Sendable {
    case fatLoss, maintain, buildMuscle, generalHealth

    public var label: String {
        switch self {
        case .fatLoss: return "Lose fat"
        case .maintain: return "Maintain"
        case .buildMuscle: return "Build muscle"
        case .generalHealth: return "General health"
        }
    }
}

public struct MacroPreset: Equatable, Hashable, Sendable, Identifiable {
    public let name: String
    public let protein: Double
    public let carbs: Double
    public let fat: Double
    public var id: String { name }

    public init(name: String, protein: Double, carbs: Double, fat: Double) {
        self.name = name; self.protein = protein; self.carbs = carbs; self.fat = fat
    }

    /// The check-in workbook's dietary styles (shares of calories).
    public static let all: [MacroPreset] = [
        .init(name: "Balanced", protein: 0.30, carbs: 0.35, fat: 0.35),
        .init(name: "Zone", protein: 0.30, carbs: 0.40, fat: 0.30),
        .init(name: "Low fat", protein: 0.30, carbs: 0.50, fat: 0.20),
        .init(name: "Low carb", protein: 0.25, carbs: 0.10, fat: 0.65),
        .init(name: "Keto", protein: 0.20, carbs: 0.05, fat: 0.75),
        .init(name: "Vegan", protein: 0.15, carbs: 0.55, fat: 0.30),
        .init(name: "High protein", protein: 0.40, carbs: 0.30, fat: 0.30),
    ]
    public static let balanced = all[0]
}

public struct BodyStats: Equatable, Sendable {
    public var weightKg: Double
    public var heightCm: Double
    public var age: Int
    public var sex: Sex
    public init(weightKg: Double, heightCm: Double, age: Int, sex: Sex) {
        self.weightKg = weightKg; self.heightCm = heightCm; self.age = age; self.sex = sex
    }
}

public enum Nutrition {
    /// Mifflin-St Jeor: 10 x kg + 6.25 x cm - 5 x age, +5 (male) or -161 (female).
    public static func bmr(_ s: BodyStats) -> Double {
        10 * s.weightKg + 6.25 * s.heightCm - 5 * Double(s.age) + (s.sex == .male ? 5 : -161)
    }

    public static func tdee(_ s: BodyStats, _ activity: ActivityLevel) -> Double {
        bmr(s) * activity.factor
    }

    /// Lowest daily target the app sets without an explicit override.
    public static func safeFloor(_ sex: Sex) -> Double { sex == .female ? 1500 : 1800 }

    public static let fibrePer1000kcal = 14.0
    public static let minFatPerKg = 0.5

    public enum Warning: Equatable, Sendable {
        /// The goal asked for fewer calories than the floor; target raised to the floor.
        case raisedToFloor(floor: Int)
        /// The user overrode the floor; target is below it.
        case belowFloor(floor: Int)
        /// Protein plus the preset's fat didn't leave room for carbs; fat was lowered.
        case fatLowered
        /// The preset's protein share is below the g/kg target; g/kg wins.
        case proteinAbovePreset
    }

    public struct Targets: Equatable, Sendable {
        public var maintenance: Int
        public var calories: Int
        public var protein: Int
        public var carbs: Int
        public var fat: Int
        public var fibre: Int
        public var warnings: [Warning]
    }

    /// Calorie and macro targets. Protein is set first (g/kg), then fat from the
    /// preset share (never below 0.5 g/kg), then carbs take the remainder.
    public static func targets(_ stats: BodyStats, activity: ActivityLevel, goal: Goal,
                               proteinPerKg: Double = 1.8, preset: MacroPreset = .balanced,
                               deficit: Double = 0.175, surplus: Double = 0.10,
                               calorieOverride: Double? = nil, allowBelowFloor: Bool = false) -> Targets {
        let maintenance = tdee(stats, activity)
        var warnings: [Warning] = []
        var calories: Double
        if let o = calorieOverride {
            calories = o
        } else {
            switch goal {
            case .fatLoss: calories = maintenance * (1 - deficit)
            case .buildMuscle: calories = maintenance * (1 + surplus)
            case .maintain, .generalHealth: calories = maintenance
            }
        }
        let floor = safeFloor(stats.sex)
        if calories < floor {
            if allowBelowFloor {
                warnings.append(.belowFloor(floor: Int(floor)))
            } else {
                calories = floor
                warnings.append(.raisedToFloor(floor: Int(floor)))
            }
        }
        let protein = proteinPerKg * stats.weightKg
        if preset.protein * calories / 4 < protein - 0.5 {
            warnings.append(.proteinAbovePreset)
        }
        var fat = max(minFatPerKg * stats.weightKg, preset.fat * calories / 9)
        var carbs = (calories - 4 * protein - 9 * fat) / 4
        if carbs < 0 {
            fat = max(minFatPerKg * stats.weightKg, (calories - 4 * protein) / 9)
            carbs = max(0, (calories - 4 * protein - 9 * fat) / 4)
            warnings.append(.fatLowered)
        }
        return Targets(maintenance: Int(maintenance.rounded()), calories: Int(calories.rounded()),
                       protein: Int(protein.rounded()), carbs: Int(carbs.rounded()), fat: Int(fat.rounded()),
                       fibre: Int((calories / 1000 * fibrePer1000kcal).rounded()), warnings: warnings)
    }
}
