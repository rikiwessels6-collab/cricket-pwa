import XCTest
@testable import SteadyCore

final class StatsPlatesWarmupTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func day(_ d: Int, hour: Int = 9) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))! }

    func testSessionsGroupByDayAndIgnoreEmptySets() {
        let sets = [StatSet(date: day(1, hour: 9), weight: 100, reps: 5), StatSet(date: day(1, hour: 10), weight: 90, reps: 8),
                    StatSet(date: day(3), weight: 105, reps: 3), StatSet(date: day(3), weight: 50, reps: 0)]
        let s = ExerciseStats.sessions(sets, calendar: cal)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].topWeight, 100)
        XCTAssertEqual(s[0].volume, 100 * 5 + 90 * 8)
        XCTAssertEqual(s[0].bestReps, 8)
        XCTAssertEqual(s[0].estimatedOneRepMax, max(Strength.epley(weight: 100, reps: 5), Strength.epley(weight: 90, reps: 8)), accuracy: 0.001)
        XCTAssertEqual(s[1].topWeight, 105)
    }

    func testHighRepSetsDontCountForOneRepMax() {
        let s = ExerciseStats.sessions([StatSet(date: day(1), weight: 40, reps: 20)], calendar: cal)
        XCTAssertEqual(s[0].estimatedOneRepMax, 0)
        XCTAssertEqual(s[0].volume, 800)
    }

    func testRecordsAndRanges() {
        let sessions = ExerciseStats.sessions([StatSet(date: day(1), weight: 100, reps: 5), StatSet(date: day(10), weight: 110, reps: 3),
                                               StatSet(date: day(20), weight: 105, reps: 5)], calendar: cal)
        let r = ExerciseStats.records(sessions)
        XCTAssertEqual(r.weight?.topWeight, 110)
        XCTAssertEqual(r.oneRepMax?.date, day(20).startOfDayUTC(cal))
        let now = day(25)
        XCTAssertEqual(ExerciseStats.filter(sessions, range: .all, now: now).count, 3)
        XCTAssertEqual(ExerciseStats.filter(sessions, range: .threeMonths, now: now).count, 3)
        XCTAssertEqual(ExerciseStats.filter(sessions, range: .threeMonths, now: cal.date(byAdding: .day, value: 200, to: now)!).count, 0)
        XCTAssertEqual(StatMetric.weight.value(sessions[1]), 110)
    }

    func testPlateLoading() {
        let l = BarLoading.load(target: 100, bar: 20, stock: BarLoading.defaultStock)      // 40 a side = 25 + 15
        XCTAssertEqual(l.perSide.map(\.weight), [25, 15])
        XCTAssertTrue(l.isExact)
        XCTAssertEqual(l.loaded, 100)
        let odd = BarLoading.load(target: 101, bar: 20, stock: BarLoading.defaultStock)    // 40.5 a side; smallest is 1.25
        XCTAssertFalse(odd.isExact)
        XCTAssertEqual(odd.loaded, 100)
        XCTAssertEqual(odd.shortfall, 1, accuracy: 0.001)
        XCTAssertTrue(BarLoading.load(target: 15, bar: 20, stock: BarLoading.defaultStock).perSide.isEmpty)
    }

    func testPlateLoadingRespectsWhatYouOwn() {
        let few = [PlateStock(weight: 20, pairs: 1), PlateStock(weight: 5, pairs: 1)]
        let l = BarLoading.load(target: 120, bar: 20, stock: few)      // wants 50 a side, owns 25
        XCTAssertEqual(l.perSide.map(\.count), [1, 1])
        XCTAssertEqual(l.loaded, 70)
        XCTAssertEqual(l.shortfall, 50, accuracy: 0.001)
    }

    func testWarmupStyles() {
        let p = Warmup.sets(style: .percent, working: 100, bar: 20)
        XCTAssertEqual(p.map(\.weight), [45, 65, 85])
        XCTAssertEqual(p.map(\.reps), [5, 3, 2])
        XCTAssertTrue(Warmup.sets(style: .percent, working: 20, bar: 20).isEmpty)
        let light = Warmup.sets(style: .percent, working: 30, bar: 20)
        XCTAssertTrue(light.allSatisfy { $0.weight >= 20 && $0.weight < 30 })
        XCTAssertFalse(Warmup.sets(style: .ramp, working: 100, bar: 20).isEmpty)
    }
}

private extension Date {
    func startOfDayUTC(_ cal: Calendar) -> Date { cal.startOfDay(for: self) }
}
