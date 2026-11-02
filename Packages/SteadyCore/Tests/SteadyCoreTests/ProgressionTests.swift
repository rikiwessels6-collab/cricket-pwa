import XCTest
@testable import SteadyCore

final class ProgressionTests: XCTestCase {
    var content: BundledContent {
        if ContentTests.content == nil { ContentTests.content = try! BundledContent(directory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Generated")) }
        return ContentTests.content
    }

    /// Beginner B, week 1, Full Body A, goblet squat: 2 x 10-12 at RPE 6.
    var goblet: PlannedExercise {
        PlannedExercise(slot: content.program("beginner-12wk-option-b")!.weeks[0].workouts[0].slots[0])
    }

    func h(_ w: Double, _ reps: [Int], rpe: Double? = nil, sets: Int = 2) -> ExerciseHistory {
        ExerciseHistory(date: .now, sets: reps.map { LoggedSet(weight: w, reps: $0, rpe: rpe) }, targetSets: sets,
                        targetTop: Array(repeating: 12, count: sets), targetMin: Array(repeating: 10, count: sets), maxRPE: 6)
    }

    func testFirstTimeIsByFeel() {
        let s = Progression.suggest(for: goblet, exercise: content.library["goblet_squat"], history: [], oneRepMaxes: [:])
        XCTAssertEqual(s.kind, .byFeel)
        XCTAssertNil(s.weight)
        XCTAssertTrue(s.reason.contains("10-12"))
    }

    func testIncreaseHoldRetryDeload() {
        let ex = content.library["goblet_squat"]
        XCTAssertEqual(Progression.suggest(for: goblet, exercise: ex, history: [h(12, [12, 12])], oneRepMaxes: [:]),
                       LoadSuggestion(weight: 14.5, kind: .increase, reason: "You hit every rep last time. Add 2.5 kg."))
        XCTAssertEqual(Progression.suggest(for: goblet, exercise: ex, history: [h(12, [12, 11])], oneRepMaxes: [:]).kind, .hold)
        XCTAssertEqual(Progression.suggest(for: goblet, exercise: ex, history: [h(12, [9, 8])], oneRepMaxes: [:]).kind, .retry)
        let d = Progression.suggest(for: goblet, exercise: ex, history: [h(20, [9, 8]), h(20, [8, 8])], oneRepMaxes: [:])
        XCTAssertEqual(d.kind, .deload)
        XCTAssertEqual(d.weight, 17.5)
        XCTAssertEqual(Progression.suggest(for: goblet, exercise: ex, history: [h(12, [12])], oneRepMaxes: [:]).kind, .retry)
    }

    func testTooHardDoesNotCountAsHittingTop() {
        let s = Progression.suggest(for: goblet, exercise: content.library["goblet_squat"],
                                    history: [h(12, [12, 12], rpe: 9)], oneRepMaxes: [:])
        XCTAssertEqual(s.kind, .hold)
    }

    func testLowerBodyMainLiftsJumpFive() {
        XCTAssertEqual(Progression.increment(for: content.library["back_squat"]), 5)
        XCTAssertEqual(Progression.increment(for: content.library["bench_press"]), 2.5)
        XCTAssertEqual(Progression.increment(for: content.library["leg_extension"]), 2.5)
    }

    func testPercentProgramsUseOneRepMax() {
        let squat = PlannedExercise(slot: content.program("rw-12-week")!.weeks[0].workouts[0].slots[0])
        let s = Progression.suggest(for: squat, exercise: content.library["back_squat"], history: [], oneRepMaxes: ["squat": 140])
        XCTAssertEqual(s.kind, .percent)
        XCTAssertEqual(s.weight, 115)                   // 82.5% of 140 = 115.5 -> 115
        var swapped = squat
        swapped.exerciseId = "goblet_squat"            // swap: %1RM no longer applies
        XCTAssertEqual(Progression.suggest(for: swapped, exercise: content.library["goblet_squat"], history: [],
                                           oneRepMaxes: ["squat": 140]).kind, .byFeel)
    }

    func testWarmupRamp() {
        XCTAssertEqual(Progression.warmupSets(working: 100).map(\.weight), [20, 40, 60, 72.5])
        XCTAssertEqual(Progression.warmupSets(working: 20), [])
    }

    func testSessionVersions() throws {
        let wo = content.program("beginner-12wk-option-b")!.weeks[4].workouts[0]
        let lib = content.library
        let std = SessionBuilder.build(wo, version: .standard, library: lib)
        XCTAssertEqual(std.count, wo.slots.count)
        let low = SessionBuilder.build(wo, version: .lowEnergy, library: lib)
        XCTAssertTrue(low.allSatisfy { $0.sets <= 2 })
        XCTAssertEqual(low[0].effortMax, std[0].effortMax! - 1)
        let ex = SessionBuilder.build(wo, version: .express, library: lib)
        XCTAssertTrue(ex.allSatisfy { $0.isMainLift && $0.sets <= 2 })
        let min = SessionBuilder.build(wo, version: .minimum, library: lib)
        XCTAssertEqual(min.count, 3)
        XCTAssertTrue(SessionBuilder.corePatterns.contains(lib[min[2].exerciseId]!.pattern))
        XCTAssertLessThan(SessionBuilder.estimatedMinutes(min, version: .minimum),
                          SessionBuilder.estimatedMinutes(std, version: .standard))
    }

    func testTargets() {
        XCTAssertEqual(goblet.targetReps(set: 0), 12)
        XCTAssertEqual(goblet.minimumReps(set: 1), 10)
    }
}
