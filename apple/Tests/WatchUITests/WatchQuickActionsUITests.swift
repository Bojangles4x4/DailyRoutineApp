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

        let suggested = app.descendants(matching: .any)["suggestedRoutineAction"]
        XCTAssertTrue(suggested.waitForExistence(timeout: 10))
        XCTAssertTrue(suggested.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Build45-Watch-Ultra-focus"
        attachment.lifetime = .keepAlways
        add(attachment)
        suggested.tap()
    }

    func testRoutineRowsUseFingerFriendlyTargetsAndCompactActionBar() {
        let app = launchApp(truthComplete: true)

        let toggle = app.descendants(matching: .any)["toggleWatchTaskView"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()

        let firstRoutine = app.buttons["routine-morning-prayer"]
        let fourthRoutine = app.buttons["routine-day-movement"]
        let fifthRoutine = app.buttons["routine-evening-prepare"]
        let customAction = app.descendants(matching: .any)["customWatchAction"]
        XCTAssertTrue(firstRoutine.waitForExistence(timeout: 10))
        XCTAssertTrue(fourthRoutine.waitForExistence(timeout: 10))
        XCTAssertTrue(customAction.waitForExistence(timeout: 10))
        XCTAssertTrue(firstRoutine.isHittable)
        XCTAssertGreaterThanOrEqual(firstRoutine.frame.height, 38)
        XCTAssertGreaterThanOrEqual(customAction.frame.height, 38)
        XCTAssertLessThanOrEqual(app.frame.maxY - customAction.frame.maxY, 6)
        XCTAssertTrue(fifthRoutine.waitForExistence(timeout: 10))
    }

    func testCustomBottomAction() {
        let app = launchApp(truthComplete: true)

        let customAction = app.descendants(matching: .any)["customWatchAction"]
        XCTAssertTrue(customAction.waitForExistence(timeout: 10))
        XCTAssertTrue(customAction.isEnabled)
        customAction.tap()
    }

    func testWatchFocusOmitsCaptureAndEarnedAccess() {
        let app = launchApp(truthComplete: true)

        XCTAssertTrue(app.descendants(matching: .any)["suggestedRoutineAction"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["captureWatchNote"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "earned")).firstMatch.exists)
    }

    func testMedicationReviewDoesNotCompleteTheRoutine() {
        let app = XCUIApplication()
        app.launchArguments += ["UI_TESTING_TRUTH_COMPLETE", "UI_TESTING_MEDICATION_FOCUS"]
        app.launch()
        let review = app.buttons["reviewWatchMedications"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["watchFocusSummary"].exists)
        let focusAttachment = XCTAttachment(screenshot: app.screenshot())
        focusAttachment.name = "Build45-Watch-medication-focus"
        focusAttachment.lifetime = .keepAlways
        add(focusAttachment)
        review.tap()
        XCTAssertTrue(app.staticTexts["Vitamin D · 1 capsule"].waitForExistence(timeout: 5))
        let listAttachment = XCTAttachment(screenshot: app.screenshot())
        listAttachment.name = "Build45-Watch-medication-list"
        listAttachment.lifetime = .keepAlways
        add(listAttachment)
        let done = app.buttons["dismissMedicationReview"]
        if !done.isHittable { app.swipeUp() }
        done.tap()
        XCTAssertTrue(app.buttons["suggestedRoutineAction"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sent to iPhone"].exists)
    }
}
