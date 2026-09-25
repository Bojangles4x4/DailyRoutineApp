import XCTest
@testable import Daily_Routine_Agent

final class PersonalSystemsAgentTests: XCTestCase {
    private var directoryURL: URL!
    private var store: SQLiteEventStore!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyRoutineAgentTests-\(UUID().uuidString)", isDirectory: true)
        store = try SQLiteEventStore(databaseURL: directoryURL.appendingPathComponent("events.sqlite"))
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: directoryURL)
        directoryURL = nil
    }

    func testEventRoundTripPreservesPrivacyFields() throws {
        let event = AgentEvent(
            id: "message-1",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .messages,
            category: .communication,
            title: "Message received",
            summary: "Please follow up tomorrow.",
            metadata: ["direction": "incoming"],
            sensitivity: .restricted,
            externalID: "1"
        )

        XCTAssertEqual(try store.insert(events: [event]), 1)
        XCTAssertEqual(try store.insert(events: [event]), 0)
        let restored = try XCTUnwrap(store.fetchEvents(since: .distantPast).first)
        XCTAssertEqual(restored, event)
        XCTAssertEqual(restored.sensitivity, .restricted)
    }

    func testStoreUsesOwnerOnlyFilePermissions() throws {
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
        let databaseAttributes = try FileManager.default.attributesOfItem(atPath: store.databaseURL.path)

        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((databaseAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        for suffix in ["-wal", "-shm"] {
            let path = store.databaseURL.path + suffix
            if FileManager.default.fileExists(atPath: path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            }
        }
    }

    func testDailyRoutineCollectorAcceptsPrivacyLimitedLiveSnapshot() async throws {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let dayKey = dayFormatter.string(from: Date())
        let snapshot: [String: Any] = [
            "version": "1.21.0",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "scope": "routine-definitions-and-daily-history",
            "state": [
                "items": [[
                    "id": "morning-water",
                    "name": "Drink water",
                    "kind": "routine",
                    "section": "morning",
                    "type": "checkbox",
                    "frequency": "daily"
                ]],
                "days": [dayKey: [
                    "entries": ["morning-water": true],
                    "skippedItems": [:]
                ]]
            ]
        ]
        let fileURL = directoryURL.appendingPathComponent("daily-routine-agent-live.json")
        try JSONSerialization.data(withJSONObject: snapshot).write(to: fileURL)

        let events = try await DailyRoutineBackupCollector(fileURL: fileURL)
            .collect(since: Date().addingTimeInterval(-86_400))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Drink water")
        XCTAssertEqual(events.first?.summary, "Completed")
        XCTAssertEqual(events.first?.source, .dailyRoutine)
    }

    func testPrivateSyncSnapshotStoreWritesProtectedCollectorInput() async throws {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let dayKey = dayFormatter.string(from: Date())
        let snapshot: [String: Any] = [
            "schemaVersion": 1,
            "scope": "routine-definitions-and-completion-signals",
            "state": [
                "items": [[
                    "id": "morning-water",
                    "name": "Drink water",
                    "kind": "routine",
                    "section": "morning",
                    "type": "checkbox",
                    "frequency": "daily"
                ]],
                "days": [dayKey: [
                    "entries": ["morning-water": true],
                    "skippedItems": [:]
                ]]
            ]
        ]
        let fileURL = directoryURL.appendingPathComponent("private-sync-agent-snapshot.json")
        let fileStore = PrivateSyncSnapshotFileStore(fileURL: fileURL)

        try fileStore.write(JSONSerialization.data(withJSONObject: snapshot))

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let events = try await DailyRoutineBackupCollector(fileURL: fileURL)
            .collect(since: Date().addingTimeInterval(-86_400))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.summary, "Completed")
    }

    func testPrivateSyncSnapshotStoreRejectsBroaderRoutineBackup() throws {
        let fileURL = directoryURL.appendingPathComponent("private-sync-agent-snapshot.json")
        let fileStore = PrivateSyncSnapshotFileStore(fileURL: fileURL)
        let broaderBackup: [String: Any] = [
            "scope": "routine-definitions-and-daily-history",
            "state": ["items": [], "days": [:]],
            "notes": [["text": "private"]]
        ]

        XCTAssertThrowsError(try fileStore.write(JSONSerialization.data(withJSONObject: broaderBackup)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testMessagesCollectorReadsOnlyTheHelperSnapshot() async throws {
        let fileURL = directoryURL.appendingPathComponent("messages-import-v1.json")
        let occurredAt = Date().addingTimeInterval(-120)
        let envelope = MessagesImportEnvelope(
            version: MessagesImportEnvelope.currentVersion,
            source: MessagesImportEnvelope.source,
            exportedAt: Date(),
            windowDays: 14,
            events: [MessagesImportRecord(
                externalID: "42",
                occurredAt: occurredAt,
                direction: "incoming",
                contact: "Family",
                body: "Please follow up tomorrow."
            )]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(envelope).write(to: fileURL)

        let events = try await MessagesImportCollector(fileURL: fileURL)
            .collect(since: Date().addingTimeInterval(-86_400))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, .messages)
        XCTAssertEqual(events.first?.summary, "Please follow up tomorrow.")
        XCTAssertEqual(events.first?.metadata["importedBy"], "messages-helper")
    }

    func testSyntheticVerticalSliceProducesAtMostThreeStructuredRecommendations() throws {
        let now = Date()
        _ = try store.insert(events: TestDataFactory.events(now: now))

        let events = try store.fetchEvents(since: now.addingTimeInterval(-14 * 86_400))
        let observations = ObservationEngine().analyze(events: events, now: now)
        try store.save(observations: observations)
        let recommendations = RecommendationEngine().generate(from: observations, now: now)
        try store.save(recommendations: recommendations)

        XCTAssertFalse(observations.isEmpty)
        XCTAssertFalse(recommendations.isEmpty)
        XCTAssertLessThanOrEqual(recommendations.count, 3)
        XCTAssertTrue(recommendations.allSatisfy {
            !$0.pattern.isEmpty && !$0.evidence.isEmpty && !$0.recommendedChange.isEmpty &&
            !$0.whereItBelongs.isEmpty && !$0.expectedBenefit.isEmpty
        })
        XCTAssertEqual(try store.fetchRecommendations().count, recommendations.count)
    }

    func testRecommendationActionIsStagedWithoutExternalMutation() throws {
        let recommendation = Recommendation(
            id: "recommendation-1",
            observationID: "observation-1",
            createdAt: Date(),
            pattern: "Repeated workflow",
            evidence: "Seen four times.",
            recommendedChange: "Stage an automation.",
            whereItBelongs: "Personal Systems Agent",
            expectedBenefit: "Save time.",
            status: .open,
            selectedAction: nil,
            actionNote: nil
        )
        try store.save(recommendations: [recommendation])

        try store.updateRecommendation(
            id: recommendation.id,
            status: .staged,
            action: .createAutomation,
            note: "Staged only."
        )

        let restored = try XCTUnwrap(store.fetchRecommendations().first)
        XCTAssertEqual(restored.status, .staged)
        XCTAssertEqual(restored.selectedAction, .createAutomation)
        XCTAssertEqual(restored.actionNote, "Staged only.")
    }

    func testSystemHelperActivityDoesNotProduceRecommendations() throws {
        let now = Date()
        let events = (0..<8).flatMap { index in
            [
                AgentEvent(
                    id: "login-\(index)",
                    occurredAt: now.addingTimeInterval(Double(index) * 60),
                    source: .appActivity,
                    category: .application,
                    title: "loginwindow",
                    summary: "Became the foreground app",
                    metadata: ["bundleID": "com.apple.loginwindow"],
                    sensitivity: .personal,
                    externalID: "login-\(index)"
                ),
                AgentEvent(
                    id: "security-\(index)",
                    occurredAt: now.addingTimeInterval(Double(index) * 60 + 15),
                    source: .appActivity,
                    category: .application,
                    title: "SecurityAgentHelper",
                    summary: "Became the foreground app",
                    metadata: ["bundleID": "com.apple.SecurityAgentHelper.arm64"],
                    sensitivity: .personal,
                    externalID: "security-\(index)"
                )
            ]
        }

        XCTAssertTrue(ObservationEngine().analyze(events: events, now: now).isEmpty)
    }

    func testSavingRecommendationsReplacesOnlyUnactedOpenItems() throws {
        let now = Date()
        let first = Recommendation(
            id: "recommendation-first",
            observationID: "observation-first",
            createdAt: now,
            pattern: "First",
            evidence: "Old evidence",
            recommendedChange: "Old change",
            whereItBelongs: "Old location",
            expectedBenefit: "Old benefit",
            status: .open,
            selectedAction: nil,
            actionNote: nil
        )
        let second = Recommendation(
            id: "recommendation-second",
            observationID: "observation-second",
            createdAt: now,
            pattern: "Second",
            evidence: "Current evidence",
            recommendedChange: "Current change",
            whereItBelongs: "Current location",
            expectedBenefit: "Current benefit",
            status: .open,
            selectedAction: nil,
            actionNote: nil
        )

        try store.save(recommendations: [first])
        try store.save(recommendations: [second])

        XCTAssertEqual(try store.fetchRecommendations().map(\.id), [second.id])
    }

    func testClearingSyntheticDataKeepsRealEventsAndRemovesTestRecommendations() throws {
        let now = Date()
        let realEvent = AgentEvent(
            id: "real-event",
            occurredAt: now,
            source: .appActivity,
            category: .application,
            title: "Real app",
            summary: "Became the foreground app",
            metadata: [:],
            sensitivity: .personal,
            externalID: "real-event"
        )
        _ = try store.insert(events: TestDataFactory.events(now: now) + [realEvent])
        let observations = ObservationEngine().analyze(events: try store.fetchEvents(since: .distantPast), now: now)
        try store.save(observations: observations)
        try store.save(recommendations: RecommendationEngine().generate(from: observations, now: now))

        try store.clearSyntheticData()

        let remaining = try store.fetchEvents(since: .distantPast)
        XCTAssertEqual(remaining.map(\.id), [realEvent.id])
        XCTAssertTrue(try store.fetchRecommendations().isEmpty)
    }
}
