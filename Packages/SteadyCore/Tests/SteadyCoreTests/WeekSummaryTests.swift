import XCTest
@testable import SteadyCore

final class WeekSummaryTests: XCTestCase {
    func testLastTimeGroupsSameWeights() {
        let sets = [LoggedSet(weight: 60, reps: 8), LoggedSet(weight: 60, reps: 8), LoggedSet(weight: 60, reps: 7),
                    LoggedSet(weight: 65, reps: 5)]
        XCTAssertEqual(LastTime.summary(sets), "60 kg × 8, 8, 7 · 65 kg × 5")
        XCTAssertEqual(LastTime.summary([LoggedSet(weight: 22.5, reps: 10)]), "22.5 kg × 10")
        XCTAssertEqual(LastTime.summary([LoggedSet(weight: 0, reps: 10), LoggedSet(weight: 0, reps: 8)]), "10, 8 reps")
        XCTAssertEqual(LastTime.summary([]), "")
    }

    func testHeadline() {
        var f = WeekFacts()
        f.plannedSessions = 4
        XCTAssertEqual(WeekSummary.headline(f), "A rest week")
        f.sessions = 3
        XCTAssertEqual(WeekSummary.headline(f), "3 of 4 sessions")
        f.sessions = 4
        XCTAssertEqual(WeekSummary.headline(f), "All 4 sessions done")
        f.plannedSessions = 0
        f.sessions = 2
        XCTAssertEqual(WeekSummary.headline(f), "2 sessions this week")
    }

    func testNotesCoverTrainingFoodAndWeight() {
        var f = WeekFacts()
        f.plannedSessions = 4; f.sessions = 3
        f.records = ["Bench press"]
        f.foodDays = 5; f.avgProtein = 140; f.proteinTarget = 150; f.daysProteinHit = 3
        f.avgKcal = 2200; f.kcalTarget = 2000
        f.goal = .fatLoss
        f.weightThisWeek = 79.4; f.weightPrevious = 79.9
        let notes = WeekSummary.notes(f)
        XCTAssertTrue(notes.contains { $0.contains("3 of 4") })
        XCTAssertTrue(notes.contains("New best on Bench press."))
        XCTAssertTrue(notes.contains { $0.contains("Protein averaged 140") && $0.contains("on target for 3 of 5") })
        XCTAssertTrue(notes.contains { $0.contains("200 over") })
        XCTAssertTrue(notes.contains { $0.contains("down 0.5 kg") && $0.contains("aiming for") })
    }

    func testLowProteinSuggestsAGap() {
        var f = WeekFacts()
        f.foodDays = 6; f.avgProtein = 90; f.proteinTarget = 150
        XCTAssertTrue(WeekSummary.notes(f).contains { $0.contains("easiest gap") })
    }

    func testEmptyWeekIsGentle() {
        let notes = WeekSummary.notes(WeekFacts())
        XCTAssertTrue(notes.contains { $0.contains("No sessions logged") })
        XCTAssertTrue(notes.contains("No food logged this week."))
        XCTAssertFalse(notes.isEmpty)
    }
}
