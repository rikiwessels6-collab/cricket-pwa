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

    init() {
        onboardingComplete = false
        lockEnabled = true
        lockTimeoutSeconds = 60
        consents = [:]
    }
}

/// The kinds of personal data the app keeps, each with its own consent.
enum DataType: String, CaseIterable, Identifiable {
    case profile, training, nutrition, checkIns, photos, appleHealth
    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: return "Profile and body measurements"
        case .training: return "Workouts and training history"
        case .nutrition: return "Food log and nutrition targets"
        case .checkIns: return "Check-ins, sleep, energy and symptoms"
        case .photos: return "Progress photos"
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
        case .appleHealth: return "Steps, workouts, weight and sleep. Asked separately when that feature arrives."
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
