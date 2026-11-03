import XCTest
@testable import SteadyCore

final class RemindersTests: XCTestCase {
    func testSlotsForTrainingDaysAndCheckIn() {
        let s = Reminders.slots(trainingWeekdays: [4, 2, 2, 6], checkInWeekday: 3, hour: 7, minute: 30)
        XCTAssertEqual(s.map(\.weekday), [2, 4, 6, 3])           // sessions sorted, de-duplicated, then check-in
        XCTAssertEqual(Set(s.map(\.id)).count, s.count)
        XCTAssertTrue(s.allSatisfy { $0.hour == 7 && $0.minute == 30 && $0.id.hasPrefix(Reminders.idPrefix) })
    }

    func testBadInputIsClamped() {
        let s = Reminders.slots(trainingWeekdays: [0, 8, 5], checkInWeekday: 9, hour: 31, minute: -4)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].hour, 23)
        XCTAssertEqual(s[0].minute, 0)
        XCTAssertTrue(Reminders.slots(trainingWeekdays: [], checkInWeekday: nil, hour: 7, minute: 0).isEmpty)
    }
}
