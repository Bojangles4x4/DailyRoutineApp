import XCTest

final class WatchQuickActionsUITests: XCTestCase {
    private func launchApp(truthComplete: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(truthComplete ? "UI_TESTING_TRUTH_COMPLETE" : "UI_TESTING_TRUTH_REQUIRED")
        app.launch()
        return app
    }

    func testTruthBeforeTasksLocksQuickActions() {
        let app = launchApp(truthComplete: false)

        let lock = app.descendants(matching: .any)["truthBeforeTasksLock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["customWatchAction"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["captureWatchNote"].exists)
        XCTAssertFalse(app.buttons["routine-morning-teeth"].exists)
    }

    func testExactRoutineItemCanBeCompleted() {
        let app = launchApp(truthComplete: true)

        let routine = app.buttons["routine-morning-teeth"]
        XCTAssertTrue(routine.waitForExistence(timeout: 10))
        XCTAssertTrue(routine.isEnabled)
        routine.tap()
    }

    func testCustomBottomAction() {
        let app = launchApp(truthComplete: true)

        let customAction = app.descendants(matching: .any)["customWatchAction"]
        XCTAssertTrue(customAction.waitForExistence(timeout: 10))
        XCTAssertTrue(customAction.isEnabled)
        customAction.tap()
    }

    func testCaptureOpensNoteComposer() {
        let app = launchApp(truthComplete: true)

        let capture = app.descendants(matching: .any)["captureWatchNote"]
        XCTAssertTrue(capture.waitForExistence(timeout: 10))
        capture.tap()
        XCTAssertTrue(app.textFields["watchCaptureText"].waitForExistence(timeout: 10))
    }
}
