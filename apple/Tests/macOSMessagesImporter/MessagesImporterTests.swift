import Foundation
import SQLite3
import XCTest
@testable import Daily_Routine_Messages_Importer

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class MessagesImporterTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyRoutineMessagesImporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directoryURL)
        directoryURL = nil
    }

    func testImporterReadsMessagesDatabaseReadOnlyAndWritesProtectedSnapshot() throws {
        let databaseURL = directoryURL.appendingPathComponent("chat.db")
        let outputURL = directoryURL.appendingPathComponent("output/messages-import-v1.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try createFixtureDatabase(at: databaseURL, messageDate: now.addingTimeInterval(-300))

        let envelope = try MessagesReadOnlyImporter(databaseURL: databaseURL, outputURL: outputURL)
            .importSnapshot(now: now)

        XCTAssertEqual(envelope.version, MessagesImportEnvelope.currentVersion)
        XCTAssertEqual(envelope.source, MessagesImportEnvelope.source)
        XCTAssertEqual(envelope.events.count, 1)
        XCTAssertEqual(envelope.events.first?.direction, "incoming")
        XCTAssertEqual(envelope.events.first?.contact, "Family")
        XCTAssertEqual(envelope.events.first?.body.count, MessagesReadOnlyImporter.maximumBodyCharacters)

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MessagesImportEnvelope.self, from: Data(contentsOf: outputURL))
        XCTAssertEqual(decoded.events, envelope.events)
    }

    func testImporterDoesNotCreateOutputWhenDatabaseCannotBeOpened() throws {
        let outputURL = directoryURL.appendingPathComponent("output/messages-import-v1.json")
        let importer = MessagesReadOnlyImporter(
            databaseURL: directoryURL.appendingPathComponent("missing-chat.db"),
            outputURL: outputURL
        )

        XCTAssertThrowsError(try importer.importSnapshot())
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    private func createFixtureDatabase(at url: URL, messageDate: Date) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else { throw NSError(domain: "MessagesImporterTests", code: 1) }
        defer { sqlite3_close(database) }

        let schema = """
        CREATE TABLE message (ROWID INTEGER PRIMARY KEY, date INTEGER, is_from_me INTEGER, handle_id INTEGER, text TEXT);
        CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE chat_message_join (message_id INTEGER, chat_id INTEGER);
        CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, display_name TEXT);
        INSERT INTO handle (ROWID, id) VALUES (1, '+15555550123');
        INSERT INTO chat (ROWID, display_name) VALUES (1, 'Family');
        INSERT INTO chat_message_join (message_id, chat_id) VALUES (1, 1);
        """
        XCTAssertEqual(sqlite3_exec(database, schema, nil, nil, nil), SQLITE_OK)

        let referenceSeconds = messageDate.timeIntervalSinceReferenceDate
        let appleNanoseconds = Int64(referenceSeconds * 1_000_000_000)
        let body = String(repeating: "follow up ", count: 80)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, "INSERT INTO message (ROWID, date, is_from_me, handle_id, text) VALUES (1, ?, 0, 1, ?);", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, appleNanoseconds)
        sqlite3_bind_text(statement, 2, body, -1, SQLITE_TRANSIENT)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }
}
