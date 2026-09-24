import Foundation
import SQLite3

enum MessagesImporterError: LocalizedError {
    case needsFullDiskAccess
    case unsupportedDatabase
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .needsFullDiskAccess:
            "The Messages database is unavailable. Grant Full Disk Access to Daily Routine Messages Importer, quit it, and reopen it."
        case .unsupportedDatabase:
            "The Messages database format was not recognized. No snapshot was changed."
        case .invalidOutput:
            "The privacy-limited Messages snapshot could not be written."
        }
    }
}

struct MessagesReadOnlyImporter {
    static let windowDays = 14
    static let maximumEvents = 5_000
    static let maximumBodyCharacters = 500

    let databaseURL: URL
    let outputURL: URL

    init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db"),
        outputURL: URL = MessagesImportLocation.snapshotURL
    ) {
        self.databaseURL = databaseURL
        self.outputURL = outputURL
    }

    func importSnapshot(now: Date = Date()) throws -> MessagesImportEnvelope {
        let since = now.addingTimeInterval(-Double(Self.windowDays) * 86_400)
        let records = try readRecords(since: since)
        let envelope = MessagesImportEnvelope(
            version: MessagesImportEnvelope.currentVersion,
            source: MessagesImportEnvelope.source,
            exportedAt: now,
            windowDays: Self.windowDays,
            events: records
        )
        try write(envelope)
        return envelope
    }

    private func readRecords(since: Date) throws -> [MessagesImportRecord] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            throw MessagesImporterError.needsFullDiskAccess
        }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT m.ROWID, m.date, m.is_from_me, COALESCE(h.id, ''), COALESCE(m.text, ''), COALESCE(c.display_name, '')
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE m.date >= ? AND m.text IS NOT NULL AND LENGTH(TRIM(m.text)) > 0
        ORDER BY m.date ASC
        LIMIT ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MessagesImporterError.unsupportedDatabase
        }
        defer { sqlite3_finalize(statement) }

        let appleEpochOffset = Date(timeIntervalSinceReferenceDate: 0).timeIntervalSince1970
        let appleNanoseconds = max(0, (since.timeIntervalSince1970 - appleEpochOffset) * 1_000_000_000)
        sqlite3_bind_int64(statement, 1, Int64(appleNanoseconds))
        sqlite3_bind_int(statement, 2, Int32(Self.maximumEvents))

        var records: [MessagesImportRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rawDate = sqlite3_column_int64(statement, 1)
            let seconds = rawDate > 10_000_000_000 ? Double(rawDate) / 1_000_000_000 : Double(rawDate)
            let occurredAt = Date(timeIntervalSinceReferenceDate: seconds)
            guard occurredAt >= since else { continue }

            let fromMe = sqlite3_column_int(statement, 2) == 1
            let handle = Self.text(statement, 3)
            let body = Self.text(statement, 4).trimmingCharacters(in: .whitespacesAndNewlines)
            let chatName = Self.text(statement, 5).trimmingCharacters(in: .whitespacesAndNewlines)
            let contact = chatName.isEmpty ? (handle.isEmpty ? "a conversation" : handle) : chatName
            records.append(MessagesImportRecord(
                externalID: String(sqlite3_column_int64(statement, 0)),
                occurredAt: occurredAt,
                direction: fromMe ? "outgoing" : "incoming",
                contact: String(contact.prefix(200)),
                body: String(body.prefix(Self.maximumBodyCharacters))
            ))
        }
        return records
    }

    private func write(_ envelope: MessagesImportEnvelope) throws {
        let directory = outputURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".messages-import-\(UUID().uuidString).json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(envelope)
            guard FileManager.default.createFile(
                atPath: temporaryURL.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw MessagesImporterError.invalidOutput
            }
            if FileManager.default.fileExists(atPath: outputURL.path) {
                _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw MessagesImporterError.invalidOutput
        }
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }
}
