import Foundation
import SwiftData

/// "Export my data": everything the app holds about you, as one JSON file you
/// can save or share from the share sheet. Nothing is uploaded anywhere.
enum DataExport {
    struct Snapshot: Codable {
        struct Profile: Codable {
            let name: String, birthYear: Int, sex: String, heightCm: Double, weightKg: Double
            let bodyFatRange: String?, goal: String, experience: String, activity: String
            let injuries: String, perimenopause: Bool
            var goalChangedAt: Date? = nil
        }
        struct Plan: Codable {
            let programId: String, startDate: Date, daysPerWeek: Int, preferredWeekdays: [Int]
            let sessionMinutes: Int, fixedCommitments: [FixedCommitment], equipmentProfileId: String
            let equipment: [String], oneRepMaxes: [String: Double], nextSessionIndex: Int
            var upperIncrement: Double? = nil, lowerIncrement: Double? = nil
        }
        struct Food: Codable {
            let calories: Int, protein: Int, carbs: Int, fat: Int, fibre: Int, maintenance: Int
            let presetName: String, proteinPerKg: Double, startAtMaintenance: Bool
        }
        struct CheckIn: Codable {
            let weekday: Int, sleepGoalHours: Double, stepsGoal: Int, metrics: [String], dailyCheckIns: Bool
        }
        struct CheckInRecord: Codable {
            let date: Date, weightKg: Double?, sleepHours: Double?, steps: Int?
            let ratings: [String: Int], measurements: [String: Double], note: String
            let activeMinutes: Int?, healthWorkoutCount: Int?
        }
        struct FoodRecord: Codable {
            let loggedAt: Date, eatenAt: Date, meal: String, source: String, name: String, brand: String?, barcode: String?
            let grams: Double, kcal: Double, protein: Double, carbs: Double, fat: Double, fibre: Double, confidence: String?
            var foodId: String? = nil
        }
        struct SetRecord: Codable {
            let exerciseId: String, setIndex: Int, weight: Double, reps: Int, rpe: Double?
            var slotOrder: Int? = nil, completedAt: Date? = nil, targetSets: Int? = nil, targetReps: Int? = nil
            var minReps: Int? = nil, maxRPE: Double? = nil
        }
        struct WorkoutRecord: Codable {
            let programId: String, week: Int, name: String, version: String, startedAt: Date, finishedAt: Date?
            let notes: String, sets: [SetRecord]
            var workoutPosition: Int? = nil, swaps: [String: String]? = nil, loadFactor: Double? = nil
            var readinessChoice: String? = nil, readinessCode: String? = nil
            var accepted: [String]? = nil, declined: [String]? = nil
            var isFreestyle: Bool? = nil, freeExerciseIds: [String]? = nil
        }
        struct CustomRecord: Codable {
            let exerciseId: String, name: String, primaryMuscle: String, secondaryMuscle: String?
            let kind: String, loadable: Bool, unilateral: Bool, timed: Bool
        }
        struct SavedFoodRecord: Codable {
            let itemData: Data, isFavourite: Bool, isCustom: Bool, lastUsed: Date, useCount: Int
        }
        struct SettingsRecord: Codable {
            let barWeightKg: Double, plateStock: [String: Int], warmupStyle: String
            let remindersEnabled: Bool, reminderHour: Int, reminderMinute: Int
        }
        struct NoteRecord: Codable { let exerciseId: String, text: String }
        struct PhotoRecord: Codable { let date: Date, angle: String }   // the pictures stay in the app; only this list is exported
        let exportedAt: Date
        var app = "Steady Strength"
        let profile: Profile?
        let trainingPlan: Plan?
        let nutritionPlan: Food?
        let checkInSettings: CheckIn?
        let consents: [String: Date]
        let checkIns: [CheckInRecord]
        let foodEntries: [FoodRecord]
        let workouts: [WorkoutRecord]
        let exerciseNotes: [NoteRecord]
        let progressPhotos: [PhotoRecord]
        // Added in build 10; older exports don't have them.
        var customExercises: [CustomRecord]? = nil
        var savedFoods: [SavedFoodRecord]? = nil
        var settings: SettingsRecord? = nil
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
        let photos = try context.fetch(FetchDescriptor<ProgressPhoto>(sortBy: [SortDescriptor(\.date)]))
        let customs = try context.fetch(FetchDescriptor<CustomExercise>(sortBy: [SortDescriptor(\.createdAt)]))
        let saved = try context.fetch(FetchDescriptor<SavedFood>())
        let snapshot = Snapshot(
            exportedAt: .now,
            profile: p.map { Snapshot.Profile(name: $0.name, birthYear: $0.birthYear, sex: $0.sexRaw, heightCm: $0.heightCm,
                                   weightKg: $0.weightKg, bodyFatRange: $0.bodyFatRange, goal: $0.goalRaw,
                                   experience: $0.experienceRaw, activity: $0.activityRaw, injuries: $0.injuries,
                                   perimenopause: $0.perimenopause, goalChangedAt: $0.goalChangedAt) },
            trainingPlan: t.map { Snapshot.Plan(programId: $0.programId, startDate: $0.startDate, daysPerWeek: $0.daysPerWeek,
                                        preferredWeekdays: $0.preferredWeekdays, sessionMinutes: $0.sessionMinutes,
                                        fixedCommitments: $0.fixedCommitments, equipmentProfileId: $0.equipmentProfileId,
                                        equipment: $0.equipment, oneRepMaxes: $0.oneRepMaxes,
                                        nextSessionIndex: $0.nextSessionIndex,
                                        upperIncrement: $0.upperIncrement, lowerIncrement: $0.lowerIncrement) },
            nutritionPlan: n.map { Snapshot.Food(calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat,
                                         fibre: $0.fibre, maintenance: $0.maintenance, presetName: $0.presetName,
                                         proteinPerKg: $0.proteinPerKg, startAtMaintenance: $0.startAtMaintenance) },
            checkInSettings: c.map { Snapshot.CheckIn(weekday: $0.weekday, sleepGoalHours: $0.sleepGoalHours, stepsGoal: $0.stepsGoal,
                                           metrics: $0.metrics, dailyCheckIns: $0.dailyCheckIns) },
            consents: s?.consents ?? [:],
            checkIns: checkIns.map { Snapshot.CheckInRecord(date: $0.date, weightKg: $0.weightKg, sleepHours: $0.sleepHours, steps: $0.steps,
                                                            ratings: $0.ratings, measurements: $0.measurements, note: $0.note,
                                                            activeMinutes: $0.activeMinutes, healthWorkoutCount: $0.healthWorkoutCount) },
            foodEntries: food.map { Snapshot.FoodRecord(loggedAt: $0.loggedAt, eatenAt: $0.eatenAt, meal: $0.mealRaw, source: $0.sourceRaw,
                                                        name: $0.name, brand: $0.brand, barcode: $0.barcode, grams: $0.grams, kcal: $0.kcal,
                                                        protein: $0.protein, carbs: $0.carbs, fat: $0.fat, fibre: $0.fibre, confidence: $0.confidence,
                                                        foodId: $0.foodId) },
            workouts: workouts.map { w in
                Snapshot.WorkoutRecord(programId: w.programId, week: w.weekNumber, name: w.workoutName, version: w.versionRaw,
                                       startedAt: w.startedAt, finishedAt: w.finishedAt, notes: w.notes,
                                       sets: w.sets.sorted { ($0.slotOrder, $0.setIndex) < ($1.slotOrder, $1.setIndex) }
                                           .map { Snapshot.SetRecord(exerciseId: $0.exerciseId, setIndex: $0.setIndex, weight: $0.weight, reps: $0.reps, rpe: $0.rpe,
                                                                     slotOrder: $0.slotOrder, completedAt: $0.completedAt, targetSets: $0.targetSets,
                                                                     targetReps: $0.targetReps, minReps: $0.minReps, maxRPE: $0.maxRPE) },
                                       workoutPosition: w.workoutPosition,
                                       swaps: Dictionary(uniqueKeysWithValues: w.swaps.map { (String($0.key), $0.value) }),
                                       loadFactor: w.loadFactor, readinessChoice: w.readinessChoiceRaw, readinessCode: w.readinessCode,
                                       accepted: w.acceptedSuggestions, declined: w.declinedSuggestions,
                                       isFreestyle: w.isFreestyle, freeExerciseIds: w.freeExerciseIds)
            },
            exerciseNotes: notes.map { Snapshot.NoteRecord(exerciseId: $0.exerciseId, text: $0.text) },
            progressPhotos: photos.map { Snapshot.PhotoRecord(date: $0.date, angle: $0.angleRaw) },
            customExercises: customs.map { Snapshot.CustomRecord(exerciseId: $0.exerciseId, name: $0.name, primaryMuscle: $0.primaryMuscle,
                                                                 secondaryMuscle: $0.secondaryMuscle, kind: $0.kind, loadable: $0.loadable,
                                                                 unilateral: $0.unilateral, timed: $0.timed) },
            savedFoods: saved.map { Snapshot.SavedFoodRecord(itemData: $0.itemData, isFavourite: $0.isFavourite, isCustom: $0.isCustom,
                                                             lastUsed: $0.lastUsed, useCount: $0.useCount) },
            settings: s.map { Snapshot.SettingsRecord(barWeightKg: $0.barWeightKg, plateStock: $0.plateStock, warmupStyle: $0.warmupStyleRaw,
                                                      remindersEnabled: $0.remindersEnabled, reminderHour: $0.reminderHour,
                                                      reminderMinute: $0.reminderMinute) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let stamp = ISO8601DateFormatter().string(from: .now).prefix(10)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SteadyStrength-export-\(stamp).json")
        try encoder.encode(snapshot).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
