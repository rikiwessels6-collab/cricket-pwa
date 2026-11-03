import XCTest
@testable import SteadyCore

final class ProgressTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

    func testSmoothingDampensASpike() {
        let pts = [WeightPoint(date: day(0), kg: 70), WeightPoint(date: day(1), kg: 72), WeightPoint(date: day(2), kg: 70)]
        let s = WeightTrend.smoothed(pts)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[0].kg, 70)
        XCTAssertLessThan(s[1].kg, 71)      // moves only part of the way to the spike
        XCTAssertGreaterThan(s[1].kg, 70)
        XCTAssertTrue(WeightTrend.smoothed([]).isEmpty)
    }

    func testWeeklyChangeNeedsEnoughData() {
        XCTAssertNil(WeightTrend.weeklyChange([WeightPoint(date: day(0), kg: 70), WeightPoint(date: day(7), kg: 69)], now: day(8)))
        let threeInThreeDays = [0.0, 1, 3].map { WeightPoint(date: day($0), kg: 70) }
        XCTAssertNil(WeightTrend.weeklyChange(threeInThreeDays, now: day(4)))
    }

    func testWeeklyChangeSlope() throws {
        let pts = [0.0, 7, 14, 21].enumerated().map { WeightPoint(date: day($1), kg: 80 - 0.5 * Double($0)) }
        let w = try XCTUnwrap(WeightTrend.weeklyChange(pts, now: day(22)))
        XCTAssertEqual(w, -0.5, accuracy: 0.001)
        XCTAssertTrue(WeightTrend.describe(weeklyChange: w).hasPrefix("Down about 0.5 kg"))
        XCTAssertTrue(WeightTrend.describe(weeklyChange: 0.02).hasPrefix("Steady"))
        XCTAssertTrue(WeightTrend.describe(weeklyChange: nil).contains("Add a few"))
    }

    func testMeasurementTotalIgnoresBlanks() {
        XCTAssertEqual(CheckInMath.measurementTotal(["Hips": 98.5, "Waist": 0, "Chest": 90]), 188.5, accuracy: 0.001)
    }

    func testCheckInDue() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let wed = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!   // a Wednesday
        XCTAssertEqual(cal.component(.weekday, from: wed), 4)
        // Check-in day is Tuesday (3); the latest Tuesday was 3 Nov.
        let tue = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!
        let lastWeek = cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9))!
        XCTAssertTrue(CheckInMath.isDue(weekday: 3, lastCheckIn: nil, now: wed, calendar: cal))
        XCTAssertTrue(CheckInMath.isDue(weekday: 3, lastCheckIn: lastWeek, now: wed, calendar: cal))
        XCTAssertFalse(CheckInMath.isDue(weekday: 3, lastCheckIn: tue, now: wed, calendar: cal))
    }
}
