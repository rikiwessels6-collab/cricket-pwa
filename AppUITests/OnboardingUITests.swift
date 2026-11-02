import XCTest

/// Runs against a throwaway in-memory store (-UITestInMemory). Face ID can't
/// be performed in UI tests, so -UITestBypassAuth makes "Unlock" succeed.
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory", "-UITestBypassAuth"] + extra
        app.launch()
        return app
    }

    private func next(_ app: XCUIApplication) {
        let button = app.buttons["onboardingNext"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
    }

    func testCompletingOnboardingShowsToday() {
        let app = launch()
        next(app)                                               // Welcome
        let accept = app.switches["acceptDisclaimer"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        accept.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        next(app)                                               // Health
        next(app)                                               // Privacy
        next(app)                                               // Lock
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Sam")
        next(app)                                               // Profile
        next(app)                                               // Goals
        next(app)                                               // Experience
        next(app)                                               // Equipment
        next(app)                                               // Schedule
        next(app)                                               // Program (Option B preselected)
        next(app)                                               // Check-in
        next(app)                                               // Nutrition
        next(app)                                               // Review -> Start my plan
        let nextSession = app.buttons["nextSession"]
        XCTAssertTrue(nextSession.waitForExistence(timeout: 10))
        XCTAssertTrue(nextSession.label.contains("Full Body A"), nextSession.label)
    }

    func testLockScreenUnlocks() {
        let app = launch(["-UITestForceLock"])
        let unlock = app.buttons["unlockButton"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        unlock.tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboardingNext"].waitForExistence(timeout: 5))
    }
}
