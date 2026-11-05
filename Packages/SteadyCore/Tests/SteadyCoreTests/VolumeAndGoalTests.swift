import XCTest
@testable import SteadyCore

final class VolumeAndGoalTests: XCTestCase {
    private func lib() -> [String: Exercise] {
        let a = Exercise.custom(id: "custom-a", name: "A", primaryMuscle: "chest", secondaryMuscle: "triceps",
                                equipment: ["barbell"], loadable: true, unilateral: false, timed: false)
        let b = Exercise.custom(id: "custom-b", name: "B", primaryMuscle: "triceps", secondaryMuscle: nil,
                                equipment: ["cable"], loadable: true, unilateral: false, timed: false)
        let plank = Exercise.custom(id: "custom-p", name: "P", primaryMuscle: "abs", secondaryMuscle: nil,
                                    equipment: [], loadable: false, unilateral: false, timed: true)
        return [a.id: a, b.id: b, plank.id: plank]
    }

    func testDirectAndIndirectCredit() {
        let v = WeeklyVolume.compute(setCounts: ["custom-a": 4, "custom-b": 3], library: lib())
        XCTAssertEqual(v["chest"]?.direct, 4)
        XCTAssertEqual(v["triceps"]?.direct, 3)
        XCTAssertEqual(v["triceps"]?.indirect, 2)   // 4 sets x 0.5
        XCTAssertEqual(v["chest"]?.indirect, 0)
    }

    func testTimedAndUnknownExercisesAreIgnored() {
        let v = WeeklyVolume.compute(setCounts: ["custom-p": 5, "nope": 3, "custom-a": 0], library: lib())
        XCTAssertTrue(v.isEmpty)
    }

    func testBands() {
        XCTAssertEqual(VolumeReport.band(direct: 0), .none)
        XCTAssertEqual(VolumeReport.band(direct: 6), .low)
        XCTAssertEqual(VolumeReport.band(direct: 10), .inRange)
        XCTAssertEqual(VolumeReport.band(direct: 20), .inRange)
        XCTAssertEqual(VolumeReport.band(direct: 21), .high)
    }

    func testWeekListsEveryMuscleMostSetsFirst() {
        let rows = VolumeReport.week(setCounts: ["custom-a": 12, "custom-b": 3], library: lib(),
                                     muscles: ["chest", "triceps", "quads"])
        XCTAssertEqual(rows.map(\.muscle), ["chest", "triceps", "quads"])
        XCTAssertEqual(rows[0].band, .inRange)
        XCTAssertEqual(rows[1].band, .low)
        XCTAssertEqual(rows[2].band, .none)
    }

    func testPrettyName() {
        XCTAssertEqual(VolumeReport.prettyName("upper_chest"), "Upper chest")
        XCTAssertEqual(VolumeReport.prettyName("abs"), "Abs")
    }

    func testWeekRangeCoversSevenDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = TimeZone(identifier: "UTC")!
        let wed = cal.date(from: DateComponents(year: 2026, month: 11, day: 4))!
        let this = VolumeReport.weekRange(containing: wed, calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: this.start), 2)
        XCTAssertEqual(cal.dateComponents([.day], from: this.start, to: this.end).day, 7)
        XCTAssertTrue(this.start <= wed && wed < this.end)
        let last = VolumeReport.weekRange(containing: wed, weeksBack: 1, calendar: cal)
        XCTAssertEqual(last.end, this.start)
    }

    func testGoalSummariesAndTags() {
        for g in Goal.allCases {
            XCTAssertFalse(g.summary.isEmpty)
            XCTAssertFalse(g.programTag.isEmpty)
        }
        XCTAssertEqual(Goal.buildMuscle.programTag, "muscle")
    }

    func testCustomExerciseAddedWithoutReplacingBuiltIn() throws {
        let c = Exercise.custom(id: "custom-z", name: "Z", primaryMuscle: "quads", secondaryMuscle: nil,
                                equipment: ["machine"], loadable: true, unilateral: false, timed: false)
        XCTAssertTrue(c.isCustom)
        XCTAssertFalse(c.isMainLift)
    }
}
