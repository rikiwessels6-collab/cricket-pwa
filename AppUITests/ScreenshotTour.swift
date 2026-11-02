import XCTest

/// Walks through the app and saves a PNG of each screen to $SCREENSHOT_DIR
/// (set by CI via TEST_RUNNER_SCREENSHOT_DIR). Skipped when it isn't set.
final class ScreenshotTour: XCTestCase {
    var dir: String?
    var count = 0

    func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir else { return }
        count += 1
        let data = app.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%02d-%@.png", count, name)))
    }

    func testTour() throws {
        dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
        try XCTSkipIf(dir == nil, "screenshots only in CI")
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory", "-UITestBypassAuth"]
        app.launch()
        let next = app.buttons["onboardingNext"]
        func tapNext() { XCTAssertTrue(next.waitForExistence(timeout: 10)); next.tap() }

        XCTAssertTrue(next.waitForExistence(timeout: 15))
        shot(app, "welcome"); tapNext()
        let accept = app.switches["acceptDisclaimer"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        accept.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        shot(app, "health"); tapNext()
        shot(app, "privacy"); tapNext()
        shot(app, "lock"); tapNext()
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Riki")
        app.keyboards.buttons["Return"].firstMatch.tap()
        shot(app, "profile"); tapNext()
        shot(app, "goal"); tapNext()
        shot(app, "experience"); tapNext()
        shot(app, "equipment"); tapNext()
        shot(app, "schedule"); tapNext()
        shot(app, "program"); tapNext()
        shot(app, "checkin"); tapNext()
        shot(app, "nutrition"); tapNext()
        shot(app, "review"); tapNext()

        XCTAssertTrue(app.buttons["nextSession"].waitForExistence(timeout: 10))
        shot(app, "today")
        app.buttons["startWorkoutButton"].tap()
        XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 5))
        shot(app, "versions")
        app.buttons["startWorkout"].tap()
        XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 10))
        shot(app, "workout")
        let firstSet = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'setDone-'")).firstMatch
        if firstSet.exists { firstSet.tap(); sleep(1); shot(app, "workout-rest-timer") }
        let swap = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Swap '")).firstMatch
        if swap.exists { swap.tap(); sleep(1); shot(app, "swap"); app.buttons["Cancel"].firstMatch.tap() }
        app.buttons["Later"].tap()

        app.tabBars.buttons["Train"].tap(); sleep(1); shot(app, "train")
        app.cells.element(boundBy: 3).tap(); sleep(1); shot(app, "session-preview")
        app.buttons.element(boundBy: 2).tap(); sleep(1); shot(app, "exercise-sheet")
        app.tabBars.buttons["Settings"].firstMatch.tap(); sleep(1); shot(app, "settings")
    }
}
