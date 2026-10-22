import XCTest
@testable import DailyRoutine

final class RoutineSharedStateStoreTests: XCTestCase {
    private var directoryURL: URL!
    private var store: RoutineSharedStateStore!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutineSharedStateStoreTests-(UUID().uuidString)", isDirectory: true)
        store = RoutineSharedStateStore(directoryURL: directoryURL)
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        store = nil
        directoryURL = nil
    }

    func testSnapshotRoundTripsWithoutPrivateCategories() throws {
        let snapshot = makeSnapshot()

        try store.save(snapshot: snapshot)

        XCTAssertEqual(try store.loadSnapshot(), snapshot)
        let encoded = try XCTUnwrap(try? Data(contentsOf: directoryURL.appendingPathComponent("routine-shared-snapshot-v1.json")))
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("medication"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("health"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("prayer"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("note"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("facebook"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("selected apps"))
        XCTAssertEqual(snapshot.earnedAccessRemainingMinutes, 25)
        XCTAssertEqual(snapshot.earnedAccessDailyLimitMinutes, 60)
    }

    func testLegacySnapshotWithoutWidgetBalanceStillDecodes() throws {
        let legacy: [String: Any] = [
            "schemaVersion": 1,
            "revision": 4,
            "localDateKey": "2026-09-14",
            "timeZoneIdentifier": "America/Chicago",
            "foundationComplete": true,
            "completed": 2,
            "total": 5,
            "eligibleItems": [],
            "updatedAt": "2026-09-14T12:00:00Z"
        ]

        let data = try JSONSerialization.data(withJSONObject: legacy)
        let snapshot = try JSONDecoder().decode(RoutineSharedSnapshot.self, from: data)

        XCTAssertTrue(snapshot.isValid)
        XCTAssertNil(snapshot.convictionsEnabled)
        XCTAssertNil(snapshot.earnedAccessRemainingMinutes)
        XCTAssertNil(snapshot.earnedAccessDailyLimitMinutes)
    }

    func testIncompleteOrExcessiveWidgetBalanceIsRejected() throws {
        let invalid = RoutineSharedSnapshot(
            schemaVersion: 1,
            revision: 7,
            localDateKey: "2026-09-14",
            timeZoneIdentifier: "America/Chicago",
            foundationComplete: true,
            convictionsEnabled: true,
            completed: 2,
            total: 10,
            earnedAccessRemainingMinutes: 61,
            earnedAccessDailyLimitMinutes: 60,
            nextItem: nil,
            eligibleItems: [],
            updatedAt: "2026-09-14T12:00:00Z"
        )

        XCTAssertFalse(invalid.isValid)
        XCTAssertThrowsError(try store.save(snapshot: invalid))
    }

    func testDuplicateCommandIDIsEnqueuedOnceAndResolvedOnce() throws {
        let command = makeCommand(id: "duplicate-command")

        let first = try store.enqueue(command)
        let duplicate = try store.enqueue(command)

        XCTAssertEqual(first, duplicate)
        XCTAssertEqual(try store.pendingCommands(), [command])

        let resolved = try store.resolve(
            commandID: command.id,
            status: .applied,
            stateRevision: 8,
            message: "Brush teeth completed."
        )
        let repeatedResolution = try store.resolve(
            commandID: command.id,
            status: .rejected,
            stateRevision: 9,
            message: "This must not replace the first result."
        )

        XCTAssertEqual(resolved?.status, .applied)
        XCTAssertEqual(repeatedResolution, resolved)
        XCTAssertTrue(try store.pendingCommands().isEmpty)
    }

    func testJournalPersistsAcrossStoreInstances() throws {
        let command = makeCommand(id: "persisted-command")
        _ = try store.enqueue(command)

        let reopenedStore = RoutineSharedStateStore(directoryURL: directoryURL)

        XCTAssertEqual(try reopenedStore.pendingCommands(), [command])
    }

    func testMutationRequiresExpectedRevisionAndFoundationValidation() throws {
        let missingRevision = RoutineSharedCommand(
            schemaVersion: 1,
            id: "missing-revision",
            actionID: RoutineSharedActionID.setCheckboxCompletion,
            origin: "widget",
            createdAt: "2026-09-14T12:00:00Z",
            localDateKey: "2026-09-14",
            timeZoneIdentifier: "America/Chicago",
            targetID: "morning-teeth",
            expectedRevision: nil,
            requiresFoundationComplete: true,
            payload: ["completed": "true"]
        )
        let missingGate = RoutineSharedCommand(
            schemaVersion: 1,
            id: "missing-gate",
            actionID: RoutineSharedActionID.setCheckboxCompletion,
            origin: "widget",
            createdAt: "2026-09-14T12:00:00Z",
            localDateKey: "2026-09-14",
            timeZoneIdentifier: "America/Chicago",
            targetID: "morning-teeth",
            expectedRevision: 7,
            requiresFoundationComplete: false,
            payload: ["completed": "true"]
        )

        XCTAssertThrowsError(try store.enqueue(missingRevision))
        XCTAssertThrowsError(try store.enqueue(missingGate))
        XCTAssertTrue(try store.pendingCommands().isEmpty)
    }

    func testInvalidSnapshotIsRejected() throws {
        let invalid = RoutineSharedSnapshot(
            schemaVersion: 1,
            revision: 7,
            localDateKey: "09/14/2026",
            timeZoneIdentifier: "America/Chicago",
            foundationComplete: true,
            convictionsEnabled: true,
            completed: 2,
            total: 10,
            earnedAccessRemainingMinutes: 25,
            earnedAccessDailyLimitMinutes: 60,
            nextItem: nil,
            eligibleItems: [],
            updatedAt: "2026-09-14T12:00:00Z"
        )

        XCTAssertThrowsError(try store.save(snapshot: invalid))
        XCTAssertNil(try store.loadSnapshot())
    }

    func testEarnedAccessUsageCheckpointsStayCompactAndIncludeFinalMinute() {
        XCTAssertEqual(EarnedAccessShared.usageCheckpoints(totalMinutes: 1), [1])
        XCTAssertEqual(EarnedAccessShared.usageCheckpoints(totalMinutes: 15), [5, 10, 15])
        XCTAssertEqual(EarnedAccessShared.usageCheckpoints(totalMinutes: 17), [5, 10, 15, 17])
        XCTAssertEqual(EarnedAccessShared.usageCheckpoints(totalMinutes: 60), Array(stride(from: 5, through: 60, by: 5)))
        XCTAssertEqual(EarnedAccessShared.usageCheckpoints(totalMinutes: 500).last, 120)
    }

    func testRepeatedMorningCompletionDoesNotResetSameDayTruthQueue() {
        XCTAssertTrue(TruthReminderStore.shouldInitializeReviewQueue(startedDay: nil, today: "2026-10-13"))
        XCTAssertTrue(TruthReminderStore.shouldInitializeReviewQueue(startedDay: "2026-10-12", today: "2026-10-13"))
        XCTAssertFalse(TruthReminderStore.shouldInitializeReviewQueue(startedDay: "2026-10-13", today: "2026-10-13"))
    }

    func testLegacyTruthQueueMigratesReviewDayIntoInitializationMarker() throws {
        let legacy = Data(#"{"reviewDay":"2026-10-13","reviewTrackingStartMinute":480,"reviewedMinutes":[480,510]}"#.utf8)

        let settings = try JSONDecoder().decode(TruthReminderSettings.self, from: legacy)

        XCTAssertEqual(settings.reviewGateStartedDay, "2026-10-13")
        XCTAssertEqual(settings.reviewTrackingStartMinute, 480)
        XCTAssertEqual(settings.reviewedMinutes, [480, 510])
        XCTAssertEqual(settings.reflectionSeconds, 10)
        XCTAssertFalse(TruthReminderStore.shouldInitializeReviewQueue(
            startedDay: settings.reviewGateStartedDay,
            today: "2026-10-13"
        ))
    }

    func testSleepSelectionPrefersTheLatestSessionEndingTodayOverALongerOlderNight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 22)))
        let olderStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 21)))
        let olderEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 8)))
        let currentStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 23)))
        let currentEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 6)))
        let sessions = [
            [DateInterval(start: olderStart, end: olderEnd)],
            [DateInterval(start: currentStart, end: currentEnd)]
        ]

        let selected = HealthKitService.preferredSleepSession(sessions, now: now, calendar: calendar)

        XCTAssertEqual(selected?.first?.start, currentStart)
        XCTAssertEqual(selected?.last?.end, currentEnd)
    }

    func testSleepSelectionKeepsOvernightSleepInsteadOfALaterNap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 18)))
        let overnightStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 22)))
        let overnightEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 6)))
        let napStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 14)))
        let napEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 15)))

        let selected = HealthKitService.preferredSleepSession(
            [[DateInterval(start: overnightStart, end: overnightEnd)], [DateInterval(start: napStart, end: napEnd)]],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(selected?.first?.start, overnightStart)
        XCTAssertEqual(selected?.last?.end, overnightEnd)
    }

    func testTruthReminderCountdownPausesOutsideTheForeground() {
        XCTAssertEqual(TruthReminderCountdown.next(10, sceneIsActive: false), 10)
        XCTAssertEqual(TruthReminderCountdown.next(10, sceneIsActive: true), 9)
        XCTAssertEqual(TruthReminderCountdown.next(0, sceneIsActive: true), 0)
    }

    func testChangingProtectedAppsEndsAnActiveAllowance() {
        XCTAssertTrue(EarnedAccessControlStore.shouldEndActiveAllowance(selectionChanged: true, allowanceActive: true))
        XCTAssertFalse(EarnedAccessControlStore.shouldEndActiveAllowance(selectionChanged: false, allowanceActive: true))
        XCTAssertFalse(EarnedAccessControlStore.shouldEndActiveAllowance(selectionChanged: true, allowanceActive: false))
    }

    func testEarnedAccessNotificationCopySeparatesAvailableBalanceFromWalkingContribution() {
        XCTAssertEqual(
            EarnedAccessShared.availableNotificationTitle(minutes: 22),
            "22 earned-app minutes available now"
        )
        XCTAssertEqual(
            EarnedAccessShared.remainingNotificationTitle(minutes: 1),
            "About 1 earned-app minute remains"
        )
        XCTAssertEqual(
            HealthKitService.walkingProgressNotificationTitle(minutes: 10, maximum: 60),
            "Walking contribution: 10 of 60 min"
        )
        XCTAssertTrue(HealthKitService.walkingProgressNotificationBody().contains("not your current usable balance"))
    }

    func testEarnedAccessNotificationCleanupMatchesOnlyOwnedIdentifiers() {
        XCTAssertTrue(EarnedAccessShared.isBalanceNotification(identifier: EarnedAccessShared.balanceNotificationIdentifier))
        XCTAssertTrue(EarnedAccessShared.isBalanceNotification(identifier: "dailyRoutine.earnedAccess.opened.legacy"))
        XCTAssertTrue(EarnedAccessShared.isBalanceNotification(identifier: "dailyRoutine.earnedAccess.usage.legacy.5"))
        XCTAssertTrue(EarnedAccessShared.isWalkingNotification(identifier: "dailyRoutine.walking.2026-10-22.5"))
        XCTAssertFalse(EarnedAccessShared.isBalanceNotification(identifier: "dailyRoutine.truthReminder.630"))
        XCTAssertFalse(EarnedAccessShared.isWalkingNotification(identifier: "dailyRoutine.sleepReview.2026-10-22"))
    }

    func testStalePublisherCannotDeleteTheNewerNotificationRequest() {
        let stale = "publisher-a"
        let current = "publisher-b"
        let staleIdentifier = EarnedAccessShared.balanceNotificationIdentifier(generation: stale)
        let currentIdentifier = EarnedAccessShared.balanceNotificationIdentifier(generation: current)

        XCTAssertNotEqual(staleIdentifier, currentIdentifier)
        XCTAssertTrue(EarnedAccessShared.shouldRemoveOwnedNotification(
            identifier: staleIdentifier,
            generation: stale,
            currentBalanceGeneration: current,
            currentWalkingGeneration: "walking-current",
            includeWalking: false
        ))
        XCTAssertFalse(EarnedAccessShared.shouldRemoveOwnedNotification(
            identifier: currentIdentifier,
            generation: current,
            currentBalanceGeneration: current,
            currentWalkingGeneration: "walking-current",
            includeWalking: false
        ))
        XCTAssertFalse(EarnedAccessShared.shouldRemoveOwnedNotification(
            identifier: "dailyRoutine.truthReminder.630",
            generation: nil,
            currentBalanceGeneration: current,
            currentWalkingGeneration: "walking-current",
            includeWalking: true
        ))
    }

    func testMorningGateOffStillShowsEarnedAccessAsControllingState() {
        let locked = EarnedAccessProtectionSummary.title(
            isAuthorized: true,
            essentialSelectionNeedsRepair: false,
            morningGateEnabled: false,
            morningFoundationCompleteToday: false,
            truthReminderGateActive: false,
            truthReminderSafetyUnlockActive: false,
            protectionEnabled: true,
            allowanceActive: false,
            allowanceRemainingMinutes: nil,
            isShielding: true
        )
        let open = EarnedAccessProtectionSummary.title(
            isAuthorized: true,
            essentialSelectionNeedsRepair: false,
            morningGateEnabled: false,
            morningFoundationCompleteToday: false,
            truthReminderGateActive: false,
            truthReminderSafetyUnlockActive: false,
            protectionEnabled: true,
            allowanceActive: true,
            allowanceRemainingMinutes: 12,
            isShielding: false
        )

        XCTAssertEqual(locked, "Earned apps are locked")
        XCTAssertEqual(open, "Currently open: about 12 min")
    }

    func testActiveAllowanceRequiresCurrentCompleteMonitorState() {
        let today = "2026-10-13"
        XCTAssertFalse(EarnedAccessControlStore.allowanceMonitorNeedsRepair(
            active: true,
            allowanceDate: today,
            today: today,
            redemptionID: "allowance-1",
            remainingMinutes: 15,
            monitorScheduled: true
        ))
        XCTAssertTrue(EarnedAccessControlStore.allowanceMonitorNeedsRepair(
            active: true,
            allowanceDate: today,
            today: today,
            redemptionID: "allowance-1",
            remainingMinutes: 15,
            monitorScheduled: false
        ))
        XCTAssertTrue(EarnedAccessControlStore.allowanceMonitorNeedsRepair(
            active: true,
            allowanceDate: "2026-10-12",
            today: today,
            redemptionID: "allowance-1",
            remainingMinutes: 15,
            monitorScheduled: true
        ))
        XCTAssertTrue(EarnedAccessControlStore.allowanceMonitorNeedsRepair(
            active: true,
            allowanceDate: today,
            today: today,
            redemptionID: "",
            remainingMinutes: nil,
            monitorScheduled: true
        ))
        XCTAssertFalse(EarnedAccessControlStore.allowanceMonitorNeedsRepair(
            active: false,
            allowanceDate: nil,
            today: today,
            redemptionID: "",
            remainingMinutes: nil,
            monitorScheduled: false
        ))
    }

    func testAllAppGateFailsOpenWithoutEssentialExceptions() {
        XCTAssertFalse(EarnedAccessShared.canApplyFoundationShield(applicationCount: 0, websiteCount: 0))
        XCTAssertTrue(EarnedAccessShared.canApplyFoundationShield(applicationCount: 1, websiteCount: 0))
        XCTAssertTrue(EarnedAccessShared.canApplyFoundationShield(applicationCount: 0, websiteCount: 1))
        XCTAssertFalse(TruthReminderStore.shouldBlockWaitingPresentation(
            canEnforceGate: false,
            gateIsActive: true,
            safetyUnlockActive: false
        ))
        XCTAssertFalse(TruthReminderStore.shouldBlockWaitingPresentation(
            canEnforceGate: true,
            gateIsActive: true,
            safetyUnlockActive: true
        ))
        XCTAssertTrue(TruthReminderStore.shouldBlockWaitingPresentation(
            canEnforceGate: true,
            gateIsActive: true,
            safetyUnlockActive: false
        ))
    }

    func testTruthReminderPresentationWaitsForMorningFoundation() {
        let entryID = UUID()

        let decision = TruthReminderStore.presentationDecision(
            queuedEntryID: entryID,
            activeGateEntryID: entryID,
            availableEntryIDs: [entryID],
            morningFoundationIsIncomplete: true
        )

        XCTAssertNil(decision)
    }

    func testActiveTruthGateWinsOverNotificationAndBlocks() {
        let queuedID = UUID()
        let activeID = UUID()

        let decision = TruthReminderStore.presentationDecision(
            queuedEntryID: queuedID,
            activeGateEntryID: activeID,
            availableEntryIDs: [queuedID, activeID],
            morningFoundationIsIncomplete: false
        )

        XCTAssertEqual(decision, TruthReminderPresentationDecision(entryID: activeID, blocking: true))
    }

    func testNotificationOnlyTruthReminderIsNonblocking() {
        let entryID = UUID()

        let decision = TruthReminderStore.presentationDecision(
            queuedEntryID: entryID,
            activeGateEntryID: nil,
            availableEntryIDs: [entryID],
            morningFoundationIsIncomplete: false
        )

        XCTAssertEqual(decision, TruthReminderPresentationDecision(entryID: entryID, blocking: false))
    }

    func testMissingTruthReminderDoesNotPresent() {
        let missingID = UUID()

        let decision = TruthReminderStore.presentationDecision(
            queuedEntryID: missingID,
            activeGateEntryID: nil,
            availableEntryIDs: [],
            morningFoundationIsIncomplete: false
        )

        XCTAssertNil(decision)
    }

    func testTruthReminderQueueKeepsEveryDueOccurrenceDistinct() {
        let waiting = TruthReminderStore.dueUnreviewedMinutes(
            scheduleMinutes: [480, 510, 540, 570],
            trackingStartMinute: 480,
            reviewedMinutes: [],
            nowMinute: 545
        )

        XCTAssertEqual(waiting, [480, 510, 540])
    }

    func testTruthReminderQueueAdvancesWithoutSkippingLaterDueOccurrences() {
        let waiting = TruthReminderStore.dueUnreviewedMinutes(
            scheduleMinutes: [480, 510, 540, 570],
            trackingStartMinute: 480,
            reviewedMinutes: [480, 540],
            nowMinute: 575
        )

        XCTAssertEqual(waiting, [510, 570])
    }

    func testTruthReminderQueueDoesNotCarryEarlierScheduleBeforeTrackingStarted() {
        let waiting = TruthReminderStore.dueUnreviewedMinutes(
            scheduleMinutes: [480, 510, 540, 570],
            trackingStartMinute: 540,
            reviewedMinutes: [],
            nowMinute: 550
        )

        XCTAssertEqual(waiting, [540])
    }

    func testNativeSafetySnapshotRoundTripsExactBytesAndRetainsTwoCopies() throws {
        let safetyDirectory = directoryURL.appendingPathComponent("Safety", isDirectory: true)
        let safetyStore = NativeSafetySnapshotStore(directoryURL: safetyDirectory)
        let first = makeSafetySnapshotData(id: "snapshot-first", createdAt: "2026-10-08T12:00:00.000Z")
        let second = makeSafetySnapshotData(id: "snapshot-second", createdAt: "2026-10-08T12:01:00.000Z")
        let third = makeSafetySnapshotData(id: "snapshot-third", createdAt: "2026-10-08T12:02:00.000Z")

        XCTAssertEqual(try safetyStore.save(snapshotData: first, expectedSnapshotID: "snapshot-first"), first.count)
        XCTAssertEqual(try safetyStore.load(snapshotID: "snapshot-first"), first)
        _ = try safetyStore.save(snapshotData: second, expectedSnapshotID: "snapshot-second")
        _ = try safetyStore.save(snapshotData: third, expectedSnapshotID: "snapshot-third")

        XCTAssertEqual(try safetyStore.metadata().map(\.snapshotId), ["snapshot-third", "snapshot-second"])
        XCTAssertNil(try safetyStore.load(snapshotID: "snapshot-first"))
        XCTAssertEqual(try safetyStore.load(snapshotID: "snapshot-third"), third)
    }

    func testNativeSafetySnapshotRejectsMismatchedEnvelopeWithoutReplacingVerifiedCopy() throws {
        let safetyDirectory = directoryURL.appendingPathComponent("SafetyMismatch", isDirectory: true)
        let safetyStore = NativeSafetySnapshotStore(directoryURL: safetyDirectory)
        let verified = makeSafetySnapshotData(id: "snapshot-verified", createdAt: "2026-10-08T12:00:00.000Z")
        let mismatched = makeSafetySnapshotData(id: "snapshot-content", createdAt: "2026-10-08T12:01:00.000Z")

        _ = try safetyStore.save(snapshotData: verified, expectedSnapshotID: "snapshot-verified")
        XCTAssertThrowsError(try safetyStore.save(snapshotData: mismatched, expectedSnapshotID: "snapshot-envelope"))

        XCTAssertEqual(try safetyStore.metadata().map(\.snapshotId), ["snapshot-verified"])
        XCTAssertEqual(try safetyStore.load(snapshotID: "snapshot-verified"), verified)
    }

    func testNativeSafetySnapshotRejectsInvalidOrUnsafeContent() throws {
        let safetyStore = NativeSafetySnapshotStore(directoryURL: directoryURL.appendingPathComponent("SafetyInvalid", isDirectory: true))
        XCTAssertThrowsError(try safetyStore.save(snapshotData: Data("{}".utf8), expectedSnapshotID: "snapshot-invalid"))
        XCTAssertThrowsError(try safetyStore.save(
            snapshotData: makeSafetySnapshotData(id: "snapshot-valid", createdAt: "2026-10-08T12:00:00.000Z"),
            expectedSnapshotID: "../unsafe"
        ))
        XCTAssertTrue(try safetyStore.metadata().isEmpty)
    }

    func testEveryLocalWebReferenceIsBundledInTheApp() throws {
        let bundle = Bundle.main
        let indexURL = try XCTUnwrap(bundle.url(forResource: "index", withExtension: "html"))
        let html = try String(contentsOf: indexURL, encoding: .utf8)
        let expression = try NSRegularExpression(pattern: #"(?:src|href)="([^"]+)""#)
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let references = expression.matches(in: html, range: range).compactMap { match -> String? in
            guard let capture = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[capture])
        }.filter { reference in
            !reference.hasPrefix("http") && !reference.hasPrefix("data:") && !reference.hasPrefix("#")
        }.map { reference in
            reference.components(separatedBy: "?")[0].components(separatedBy: "#")[0]
        }

        XCTAssertTrue(references.contains("data-health.js"), "index.html must load the sync safety component")
        for reference in references {
            let resourceURL = try XCTUnwrap(bundle.resourceURL?.appendingPathComponent(reference))
            XCTAssertTrue(FileManager.default.fileExists(atPath: resourceURL.path), "Missing bundled web resource: \(reference)")
        }
    }

    private func makeSnapshot() -> RoutineSharedSnapshot {
        let item = RoutineSharedItemSnapshot(
            id: "morning-teeth",
            title: "Brush teeth",
            section: "morning",
            completed: false,
            actionID: RoutineSharedActionID.setCheckboxCompletion
        )
        return RoutineSharedSnapshot(
            schemaVersion: 1,
            revision: 7,
            localDateKey: "2026-09-14",
            timeZoneIdentifier: "America/Chicago",
            foundationComplete: true,
            convictionsEnabled: true,
            completed: 2,
            total: 10,
            earnedAccessRemainingMinutes: 25,
            earnedAccessDailyLimitMinutes: 60,
            nextItem: item,
            eligibleItems: [item],
            updatedAt: "2026-09-14T12:00:00.000Z"
        )
    }

    private func makeSafetySnapshotData(id: String, createdAt: String) -> Data {
        let snapshot: [String: Any] = [
            "schemaVersion": 1,
            "id": id,
            "createdAt": createdAt,
            "label": "Before private sync",
            "version": "1.33.0",
            "build": 34,
            "state": [
                "settings": ["backgroundImage": ""],
                "items": [["id": "morning-teeth", "name": "Brush teeth"]],
                "days": ["2026-10-08": ["entries": ["morning-teeth": true]]],
                "memories": [],
                "notes": [],
                "weeklyReviews": [:]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
    }

    private func makeCommand(id: String) -> RoutineSharedCommand {
        RoutineSharedCommand(
            schemaVersion: 1,
            id: id,
            actionID: RoutineSharedActionID.setCheckboxCompletion,
            origin: "widget",
            createdAt: "2026-09-14T12:00:00Z",
            localDateKey: "2026-09-14",
            timeZoneIdentifier: "America/Chicago",
            targetID: "morning-teeth",
            expectedRevision: 7,
            requiresFoundationComplete: true,
            payload: ["completed": "true"]
        )
    }
}
