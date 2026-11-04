import Foundation
import SwiftData

/// "Export my data": everything the app holds about you, as one JSON file you
/// can save or share from the share sheet. Nothing is uploaded anywhere.
enum DataExport {
    struct Snapshot: Encodable {
        struct Profile: Encodable {
            let name: String, birthYear: Int, sex: String, heightCm: Double, weightKg: Double
            let bodyFatRange: String?, goal: String, experience: String, activity: String
            let injuries: String, perimenopause: Bool
        }
        struct Plan: Encodable {
            let programId: String, startDate: Date, daysPerWeek: Int, preferredWeekdays: [Int]
            let sessionMinutes: Int, fixedCommitments: [FixedCommitment], equipmentProfileId: String
            let equipment: [String], oneRepMaxes: [String: Double], nextSessionIndex: Int
        }
        struct Food: Encodable {
            let calories: Int, protein: Int, carbs: Int, fat: Int, fibre: Int, maintenance: Int
            let presetName: String, proteinPerKg: Double, startAtMaintenance: Bool
        }
        struct CheckIn: Encodable {
            let weekday: Int, sleepGoalHours: Double, stepsGoal: Int, metrics: [String], dailyCheckIns: Bool
        }
        struct CheckInRecord: Encodable {
            let date: Date, weightKg: Double?, sleepHours: Double?, steps: Int?
            let ratings: [String: Int], measurements: [String: Double], note: String
        }
        struct FoodRecord: Encodable {
            let loggedAt: Date, eatenAt: Date, meal: String, source: String, name: String, brand: String?, barcode: String?
            let grams: Double, kcal: Double, protein: Double, carbs: Double, fat: Double, fibre: Double, confidence: String?
        }
        struct SetRecord: Encodable {
            let exerciseId: String, setIndex: Int, weight: Double, reps: Int, rpe: Double?
        }
        struct WorkoutRecord: Encodable {
            let programId: String, week: Int, name: String, version: String, startedAt: Date, finishedAt: Date?
            let notes: String, sets: [SetRecord]
        }
        struct NoteRecord: Encodable { let exerciseId: String, text: String }
        let exportedAt: Date
        let app = "Steady Strength"
        let profile: Profile?
        let trainingPlan: Plan?
        let nutritionPlan: Food?
        let checkInSettings: CheckIn?
        let consents: [String: Date]
        let checkIns: [CheckInRecord]
        let foodEntries: [FoodRecord]
        let workouts: [WorkoutRecord]
        let exerciseNotes: [NoteRecord]
    }

    @MainActor
    static func write(_ context: ModelContext) throws -> URL {
        let p = try context.fetch(FetchDescriptor<UserProfile>()).first
        let t = try context.fetch(FetchDescriptor<TrainingPlan>()).first
        let n = try context.fetch(FetchDescriptor<NutritionPlan>()).first
        let c = try context.fetch(FetchDescriptor<CheckInSettings>()).first
        let s = try context.fetch(FetchDescriptor<AppSettings>()).first
        let checkIns = try context.fetch(FetchDescriptor<CheckInEntry>(sortBy: [SortDescriptor(\.date)]))
        let food = try context.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.eatenAt)]))
        let workouts = try context.fetch(FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\.startedAt)]))
        let notes = try context.fetch(FetchDescriptor<ExerciseNote>())
        let snapshot = Snapshot(
            exportedAt: .now,
            profile: p.map { Snapshot.Profile(name: $0.name, birthYear: $0.birthYear, sex: $0.sexRaw, heightCm: $0.heightCm,
                                   weightKg: $0.weightKg, bodyFatRange: $0.bodyFatRange, goal: $0.goalRaw,
                                   experience: $0.experienceRaw, activity: $0.activityRaw, injuries: $0.injuries,
                                   perimenopause: $0.perimenopause) },
            trainingPlan: t.map { Snapshot.Plan(programId: $0.programId, startDate: $0.startDate, daysPerWeek: $0.daysPerWeek,
                                        preferredWeekdays: $0.preferredWeekdays, sessionMinutes: $0.sessionMinutes,
                                        fixedCommitments: $0.fixedCommitments, equipmentProfileId: $0.equipmentProfileId,
                                        equipment: $0.equipment, oneRepMaxes: $0.oneRepMaxes,
                                        nextSessionIndex: $0.nextSessionIndex) },
            nutritionPlan: n.map { Snapshot.Food(calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat,
                                         fibre: $0.fibre, maintenance: $0.maintenance, presetName: $0.presetName,
                                         proteinPerKg: $0.proteinPerKg, startAtMaintenance: $0.startAtMaintenance) },
            checkInSettings: c.map { Snapshot.CheckIn(weekday: $0.weekday, sleepGoalHours: $0.sleepGoalHours, stepsGoal: $0.stepsGoal,
                                           metrics: $0.metrics, dailyCheckIns: $0.dailyCheckIns) },
            consents: s?.consents ?? [:],
            checkIns: checkIns.map { Snapshot.CheckInRecord(date: $0.date, weightKg: $0.weightKg, sleepHours: $0.sleepHours, steps: $0.steps,
                                                            ratings: $0.ratings, measurements: $0.measurements, note: $0.note) },
            foodEntries: food.map { Snapshot.FoodRecord(loggedAt: $0.loggedAt, eatenAt: $0.eatenAt, meal: $0.mealRaw, source: $0.sourceRaw,
                                                        name: $0.name, brand: $0.brand, barcode: $0.barcode, grams: $0.grams, kcal: $0.kcal,
                                                        protein: $0.protein, carbs: $0.carbs, fat: $0.fat, fibre: $0.fibre, confidence: $0.confidence) },
            workouts: workouts.map { w in
                Snapshot.WorkoutRecord(programId: w.programId, week: w.weekNumber, name: w.workoutName, version: w.versionRaw,
                                       startedAt: w.startedAt, finishedAt: w.finishedAt, notes: w.notes,
                                       sets: w.sets.sorted { ($0.slotOrder, $0.setIndex) < ($1.slotOrder, $1.setIndex) }
                                           .map { Snapshot.SetRecord(exerciseId: $0.exerciseId, setIndex: $0.setIndex, weight: $0.weight, reps: $0.reps, rpe: $0.rpe) })
            },
            exerciseNotes: notes.map { Snapshot.NoteRecord(exerciseId: $0.exerciseId, text: $0.text) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let stamp = ISO8601DateFormatter().string(from: .now).prefix(10)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SteadyStrength-export-\(stamp).json")
        try encoder.encode(snapshot).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
