import XCTest
@testable import SteadyCore

final class SleepTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))! }

    func testOverlappingDevicesAreCountedOnce() {
        let watch = DateInterval(start: at(1, 23), end: at(2, 7))
        let phone = DateInterval(start: at(1, 23, 30), end: at(2, 6, 30))
        let n = SleepMath.nights([watch, phone], calendar: cal)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n[0].hours, 8, accuracy: 0.001)
        XCTAssertEqual(n[0].night, cal.startOfDay(for: at(1, 0)))
    }

    func testNapsAreSeparateAndIgnoredByTheAverage() {
        let night = DateInterval(start: at(1, 23), end: at(2, 7))
        let nap = DateInterval(start: at(2, 14), end: at(2, 14, 30))
        let n = SleepMath.nights([night, nap], calendar: cal)
        XCTAssertEqual(n.count, 2)
        XCTAssertEqual(n.map(\.hours).sorted(), [0.5, 8])
        XCTAssertEqual(SleepMath.average(n) ?? 0, 8, accuracy: 0.001)
        XCTAssertNil(SleepMath.average([SleepNight(night: at(1, 0), hours: 1)]))
    }

    func testSplitSleepWithAWakingGapAddsUp() {
        let a = DateInterval(start: at(3, 22, 30), end: at(4, 2))
        let b = DateInterval(start: at(4, 3), end: at(4, 6, 30))
        let n = SleepMath.nights([b, a], calendar: cal)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n[0].hours, 7, accuracy: 0.001)
    }
}
