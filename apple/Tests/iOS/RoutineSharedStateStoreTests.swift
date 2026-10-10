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
