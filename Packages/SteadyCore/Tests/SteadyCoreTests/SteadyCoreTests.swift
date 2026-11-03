import XCTest
@testable import SteadyCore

/// Repo-root/Resources/Generated, found relative to this file.
private let generated: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Generated")

final class ContentTests: XCTestCase {
    static var content: BundledContent!

    override class func setUp() {
        super.setUp()
        content = try! BundledContent(directory: generated)
    }

    var content: BundledContent { Self.content }

    func testAllProgramsDecode() {
        XCTAssertEqual(content.programs.count, 14)
        let slots = content.programs.flatMap { $0.weeks.flatMap { $0.workouts.flatMap(\.slots) } }
        XCTAssertEqual(slots.count, 4012)
        XCTAssertFalse(slots.contains { if case .unknown = $0.reps.scheme { return true } else { return false } })
    }

    func testEverySlotIsInTheLibrary() {
        for p in content.programs {
            for w in p.weeks { for wo in w.workouts { for s in wo.slots {
                XCTAssertNotNil(content.library[s.exerciseId], "\(p.id) \(s.exercise)")
            } } }
        }
    }

    func testProgramShapes() throws {
        let b = try XCTUnwrap(content.program("beginner-12wk-option-b"))
        XCTAssertEqual(b.sessionsPerWeek, 3...3)
        XCTAssertEqual(b.weeks.first?.workouts.map(\.name), ["Full Body A", "Full Body B", "Full Body C"])
        let twelve = try XCTUnwrap(content.program("rw-12-week"))
        XCTAssertEqual(twelve.sessionsPerWeek, 5...6)
        XCTAssertTrue(twelve.requiresOneRepMax)
        XCTAssertFalse(b.requiresOneRepMax)
    }

    func testGuidePrograms() throws {
        let ids = ["ss-strength-foundations", "ss-build-and-grow", "ss-lower-body-focus", "ss-muscle-builder-pro", "ss-strong-for-life"]
        for id in ids {
            let p = try XCTUnwrap(content.program(id), id)
            XCTAssertEqual(p.weeks.count, 12, id)
            XCTAssertNotNil(p.description)
            XCTAssertTrue(p.weeks.allSatisfy { w in w.workouts.allSatisfy { $0.slots.allSatisfy { $0.effort?.type == .rir } } })
        }
        let life = try XCTUnwrap(content.program("ss-strong-for-life"))
        XCTAssertEqual(life.weeks[0].workouts.map { $0.optional ?? false }, [false, false, true])
        // Two-day plan skips the optional C; three-day plan includes it.
        XCTAssertEqual(life.session(at: 2, includeOptional: false)?.week.number, 2)
        XCTAssertEqual(life.session(at: 2, includeOptional: true)?.workout.name, "Full Body C")
        let grow = try XCTUnwrap(content.program("ss-build-and-grow"))
        XCTAssertEqual(grow.weeks[3].lowFatigueOptional, true)
        XCTAssertEqual(grow.weeks[0].workouts[0].slots.first?.exerciseId, "bench_press")
        XCTAssertEqual(grow.weeks[0].workouts[0].slots.first?.isMainLift, true)
    }

    func testRepSchemesAndDisplay() throws {
        let twelve = try XCTUnwrap(content.program("rw-12-week"))
        let pullUp = twelve.weeks[0].workouts[0].slots[4]
        XCTAssertEqual(pullUp.reps.scheme, .range(4, 6))
        XCTAssertEqual(pullUp.reps.display, "4-6")
        XCTAssertNotNil(pullUp.reps.repairedFrom)
        let squat = twelve.weeks[0].workouts[0].slots[0]
        XCTAssertEqual(squat.pct1RM?.lift, "squat")
        XCTAssertEqual(squat.effort?.display, "RPE 7")
        XCTAssertEqual(squat.rest?.display, "3-4 min")
        let b = try XCTUnwrap(content.program("beginner-12wk-option-b"))
        XCTAssertEqual(b.weeks[0].workouts[1].slots[3].reps.display, "8-10 each side")
    }

    func testEquipmentProfilesAndCheckInDefaults() {
        XCTAssertEqual(content.equipment.profiles.map(\.id), ["full_gym", "basic_gym", "hotel_gym", "home_dumbbells", "travel"])
        XCTAssertEqual(content.checkIn.checkInDay, "Tuesday")
        XCTAssertEqual(content.checkIn.dailyStepsGoal, 10500)
        XCTAssertEqual(content.checkIn.measurementSites.count, 8)
    }
}

final class SubstitutionTests: XCTestCase {
    var content: BundledContent { ContentTests.content }

    override class func setUp() {
        super.setUp()
        if ContentTests.content == nil { ContentTests.content = try! BundledContent(directory: generated) }
    }

    func kit(_ id: String) -> Set<String> { Set(content.equipment.profile(id)!.equipment) }

    /// Same answers as tools/importer/test_importer.py (test_curated_order_wins etc.).
    func testMatchesPythonReference() {
        let lib = content.library
        XCTAssertEqual(Substitution.choose("trap_bar_deadlift", library: lib, available: kit("basic_gym")).id, "deadlift")
        XCTAssertEqual(Substitution.choose("back_squat", library: lib, available: kit("hotel_gym")).id, "goblet_squat")
        XCTAssertEqual(Substitution.choose("bench_press", library: lib, available: kit("travel")).id, "push_up")
        XCTAssertEqual(Substitution.choose("box_jump", library: lib, available: kit("travel")).id, "squat_jump")
        let kept = Substitution.choose("goblet_squat", library: lib, available: kit("full_gym"))
        XCTAssertEqual(kept.id, "goblet_squat")
        XCTAssertEqual(kept.reason, .asWritten)
        let busy = Substitution.choose("leg_press", library: lib, available: kit("full_gym"), exclude: ["leg_press"])
        XCTAssertEqual(busy.id, "hack_squat")   // guide section 5: leg press -> hack squat
        XCTAssertEqual(busy.reason, .coachSwap)
    }

    func testEverySlotHasAnOptionEverywhere() {
        for p in content.programs {
            for w in p.weeks { for wo in w.workouts { for s in wo.slots {
                for prof in content.equipment.profiles {
                    let r = Substitution.choose(s.exerciseId, library: content.library, available: Set(prof.equipment),
                                                maxDifficulty: p.maxSwapDifficulty ?? 3,
                                                slotAlternatives: s.alternativeIds ?? [])
                    XCTAssertNotNil(r.id, "\(p.id) \(s.exercise) at \(prof.id)")
                }
            } } }
        }
    }

    func testAlternativesRequirement() {
        XCTAssertTrue(Substitution.satisfied(["dumbbells/kettlebell"], available: ["kettlebell"]))
        XCTAssertFalse(Substitution.satisfied(["barbell", "rack"], available: ["barbell"]))
        XCTAssertTrue(Substitution.satisfied([], available: []))
    }
}

final class NutritionTests: XCTestCase {
    func testMifflinMatchesWorkbook() {
        // Check-in workbook sample: male, 37, 179 cm, 83 kg, moderate -> BMR 1768.75, TDEE 2741.56
        let s = BodyStats(weightKg: 83, heightCm: 179, age: 37, sex: .male)
        XCTAssertEqual(Nutrition.bmr(s), 1768.75, accuracy: 0.001)
        XCTAssertEqual(Nutrition.tdee(s, .moderate), 2741.5625, accuracy: 0.001)
        let f = BodyStats(weightKg: 68, heightCm: 165, age: 40, sex: .female)
        XCTAssertEqual(Nutrition.bmr(f), 1350.25, accuracy: 0.001)
    }

    func testFatLossIsModerateAndProteinFirst() {
        let f = BodyStats(weightKg: 68, heightCm: 165, age: 40, sex: .female)
        let t = Nutrition.targets(f, activity: .light, goal: .fatLoss, proteinPerKg: 1.8)
        XCTAssertEqual(t.maintenance, 1857)
        XCTAssertEqual(t.calories, 1532)              // 17.5% below
        XCTAssertEqual(t.protein, 122)                // 1.8 g/kg
        XCTAssertEqual(t.fibre, 21)                   // 14 g per 1000 kcal
        let kcal = 4 * t.protein + 4 * t.carbs + 9 * t.fat
        XCTAssertEqual(Double(kcal), Double(t.calories), accuracy: 6)
    }

    func testSafeFloor() {
        let small = BodyStats(weightKg: 55, heightCm: 160, age: 40, sex: .female)
        let t = Nutrition.targets(small, activity: .sedentary, goal: .fatLoss)
        XCTAssertEqual(t.calories, 1500)
        XCTAssertTrue(t.warnings.contains(.raisedToFloor(floor: 1500)))
        let o = Nutrition.targets(small, activity: .sedentary, goal: .fatLoss, calorieOverride: 1300, allowBelowFloor: true)
        XCTAssertEqual(o.calories, 1300)
        XCTAssertTrue(o.warnings.contains(.belowFloor(floor: 1500)))
        let m = Nutrition.targets(BodyStats(weightKg: 70, heightCm: 170, age: 41, sex: .male), activity: .sedentary, goal: .fatLoss)
        XCTAssertGreaterThanOrEqual(m.calories, 1800)
    }

    func testKetoKeepsProteinAndFlagsIt() {
        let s = BodyStats(weightKg: 90, heightCm: 182, age: 41, sex: .male)
        let keto = MacroPreset.all.first { $0.name == "Keto" }!
        let t = Nutrition.targets(s, activity: .moderate, goal: .maintain, proteinPerKg: 2.0, preset: keto)
        XCTAssertEqual(t.protein, 180)
        XCTAssertTrue(t.warnings.contains(.proteinAbovePreset))
        XCTAssertGreaterThanOrEqual(t.carbs, 0)
    }
}

final class TrainingTests: XCTestCase {
    func testEpley() {
        XCTAssertEqual(Strength.epley(weight: 100, reps: 5), 116.667, accuracy: 0.01)
        XCTAssertEqual(Strength.epley(weight: 100, reps: 1), 100)
        XCTAssertEqual(Strength.epley(weight: 100, reps: 0), 0)
    }

    func testPercentLoadRoundsDown() {
        XCTAssertEqual(Strength.load(percent: 0.825, oneRepMax: 140), 115)   // 115.5 -> 115
        XCTAssertEqual(Strength.load(percent: 0.8, oneRepMax: 100), 80)
    }

    func testAdvisor() {
        let content = try! BundledContent(directory: generated)
        let new3 = ProgramAdvisor.recommend(experience: .new, daysPerWeek: 3, programs: content.programs)
        XCTAssertEqual(new3.first?.programId, "ss-strength-foundations")
        let new2 = ProgramAdvisor.recommend(experience: .new, daysPerWeek: 2, programs: content.programs)
        XCTAssertEqual(new2.first?.programId, "ss-strong-for-life")
        let adv5 = ProgramAdvisor.recommend(experience: .advanced, daysPerWeek: 5, programs: content.programs)
        XCTAssertEqual(adv5.first?.programId, "rw-intermediate-18wk")
        XCTAssertFalse(new3.contains { $0.programId.hasPrefix("rw-12") })
    }

    func testLockPolicy() {
        let p = LockPolicy(timeout: 60)
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(p.shouldLock(backgroundedAt: nil, now: t0))
        XCTAssertFalse(p.shouldLock(backgroundedAt: t0, now: t0.addingTimeInterval(59)))
        XCTAssertTrue(p.shouldLock(backgroundedAt: t0, now: t0.addingTimeInterval(60)))
        XCTAssertTrue(LockPolicy(timeout: 0).shouldLock(backgroundedAt: t0, now: t0))
    }
}
