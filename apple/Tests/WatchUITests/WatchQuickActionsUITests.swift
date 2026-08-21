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
        XCTAssertFalse(app.buttons["Complete next"].exists)
        XCTAssertFalse(app.buttons["Water +1"].exists)
        XCTAssertFalse(app.buttons["Save mood 5"].exists)
    }

    func testCompleteNextQuickAction() {
        let app = launchApp(truthComplete: true)

        let completeNext = app.buttons["Complete next"]
        XCTAssertTrue(completeNext.waitForExistence(timeout: 10))
        XCTAssertTrue(completeNext.isEnabled)
        completeNext.tap()
    }

    func testWaterQuickAction() {
        let app = launchApp(truthComplete: true)

        let addWater = app.buttons["Water +1"]
        XCTAssertTrue(addWater.waitForExistence(timeout: 10))
        XCTAssertTrue(addWater.isEnabled)
        addWater.tap()
    }

    func testMoodQuickAction() {
        let app = launchApp(truthComplete: true)

        let saveMood = app.buttons["Save mood 5"]
        if !saveMood.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(saveMood.waitForExistence(timeout: 10))
        XCTAssertTrue(saveMood.isEnabled)
        saveMood.tap()
    }
}
