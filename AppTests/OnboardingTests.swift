import XCTest
import SwiftData
import SteadyCore
@testable import SteadyStrength

@MainActor
final class OnboardingTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func bundledContent() throws -> BundledContent {
        let bundle = Bundle(for: AppLock.self)
        func data(_ name: String) throws -> Data {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json") ?? Bundle.main.url(forResource: name, withExtension: "json"))
            return try Data(contentsOf: url)
        }
        return try BundledContent(programs: data("programs"), library: data("exercise_library"),
                                  equipment: data("equipment"), checkIn: data("checkin_defaults"))
    }

    func testBundledContentShipsWithTheApp() throws {
        let c = try bundledContent()
        XCTAssertEqual(c.programs.count, 14)
        XCTAssertGreaterThan(c.library.count, 150)
    }

    func testSaveCreatesOnePersonsPlan() throws {
        let mc = try container()
        let ctx = mc.mainContext
        let content = try bundledContent()
        let d = OnboardingDraft()
        d.applyDefaults(from: content)
        d.name = "Sam"
        d.sex = .female
        d.birthYear = Calendar.current.component(.year, from: .now) - 40
        d.heightCm = 165
        d.weightKg = 68
        d.perimenopause = true
        d.applyPerimenopauseDefaults()
        d.goal = .fatLoss
        d.programId = "beginner-12wk-option-b"
        d.commitments = [FixedCommitment(name: "Yoga", weekday: 3, minutes: 60),
                         FixedCommitment(name: "Pilates", weekday: 4, minutes: 60)]
        try d.save(into: ctx, settings: nil)

        let profile = try XCTUnwrap(ctx.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertEqual(profile.name, "Sam")
        XCTAssertTrue(profile.perimenopause)
        let plan = try XCTUnwrap(ctx.fetch(FetchDescriptor<TrainingPlan>()).first)
        XCTAssertEqual(plan.programId, "beginner-12wk-option-b")
        XCTAssertEqual(plan.fixedCommitments.count, 2)
        XCTAssertEqual(plan.nextSessionIndex, 0)
        let food = try XCTUnwrap(ctx.fetch(FetchDescriptor<NutritionPlan>()).first)
        XCTAssertTrue(food.startAtMaintenance)
        XCTAssertEqual(food.calories, food.maintenance)           // two weeks at maintenance first
        XCTAssertEqual(food.protein, Int((1.8 * 68).rounded()))
        let settings = try XCTUnwrap(ctx.fetch(FetchDescriptor<AppSettings>()).first)
        XCTAssertTrue(settings.onboardingComplete)
        XCTAssertNotNil(settings.consents[DataType.profile.rawValue])
        let checkIn = try XCTUnwrap(ctx.fetch(FetchDescriptor<CheckInSettings>()).first)
        XCTAssertEqual(checkIn.weekday, 3)                         // Tuesday, from the workbook
        XCTAssertTrue(checkIn.dailyCheckIns)
    }

    func testStrengthStepOnlyForPercentPrograms() throws {
        let content = try bundledContent()
        let d = OnboardingDraft()
        d.programId = "beginner-12wk-option-b"
        XCTAssertFalse(d.needsStrengths(content))
        d.programId = "rw-12-week"
        XCTAssertTrue(d.needsStrengths(content))
        d.strengthWeight = ["squat": 100]
        d.strengthReps = ["squat": 5]
        XCTAssertEqual(try XCTUnwrap(d.oneRepMaxes()["squat"]), 116.7, accuracy: 0.01)
    }

    func testRotationIndexWalksAcrossWeeks() throws {
        let content = try bundledContent()
        let b = try XCTUnwrap(content.program("beginner-12wk-option-b"))
        XCTAssertEqual(b.session(at: 0)?.workout.name, "Full Body A")
        XCTAssertEqual(b.session(at: 3)?.week.number, 2)
        XCTAssertNil(b.session(at: 36))
    }

    func testEraseRemovesEverything() throws {
        let mc = try container()
        let ctx = mc.mainContext
        let d = OnboardingDraft()
        d.name = "Sam"
        d.programId = "beginner-12wk-option-b"
        try d.save(into: ctx, settings: nil)
        try Persistence.eraseAll(ctx)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<UserProfile>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<TrainingPlan>()), 0)
    }
}
