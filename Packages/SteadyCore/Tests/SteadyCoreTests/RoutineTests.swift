import XCTest
@testable import SteadyCore

final class RoutineTests: XCTestCase {
    func testShorterVersionsGetShorterRoutines() {
        let full = Routine.steps(.warmup, version: .standard)
        let minimum = Routine.steps(.warmup, version: .minimum)
        XCTAssertGreaterThan(full.count, minimum.count)
        XCTAssertEqual(Routine.minutes(.warmup, version: .standard), 7)
        XCTAssertEqual(Routine.minutes(.cooldown, version: .minimum), 2)
        XCTAssertFalse(Routine.steps(.cooldown, version: .minimum).isEmpty)
    }

    func testStepIdsAreUnique() {
        for kind in [Routine.Kind.warmup, .cooldown] {
            let ids = Routine.steps(kind, version: .standard).map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count)
        }
    }
}
