import XCTest
@testable import SteadyCore

final class ReturnToTrainingTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func date(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 8))! }

    func testNoAdviceWithoutHistoryOrShortGap() {
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!
        XCTAssertNil(ReturnToTraining.advice(lastSession: nil, now: now, calendar: cal))
        XCTAssertNil(ReturnToTraining.advice(lastSession: date(25), now: now, calendar: cal))     // 9 days
    }

    func testAdviceFromTwoWeeksAndLongerGapNote() throws {
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!
        let two = try XCTUnwrap(ReturnToTraining.advice(lastSession: date(20), now: now, calendar: cal))   // 14 days
        XCTAssertEqual(two.daysAway, 14)
        XCTAssertEqual(two.loadFactor, 0.9)
        XCTAssertFalse(two.message.contains("Low energy"))
        let long = try XCTUnwrap(ReturnToTraining.advice(lastSession: date(1), now: now, calendar: cal))   // 33 days
        XCTAssertTrue(long.message.contains("Low energy"))
        XCTAssertEqual(long.code, .missedReturnReduction)
    }
}
