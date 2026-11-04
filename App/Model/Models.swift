import Foundation
import SwiftData
import SteadyCore

// One person per phone: each of these is a single row, created at the end of
// onboarding. Enums are stored as raw strings so the schema stays simple.

@Model
final class UserProfile {
    var name: String
    var birthYear: Int
    var sexRaw: String
    var heightCm: Double
    var weightKg: Double
    var bodyFatRange: String?
    var goalRaw: String
    var experienceRaw: String
    var activityRaw: String
    var injuries: String
    /// Turns on the perimenopause-aware defaults (protein, optional daily check-ins).
    var perimenopause: Bool
    var createdAt: Date

    init(name: String, birthYear: Int, sex: Sex, heightCm: Double, weightKg: Double, bodyFatRange: String?,
         goal: Goal, experience: Experience, activity: ActivityLevel, injuries: String, perimenopause: Bool) {
        self.name = name
        self.birthYear = birthYear
        self.sexRaw = sex.rawValue
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.bodyFatRange = bodyFatRange
        self.goalRaw = goal.rawValue
        self.experienceRaw = experience.rawValue
        self.activityRaw = activity.rawValue
        self.injuries = injuries
        self.perimenopause = perimenopause
        self.createdAt = .now
    }

    var sex: Sex { Sex(rawValue: sexRaw) ?? .female }
    var goal: Goal { Goal(rawValue: goalRaw) ?? .generalHealth }
    var experience: Experience { Experience(rawValue: experienceRaw) ?? .new }
    var activity: ActivityLevel { ActivityLevel(rawValue: activityRaw) ?? .light }
    var age: Int { Calendar.current.component(.year, from: .now) - birthYear }
    var stats: BodyStats { BodyStats(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex) }
}

struct FixedCommitment: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// Calendar weekday, 1 = Sunday ... 7 = Saturday.
    var weekday: Int
    var minutes: Int
    var countsAsActivity: Bool = true
}

@Model
final class TrainingPlan {
    var programId: String
    var startDate: Date
    var daysPerWeek: Int
    /// Preferred training weekdays (1 = Sunday ... 7 = Saturday).
    var preferredWeekdays: [Int]
    var sessionMinutes: Int
    var fixedCommitments: [FixedCommitment]
    var avoidHeavyLegsNextToCommitments: Bool
    var equipmentProfileId: String
    /// Equipment actually available (starts as the profile's list; the user can toggle items).
    var equipment: [String]
    /// Estimated 1RMs in kg by lift id (squat, bench, deadlift, ohp). Empty if not entered.
    var oneRepMaxes: [String: Double]
    /// Rotation position: index of the next session across the whole program.
    var nextSessionIndex: Int
    /// Smallest weight steps the app suggests when you hit the top of the rep range (kg). Editable in Settings.
    var upperIncrement: Double = 2.5
    var lowerIncrement: Double = 5

    init(programId: String, startDate: Date, daysPerWeek: Int, preferredWeekdays: [Int], sessionMinutes: Int,
         fixedCommitments: [FixedCommitment], avoidHeavyLegsNextToCommitments: Bool, equipmentProfileId: String,
         equipment: [String], oneRepMaxes: [String: Double]) {
        self.programId = programId
        self.startDate = startDate
        self.daysPerWeek = daysPerWeek
        self.preferredWeekdays = preferredWeekdays
        self.sessionMinutes = sessionMinutes
        self.fixedCommitments = fixedCommitments
        self.avoidHeavyLegsNextToCommitments = avoidHeavyLegsNextToCommitments
        self.equipmentProfileId = equipmentProfileId
        self.equipment = equipment
        self.oneRepMaxes = oneRepMaxes
        self.nextSessionIndex = 0
    }
}

@Model
final class NutritionPlan {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var fibre: Int
    var maintenance: Int
    var presetName: String
    var proteinPerKg: Double
    /// Follow the workbook advice: two weeks at maintenance before a deficit or surplus.
    var startAtMaintenance: Bool
    var createdAt: Date

    init(targets: Nutrition.Targets, presetName: String, proteinPerKg: Double, startAtMaintenance: Bool) {
        self.calories = targets.calories
        self.protein = targets.protein
        self.carbs = targets.carbs
        self.fat = targets.fat
        self.fibre = targets.fibre
        self.maintenance = targets.maintenance
        self.presetName = presetName
        self.proteinPerKg = proteinPerKg
        self.startAtMaintenance = startAtMaintenance
        self.createdAt = .now
    }
}

@Model
final class CheckInSettings {
    /// Calendar weekday, 1 = Sunday ... 7 = Saturday.
    var weekday: Int
    var sleepGoalHours: Double
    var stepsGoal: Int
    var metrics: [String]
    var dailyCheckIns: Bool

    init(weekday: Int, sleepGoalHours: Double, stepsGoal: Int, metrics: [String], dailyCheckIns: Bool) {
        self.weekday = weekday
        self.sleepGoalHours = sleepGoalHours
        self.stepsGoal = stepsGoal
        self.metrics = metrics
        self.dailyCheckIns = dailyCheckIns
    }
}

@Model
final class AppSettings {
    var onboardingComplete: Bool
    var lockEnabled: Bool
    var lockTimeoutSeconds: Int
    var disclaimerAcceptedAt: Date?
    /// Consent per data type (DataType.rawValue -> when it was given). Missing = not given.
    var consents: [String: Date]
    /// Opt-in local reminders (training days and the weekly check-in).
    var remindersEnabled: Bool = false
    var reminderHour: Int = 7
    var reminderMinute: Int = 0

    init() {
        onboardingComplete = false
        lockEnabled = true
        lockTimeoutSeconds = 60
        consents = [:]
    }
}

/// The kinds of personal data the app keeps, each with its own consent.
enum DataType: String, CaseIterable, Identifiable {
    case profile, training, nutrition, checkIns, photos, plateAnalysis, appleHealth
    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: return "Profile and body measurements"
        case .training: return "Workouts and training history"
        case .nutrition: return "Food log and nutrition targets"
        case .checkIns: return "Check-ins, sleep, energy and symptoms"
        case .photos: return "Progress photos"
        case .plateAnalysis: return "Plate photo estimates"
        case .appleHealth: return "Apple Health"
        }
    }

    var detail: String {
        switch self {
        case .profile: return "Age, sex, height, weight and goals, used to set your plan and targets."
        case .training: return "Sets, reps and weights, used to progress your program."
        case .nutrition: return "What you eat and your targets. Barcode lookups send only the barcode to Open Food Facts."
        case .checkIns: return "Weekly check-ins and optional daily notes. Private to this phone."
        case .photos: return "Front, side and rear photos, kept in the app, behind Face ID, never analysed."
        case .plateAnalysis: return "Off by default. When on, a plate photo you choose to analyse is sent once to estimate its food and macros, then discarded. Nothing is stored or linked to you."
        case .appleHealth: return "Reads your daily steps and body weight to fill in check-ins. Never writes to Health. Turn it on in Settings > Apple Health."
        }
    }

    /// The app can't work without these two.
    var required: Bool { self == .profile || self == .training }
}

// MARK: - Workout logs

@Model
final class WorkoutLog {
    var programId: String
    var weekNumber: Int
    var workoutPosition: Int
    var workoutName: String
    var versionRaw: String
    /// Exercises swapped for this session: slot order -> exercise id.
    var swaps: [Int: String]
    var startedAt: Date
    var finishedAt: Date?
    var notes: String
    /// Multiplier on suggested weights for this session (0.9 when "lower the load" was chosen at the readiness check).
    var loadFactor: Double = 1.0
    /// Readiness choice and reason code, kept on the phone only.
    var readinessChoiceRaw: String = ""
    var readinessCode: String = ""
    /// Exercise ids where the user accepted or declined a suggested increase or deload today.
    var acceptedSuggestions: [String] = []
    var declinedSuggestions: [String] = []
    @Relationship(deleteRule: .cascade, inverse: \SetLog.workout) var sets: [SetLog] = []

    init(programId: String, weekNumber: Int, workoutPosition: Int, workoutName: String, version: SessionVersion, swaps: [Int: String]) {
        self.programId = programId
        self.weekNumber = weekNumber
        self.workoutPosition = workoutPosition
        self.workoutName = workoutName
        self.versionRaw = version.rawValue
        self.swaps = swaps
        self.startedAt = .now
        self.notes = ""
    }

    var version: SessionVersion { SessionVersion(rawValue: versionRaw) ?? .standard }
}

@Model
final class SetLog {
    var exerciseId: String
    var slotOrder: Int
    var setIndex: Int
    var weight: Double
    var reps: Int
    var rpe: Double?
    var completedAt: Date
    // What was asked for, so progression can judge this set later.
    var targetSets: Int
    var targetReps: Int?
    var minReps: Int?
    var maxRPE: Double?
    var workout: WorkoutLog?

    init(exerciseId: String, slotOrder: Int, setIndex: Int, weight: Double, reps: Int, rpe: Double?,
         targetSets: Int, targetReps: Int?, minReps: Int?, maxRPE: Double?) {
        self.exerciseId = exerciseId
        self.slotOrder = slotOrder
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.completedAt = .now
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.minReps = minReps
        self.maxRPE = maxRPE
    }
}

// MARK: - Food

/// One thing eaten. Every entry is time-stamped twice: when it was logged and
/// when it was eaten (defaults to now, editable), plus how it was entered.
@Model
final class FoodEntry {
    var loggedAt: Date
    var eatenAt: Date
    var mealRaw: String
    var sourceRaw: String
    var name: String
    var brand: String?
    var barcode: String?
    var foodId: String
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fibre: Double
    /// Photo estimates: "high", "medium" or "low". Nil for exact sources.
    var confidence: String?

    init(item: FoodItem, grams: Double, meal: MealSlot, source: FoodSource, eatenAt: Date) {
        let m = item.macros(grams: grams)
        self.loggedAt = .now
        self.eatenAt = eatenAt
        self.mealRaw = meal.rawValue
        self.sourceRaw = source.rawValue
        self.name = item.name
        self.brand = item.brand
        self.barcode = item.barcode
        self.foodId = item.id
        self.grams = grams
        self.kcal = m.kcal
        self.protein = m.protein
        self.carbs = m.carbs
        self.fat = m.fat
        self.fibre = m.fibre
    }

    var meal: MealSlot { MealSlot(rawValue: mealRaw) ?? .snacks }
    var source: FoodSource { FoodSource(rawValue: sourceRaw) ?? .manual }
    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat, fibre: fibre) }
}

/// Foods kept for quick logging: everything scanned or searched is cached here
/// (so it works offline next time), and custom foods live here too.
@Model
final class SavedFood {
    @Attribute(.unique) var foodId: String
    var itemData: Data
    var isFavourite: Bool
    var isCustom: Bool
    var lastUsed: Date
    var useCount: Int

    init(item: FoodItem, isCustom: Bool = false) {
        self.foodId = item.id
        self.itemData = (try? JSONEncoder().encode(item)) ?? Data()
        self.isFavourite = false
        self.isCustom = isCustom
        self.lastUsed = .now
        self.useCount = 0
    }

    var item: FoodItem? { try? JSONDecoder().decode(FoodItem.self, from: itemData) }
}


// MARK: - Weekly check-ins

/// One weekly check-in: weight, sleep, steps, your own 1-10 ratings, tape measurements and a note.
/// Everything is optional so a quick check-in can be just a weight. Stays on this phone.
@Model
final class CheckInEntry {
    var date: Date
    var weightKg: Double?
    var sleepHours: Double?
    var steps: Int?
    var ratings: [String: Int] = [:]
    var measurements: [String: Double] = [:]
    var note: String = ""

    init(date: Date, weightKg: Double?, sleepHours: Double?, steps: Int?,
         ratings: [String: Int], measurements: [String: Double], note: String) {
        self.date = date; self.weightKg = weightKg; self.sleepHours = sleepHours; self.steps = steps
        self.ratings = ratings; self.measurements = measurements; self.note = note
    }
}
