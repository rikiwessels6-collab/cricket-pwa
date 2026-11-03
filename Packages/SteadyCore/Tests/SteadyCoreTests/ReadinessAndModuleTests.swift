import XCTest
@testable import SteadyCore

final class ReadinessAndModuleTests: XCTestCase {
    func ex(_ id: String, tier: String = "accessory", primary: [String], secondary: [String] = [],
            timed: Bool = false, pattern: String = "isolation") -> Exercise {
        let json = """
        {"id":"\\(id)","name":"\\(id)","pattern":"\\(pattern)","tier":"\\(tier)","equipment":[],
         "primaryMuscles":\\(primary.map { "\\"\\($0)\\"" }),"secondaryMuscles":\\(secondary.map { "\\"\\($0)\\"" }),
         "unilateral":false,"loadable":true,"timed":\\(timed),"difficulty":1,"cues":"","cueSource":"",
         "seed":false,"aliases":[],"demoSearchQuery":"","substitutes":[],"usedIn":[]}
        """
        return try! JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
    }

    func planned(_ id: String, sets: Int, order: Int, main: Bool = false) -> PlannedExercise {
        var p = PlannedExercise(moduleExerciseId: id, name: id, id: order, sets: sets, repMin: 8, repMax: 12, restSeconds: 90)
        p.isMainLift = main
        return p
    }

    func testReadinessPainStopsAndSuggestsRest() {
        let a = Readiness.advise(ReadinessAnswers(concern: .pain))
        XCTAssertEqual(a.suggested, .rest)
        XCTAssertEqual(a.stopMessage, Readiness.stopMessage)
        XCTAssertNotNil(Readiness.advise(ReadinessAnswers(note: "some chest tightness")).stopMessage)
    }

    func testReadinessLevels() {
        XCTAssertEqual(Readiness.advise(ReadinessAnswers()).suggested, .asPlanned)
        XCTAssertEqual(Readiness.advise(ReadinessAnswers(sleep: .low, energy: .low)).suggested, .fewerSets)
        XCTAssertEqual(Readiness.advise(ReadinessAnswers(sleep: .okay, energy: .okay)).suggested, .lowerLoad)
        XCTAssertEqual(Readiness.advise(ReadinessAnswers(concern: .jointDiscomfort)).suggested, .comfortableSubstitute)
        XCTAssertEqual(Readiness.Choice.lowerLoad.loadFactor, 0.9)
        XCTAssertEqual(Readiness.Choice.fewerSets.version, .lowEnergy)
    }

    func testOnRampCapsSetsOnlyInWeeksOneToFour() {
        let plan = [planned("a", sets: 4, order: 1)]
        XCTAssertEqual(SessionBuilder.applyOnRamp(plan, week: 2)[0].sets, 2)
        XCTAssertEqual(SessionBuilder.applyOnRamp(plan, week: 5)[0].sets, 4)
    }

    func testMergeReplacesOverlapAddsModuleAndNeverTouchesMainLifts() {
        let lib = ["squat": ex("squat", tier: "main", primary: ["quads"]),
                   "curl": ex("curl", primary: ["biceps"]),
                   "ext": ex("ext", primary: ["quads"]),
                   "row": ex("row", primary: ["lats"])]
        let base = [planned("squat", sets: 3, order: 0, main: true), planned("ext", sets: 3, order: 1), planned("curl", sets: 3, order: 2)]
        let r = ModuleMerger.merge(base: base, module: [ModuleSlot(exerciseId: "row", sets: 3, repMin: 8, repMax: 12)],
                                   targets: ["lats"], library: lib)
        XCTAssertEqual(r.plan.map(\.exerciseId), ["squat", "ext", "curl", "row"])
        let q = ModuleMerger.merge(base: base, module: [ModuleSlot(exerciseId: "ext", sets: 4, repMin: 8, repMax: 12)],
                                   targets: ["quads"], library: lib)
        XCTAssertTrue(q.plan.contains { $0.exerciseId == "squat" })
        XCTAssertEqual(q.change.removed, ["ext"])
        // merging again from the original base gives the same result (no duplicated sets)
        XCTAssertEqual(q.plan, ModuleMerger.merge(base: base, module: [ModuleSlot(exerciseId: "ext", sets: 4, repMin: 8, repMax: 12)],
                                                  targets: ["quads"], library: lib).plan)
    }

    func testMergeTrimsToTimeLimit() {
        let lib = ["a": ex("a", primary: ["lats"]), "b": ex("b", primary: ["biceps"]), "m": ex("m", primary: ["delts"])]
        let base = (0..<4).map { planned("a", sets: 4, order: $0) }
        let r = ModuleMerger.merge(base: base, module: [ModuleSlot(exerciseId: "m", sets: 4, repMin: 8, repMax: 12)],
                                   targets: ["delts"], library: lib, rules: RuleSet(sessionLimitMinutes: 40))
        XCTAssertFalse(r.change.trimmed.isEmpty)
        XCTAssertLessThanOrEqual(r.change.minutesAfter, 40)
    }

    func testNoModuleMeansBaseSession() {
        let base = [planned("a", sets: 3, order: 0)]
        XCTAssertEqual(ModuleMerger.resolve(base: base, module: nil, sessionIndex: 0, library: [:]).plan, base)
    }

    func testDirectAndIndirectVolumeAreSeparate() {
        let lib = ["bench": ex("bench", primary: ["chest", "triceps"], secondary: ["delts"]),
                   "plank": ex("plank", primary: ["abs"], timed: true)]
        let v = WeeklyVolume.compute([[planned("bench", sets: 4, order: 0), planned("plank", sets: 3, order: 1)]], library: lib)
        XCTAssertEqual(v["chest"]?.direct, 4)
        XCTAssertEqual(v["triceps"]?.indirect, 2)
        XCTAssertEqual(v["triceps"]?.direct, 0)
        XCTAssertEqual(v["delts"]?.indirect, 2)
        XCTAssertNil(v["abs"])
    }

    func testReviewPromptIsAdvisoryAboveThreshold() {
        let prompts = WeeklyVolume.reviewPrompts(["quads": MuscleVolume(direct: 24, indirect: 0), "lats": MuscleVolume(direct: 10, indirect: 0)])
        XCTAssertEqual(prompts.map(\.muscle), ["quads"])
    }
}
