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
            completed: 2,
            total: 10,
            nextItem: nil,
            eligibleItems: [],
            updatedAt: "2026-09-14T12:00:00Z"
        )

        XCTAssertThrowsError(try store.save(snapshot: invalid))
        XCTAssertNil(try store.loadSnapshot())
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
            completed: 2,
            total: 10,
            nextItem: item,
            eligibleItems: [item],
            updatedAt: "2026-09-14T12:00:00.000Z"
        )
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
