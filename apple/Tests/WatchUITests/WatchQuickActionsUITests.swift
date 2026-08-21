import XCTest

final class WatchQuickActionsUITests: XCTestCase {
    func testCompleteNextQuickAction() {
        let app = XCUIApplication()
        app.launch()

        let completeNext = app.buttons["Complete next"]
        XCTAssertTrue(completeNext.waitForExistence(timeout: 10))
        XCTAssertTrue(completeNext.isEnabled)
        completeNext.tap()
    }

    func testWaterQuickAction() {
        let app = XCUIApplication()
        app.launch()

        let addWater = app.buttons["Water +1"]
        XCTAssertTrue(addWater.waitForExistence(timeout: 10))
        XCTAssertTrue(addWater.isEnabled)
        addWater.tap()
    }
}
