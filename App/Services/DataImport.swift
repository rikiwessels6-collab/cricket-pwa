import Foundation
import SwiftData
import SteadyCore

/// "Restore from a backup": reads a file made by Export my data and rebuilds your profile, plans, workouts,
/// food, check-ins and notes on this phone. Progress photos are pictures kept inside the app; they are not
/// in the file, so photos already on this phone are left as they are.
enum DataImport {
    enum ImportError: LocalizedError {
        case notABackup
        var errorDescription: String? { "That file isn't a Steady Strength backup." }
    }

    struct Summary: Equatable {
        var workouts = 0, foodEntries = 0, checkIns = 0
        var text: String { "Restored \(workouts) workouts, \(foodEntries) food entries and \(checkIns) check-ins." }
    }

    static func decode(_ data: Data) throws -> DataExport.Snapshot {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let snap = try? d.decode(DataExport.Snapshot.self, from: data), snap.app == "Steady Strength",
              snap.profile != nil else { throw ImportError.notABackup }
        return snap
    }

    @MainActor
    static func restore(from url: URL, into context: ModelContext) throws -> Summary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let snap = try decode(try Data(contentsOf: url))
        do {
            return try apply(snap, into: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    @MainActor
    static func apply(_ snap: DataExport.Snapshot, into context: ModelContext) throws -> Summary {
        // Replace everything except settings and photos.
        try context.delete(model: UserProfile.self)
        try context.delete(model: TrainingPlan.self)
        try context.delete(model: NutritionPlan.self)
        try context.delete(model: CheckInSettings.self)
        try context.delete(model: FoodEntry.self)
        try context.delete(model: SavedFood.self)
        try context.delete(model: CheckInEntry.self)
        try context.delete(model: ExerciseNote.self)
        try context.delete(model: CustomExercise.self)
        try context.delete(model: SetLog.self)
        try context.delete(model: WorkoutLog.self)

        var summary = Summary()
        if let p = snap.profile {
            let profile = UserProfile(name: p.name, birthYear: p.birthYear, sex: Sex(rawValue: p.sex) ?? .female,
                                      heightCm: p.heightCm, weightKg: p.weightKg, bodyFatRange: p.bodyFatRange,
                                      goal: Goal(rawValue: p.goal) ?? .generalHealth,
                                      experience: Experience(rawValue: p.experience) ?? .new,
                                      activity: ActivityLevel(rawValue: p.activity) ?? .light,
                                      injuries: p.injuries, perimenopause: p.perimenopause)
            profile.goalChangedAt = p.goalChangedAt
            context.insert(profile)
        }
        if let t = snap.trainingPlan {
            let plan = TrainingPlan(programId: t.programId, startDate: t.startDate, daysPerWeek: t.daysPerWeek,
                                    preferredWeekdays: t.preferredWeekdays, sessionMinutes: t.sessionMinutes,
                                    fixedCommitments: t.fixedCommitments, avoidHeavyLegsNextToCommitments: false,
                                    equipmentProfileId: t.equipmentProfileId, equipment: t.equipment, oneRepMaxes: t.oneRepMaxes)
            plan.nextSessionIndex = t.nextSessionIndex
            if let u = t.upperIncrement { plan.upperIncrement = u }
            if let l = t.lowerIncrement { plan.lowerIncrement = l }
            context.insert(plan)
        }
        if let n = snap.nutritionPlan {
            context.insert(NutritionPlan(calories: n.calories, protein: n.protein, carbs: n.carbs, fat: n.fat, fibre: n.fibre,
                                         maintenance: n.maintenance, presetName: n.presetName, proteinPerKg: n.proteinPerKg,
                                         startAtMaintenance: n.startAtMaintenance))
        }
        if let c = snap.checkInSettings {
            context.insert(CheckInSettings(weekday: c.weekday, sleepGoalHours: c.sleepGoalHours, stepsGoal: c.stepsGoal,
                                           metrics: c.metrics, dailyCheckIns: c.dailyCheckIns))
        }
        for r in snap.customExercises ?? [] {
            let e = CustomExercise(name: r.name, primaryMuscle: r.primaryMuscle, secondaryMuscle: r.secondaryMuscle, kind: r.kind,
                                   loadable: r.loadable, unilateral: r.unilateral, timed: r.timed)
            e.exerciseId = r.exerciseId
            context.insert(e)
        }
        for r in snap.checkIns {
            let e = CheckInEntry(date: r.date, weightKg: r.weightKg, sleepHours: r.sleepHours, steps: r.steps,
                                 ratings: r.ratings, measurements: r.measurements, note: r.note)
            e.activeMinutes = r.activeMinutes
            e.healthWorkoutCount = r.healthWorkoutCount
            context.insert(e)
            summary.checkIns += 1
        }
        for r in snap.foodEntries {
            let item = FoodItem(id: r.foodId ?? r.barcode ?? "restored-\(UUID().uuidString.prefix(8))", name: r.name, brand: r.brand,
                                barcode: r.barcode, per100: Per100(kcal: 0, protein: 0, carbs: 0, fat: 0), servingGrams: nil, servingLabel: nil)
            let e = FoodEntry(item: item, grams: r.grams, meal: MealSlot(rawValue: r.meal) ?? .snacks,
                              source: FoodSource(rawValue: r.source) ?? .manual, eatenAt: r.eatenAt)
            e.loggedAt = r.loggedAt
            e.kcal = r.kcal; e.protein = r.protein; e.carbs = r.carbs; e.fat = r.fat; e.fibre = r.fibre
            e.confidence = r.confidence
            context.insert(e)
            summary.foodEntries += 1
        }
        for r in snap.savedFoods ?? [] {
            guard let item = try? JSONDecoder().decode(FoodItem.self, from: r.itemData) else { continue }
            let f = SavedFood(item: item, isCustom: r.isCustom)
            f.isFavourite = r.isFavourite; f.lastUsed = r.lastUsed; f.useCount = r.useCount
            context.insert(f)
        }
        for r in snap.exerciseNotes { context.insert(ExerciseNote(exerciseId: r.exerciseId, text: r.text)) }
        for r in snap.workouts {
            var swaps: [Int: String] = [:]
            for (k, v) in r.swaps ?? [:] { if let i = Int(k) { swaps[i] = v } }
            let log = WorkoutLog(programId: r.programId, weekNumber: r.week, workoutPosition: r.workoutPosition ?? 0,
                                 workoutName: r.name, version: SessionVersion(rawValue: r.version) ?? .standard, swaps: swaps)
            log.startedAt = r.startedAt
            log.finishedAt = r.finishedAt
            log.notes = r.notes
            log.loadFactor = r.loadFactor ?? 1
            log.readinessChoiceRaw = r.readinessChoice ?? ""
            log.readinessCode = r.readinessCode ?? ""
            log.acceptedSuggestions = r.accepted ?? []
            log.declinedSuggestions = r.declined ?? []
            log.isFreestyle = r.isFreestyle ?? false
            log.freeExerciseIds = r.freeExerciseIds ?? []
            context.insert(log)
            let perExercise = Dictionary(grouping: r.sets, by: \.exerciseId).mapValues(\.count)
            for s in r.sets {
                let set = SetLog(exerciseId: s.exerciseId, slotOrder: s.slotOrder ?? 0, setIndex: s.setIndex, weight: s.weight,
                                 reps: s.reps, rpe: s.rpe, targetSets: s.targetSets ?? perExercise[s.exerciseId] ?? 1,
                                 targetReps: s.targetReps, minReps: s.minReps, maxRPE: s.maxRPE)
                set.completedAt = s.completedAt ?? r.startedAt
                context.insert(set)
                set.workout = log
            }
            summary.workouts += 1
        }

        let all = try context.fetch(FetchDescriptor<AppSettings>())
        let settings: AppSettings
        if let existing = all.first { settings = existing } else { settings = AppSettings(); context.insert(settings) }
        if !snap.consents.isEmpty { settings.consents = snap.consents }
        if let st = snap.settings {
            settings.barWeightKg = st.barWeightKg; settings.plateStock = st.plateStock; settings.warmupStyleRaw = st.warmupStyle
            settings.remindersEnabled = st.remindersEnabled; settings.reminderHour = st.reminderHour; settings.reminderMinute = st.reminderMinute
        }
        if settings.disclaimerAcceptedAt == nil { settings.disclaimerAcceptedAt = .now }
        settings.onboardingComplete = true
        try context.save()
        return summary
    }
}
