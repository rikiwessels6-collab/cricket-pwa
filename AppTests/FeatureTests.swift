import XCTest
import SwiftData
import SteadyCore
@testable import SteadyStrength

@MainActor
final class FeatureTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func profile(goal: Goal = .generalHealth) -> UserProfile {
        UserProfile(name: "Sam", birthYear: 1985, sex: .female, heightCm: 168, weightKg: 70, bodyFatRange: nil,
                    goal: goal, experience: .intermediate, activity: .moderate, injuries: "", perimenopause: false)
    }

    private func nutrition(for p: UserProfile) -> NutritionPlan {
        let t = Nutrition.targets(p.stats, activity: p.activity, goal: .maintain)
        return NutritionPlan(targets: t, presetName: "Balanced", proteinPerKg: 1.8, startAtMaintenance: true)
    }

    func testGoalChangeRecomputesTargets() {
        let p = profile()
        let n = nutrition(for: p)
        let before = n.calories
        GoalSwitch.apply(.fatLoss, profile: p, nutrition: n, today: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(p.goal, .fatLoss)
        XCTAssertNotNil(p.goalChangedAt)
        XCTAssertLessThan(n.calories, before)
        XCTAssertFalse(n.startAtMaintenance)
        GoalSwitch.apply(.buildMuscle, profile: p, nutrition: n)
        XCTAssertGreaterThan(n.calories, before)
        XCTAssertEqual(n.protein, Int((1.8 * 70).rounded()))
    }

    func testGoalChangeWithoutNutritionPlanStillSavesGoal() {
        let p = profile()
        GoalSwitch.apply(.maintain, profile: p, nutrition: nil)
        XCTAssertEqual(p.goal, .maintain)
    }

    func testRemovingAnOpenWorkoutExerciseKeepsLaterSetsInPlace() throws {
        let c = try container()
        let log = WorkoutLog(programId: "open", weekNumber: 0, workoutPosition: 0, workoutName: "Open workout",
                             version: .standard, swaps: [:])
        log.isFreestyle = true
        log.freeExerciseIds = ["a", "b", "c"]
        c.mainContext.insert(log)
        let second = SetLog(exerciseId: "c", slotOrder: 2, setIndex: 0, weight: 50, reps: 8, rpe: nil,
                            targetSets: 3, targetReps: 12, minReps: 8, maxRPE: nil)
        c.mainContext.insert(second)
        second.workout = log
        FreeWorkout.remove(at: 1, from: log)
        XCTAssertEqual(log.freeExerciseIds, ["a", "c"])
        XCTAssertEqual(second.slotOrder, 1)
        // An exercise with sets can't be removed.
        FreeWorkout.remove(at: 1, from: log)
        XCTAssertEqual(log.freeExerciseIds, ["a", "c"])
    }

    func testBackupRoundTrip() throws {
        let c = try container()
        let ctx = c.mainContext
        let p = profile(goal: .buildMuscle)
        p.goalChangedAt = Date(timeIntervalSince1970: 1_700_000_000)
        ctx.insert(p)
        ctx.insert(nutrition(for: p))
        ctx.insert(TrainingPlan(programId: "ss-strength-foundations", startDate: .now, daysPerWeek: 3, preferredWeekdays: [2, 4, 6],
                                sessionMinutes: 60, fixedCommitments: [], avoidHeavyLegsNextToCommitments: false,
                                equipmentProfileId: "full_gym", equipment: ["barbell"], oneRepMaxes: ["squat": 100]))
        let custom = CustomExercise(name: "Cable crunch", primaryMuscle: "abs", secondaryMuscle: nil, kind: "cable",
                                    loadable: true, unilateral: false, timed: false)
        ctx.insert(custom)
        let log = WorkoutLog(programId: "open", weekNumber: 0, workoutPosition: 0, workoutName: "Open workout",
                             version: .standard, swaps: [3: "swapped-id"])
        log.isFreestyle = true
        log.freeExerciseIds = [custom.exerciseId]
        log.finishedAt = .now
        ctx.insert(log)
        let set = SetLog(exerciseId: custom.exerciseId, slotOrder: 0, setIndex: 0, weight: 40, reps: 10, rpe: 8,
                         targetSets: 3, targetReps: 12, minReps: 8, maxRPE: nil)
        ctx.insert(set)
        set.workout = log
        try ctx.save()

        let url = try DataExport.write(ctx)
        defer { try? FileManager.default.removeItem(at: url) }

        // Restore into a different, empty store.
        let other = try container()
        let summary = try DataImport.restore(from: url, into: other.mainContext)
        XCTAssertEqual(summary.workouts, 1)
        let profiles = try other.mainContext.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(profiles.first?.goal, .buildMuscle)
        XCTAssertNotNil(profiles.first?.goalChangedAt)
        let logs = try other.mainContext.fetch(FetchDescriptor<WorkoutLog>())
        XCTAssertEqual(logs.first?.isFreestyle, true)
        XCTAssertEqual(logs.first?.swaps[3], "swapped-id")
        XCTAssertEqual(logs.first?.sets.first?.targetSets, 3)
        XCTAssertEqual(logs.first?.sets.first?.rpe, 8)
        let customs = try other.mainContext.fetch(FetchDescriptor<CustomExercise>())
        XCTAssertEqual(customs.first?.exerciseId, custom.exerciseId)
        let settings = try other.mainContext.fetch(FetchDescriptor<AppSettings>())
        XCTAssertEqual(settings.first?.onboardingComplete, true)
        // Restoring twice doesn't double anything up.
        _ = try DataImport.restore(from: url, into: other.mainContext)
        XCTAssertEqual(try other.mainContext.fetch(FetchDescriptor<WorkoutLog>()).count, 1)
    }

    func testNotABackupIsRejected() {
        XCTAssertThrowsError(try DataImport.decode(Data("{\"hello\": 1}".utf8)))
    }
}
