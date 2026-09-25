import Foundation
import SQLite3

enum EventStoreError: LocalizedError {
    case open(String)
    case statement(String)
    case execute(String)

    var errorDescription: String? {
        switch self {
        case .open(let message), .statement(let message), .execute(let message): message
        }
    }
}

final class SQLiteEventStore {
    let databaseURL: URL
    private var database: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw EventStoreError.open("The local event database could not be opened.")
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try migrate()
        try hardenFilePermissions()
    }

    deinit { sqlite3_close(database) }

    private func hardenFilePermissions() throws {
        let fileManager = FileManager.default
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: databaseURL.deletingLastPathComponent().path
        )
        for url in [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS events (
          id TEXT PRIMARY KEY,
          occurred_at REAL NOT NULL,
          source TEXT NOT NULL,
          category TEXT NOT NULL,
          title TEXT NOT NULL,
          summary TEXT NOT NULL,
          metadata_json TEXT NOT NULL,
          sensitivity TEXT NOT NULL,
          external_id TEXT NOT NULL,
          created_at REAL NOT NULL,
          UNIQUE(source, external_id)
        );
        CREATE INDEX IF NOT EXISTS events_occurred_at ON events(occurred_at DESC);
        CREATE INDEX IF NOT EXISTS events_source ON events(source, occurred_at DESC);
        CREATE TABLE IF NOT EXISTS observations (
          id TEXT PRIMARY KEY,
          created_at REAL NOT NULL,
          kind TEXT NOT NULL,
          title TEXT NOT NULL,
          evidence_json TEXT NOT NULL,
          score REAL NOT NULL,
          event_ids_json TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS recommendations (
          id TEXT PRIMARY KEY,
          observation_id TEXT NOT NULL,
          created_at REAL NOT NULL,
          pattern TEXT NOT NULL,
          evidence TEXT NOT NULL,
          recommended_change TEXT NOT NULL,
          where_it_belongs TEXT NOT NULL,
          expected_benefit TEXT NOT NULL,
          status TEXT NOT NULL,
          selected_action TEXT,
          action_note TEXT
        );
        CREATE TABLE IF NOT EXISTS source_status (
          source TEXT PRIMARY KEY,
          enabled INTEGER NOT NULL,
          permission TEXT NOT NULL,
          last_successful_read REAL,
          detail TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS job_runs (
          id TEXT PRIMARY KEY,
          job TEXT NOT NULL,
          started_at REAL NOT NULL,
          finished_at REAL NOT NULL,
          succeeded INTEGER NOT NULL,
          detail TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS job_runs_job ON job_runs(job, finished_at DESC);
        """)
    }

    @discardableResult
    func insert(events: [AgentEvent]) throws -> Int {
        guard !events.isEmpty else { return 0 }
        return try locked {
            try execute("BEGIN IMMEDIATE;")
            var inserted = 0
            do {
                let sql = "INSERT OR IGNORE INTO events (id, occurred_at, source, category, title, summary, metadata_json, sensitivity, external_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
                for event in events {
                    let metadata = String(data: try encoder.encode(event.metadata), encoding: .utf8) ?? "{}"
                    try withStatement(sql) { statement in
                        bind(event.id, at: 1, to: statement)
                        sqlite3_bind_double(statement, 2, event.occurredAt.timeIntervalSince1970)
                        bind(event.source.rawValue, at: 3, to: statement)
                        bind(event.category.rawValue, at: 4, to: statement)
                        bind(event.title, at: 5, to: statement)
                        bind(event.summary, at: 6, to: statement)
                        bind(metadata, at: 7, to: statement)
                        bind(event.sensitivity.rawValue, at: 8, to: statement)
                        bind(event.externalID, at: 9, to: statement)
                        sqlite3_bind_double(statement, 10, Date().timeIntervalSince1970)
                        try step(statement)
                        inserted += Int(sqlite3_changes(database))
                    }
                }
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
            return inserted
        }
    }

    func fetchEvents(since: Date) throws -> [AgentEvent] {
        try locked {
            var result: [AgentEvent] = []
            try withStatement("SELECT id, occurred_at, source, category, title, summary, metadata_json, sensitivity, external_id FROM events WHERE occurred_at >= ? ORDER BY occurred_at ASC;") { statement in
                sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard
                        let source = AgentSource(rawValue: text(statement, 2)),
                        let category = EventCategory(rawValue: text(statement, 3)),
                        let sensitivity = SensitivityLevel(rawValue: text(statement, 7))
                    else { continue }
                    let metadataData = Data(text(statement, 6).utf8)
                    let metadata = (try? decoder.decode([String: String].self, from: metadataData)) ?? [:]
                    result.append(AgentEvent(
                        id: text(statement, 0),
                        occurredAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                        source: source,
                        category: category,
                        title: text(statement, 4),
                        summary: text(statement, 5),
                        metadata: metadata,
                        sensitivity: sensitivity,
                        externalID: text(statement, 8)
                    ))
                }
            }
            return result
        }
    }

    func clearSyntheticData() throws {
        try locked {
            try execute("BEGIN IMMEDIATE;")
            do {
                try execute("DELETE FROM recommendations WHERE observation_id IN (SELECT id FROM observations WHERE event_ids_json LIKE '%test-%');")
                try execute("DELETE FROM observations WHERE event_ids_json LIKE '%test-%';")
                try execute("DELETE FROM events WHERE id LIKE 'test-%';")
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
        }
    }

    func save(observations: [Observation]) throws {
        try locked {
            let sql = "INSERT OR REPLACE INTO observations (id, created_at, kind, title, evidence_json, score, event_ids_json) VALUES (?, ?, ?, ?, ?, ?, ?);"
            for observation in observations {
                try withStatement(sql) { statement in
                    bind(observation.id, at: 1, to: statement)
                    sqlite3_bind_double(statement, 2, observation.createdAt.timeIntervalSince1970)
                    bind(observation.kind, at: 3, to: statement)
                    bind(observation.title, at: 4, to: statement)
                    bind(String(data: try encoder.encode(observation.evidence), encoding: .utf8) ?? "[]", at: 5, to: statement)
                    sqlite3_bind_double(statement, 6, observation.score)
                    bind(String(data: try encoder.encode(observation.eventIDs), encoding: .utf8) ?? "[]", at: 7, to: statement)
                    try step(statement)
                }
            }
        }
    }

    func save(recommendations: [Recommendation]) throws {
        try locked {
            try execute("BEGIN IMMEDIATE;")
            do {
                try execute("DELETE FROM recommendations WHERE status = 'open' AND selected_action IS NULL;")
                let sql = "INSERT OR IGNORE INTO recommendations (id, observation_id, created_at, pattern, evidence, recommended_change, where_it_belongs, expected_benefit, status, selected_action, action_note) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
                for recommendation in recommendations {
                    try withStatement(sql) { statement in
                        bind(recommendation.id, at: 1, to: statement)
                        bind(recommendation.observationID, at: 2, to: statement)
                        sqlite3_bind_double(statement, 3, recommendation.createdAt.timeIntervalSince1970)
                        bind(recommendation.pattern, at: 4, to: statement)
                        bind(recommendation.evidence, at: 5, to: statement)
                        bind(recommendation.recommendedChange, at: 6, to: statement)
                        bind(recommendation.whereItBelongs, at: 7, to: statement)
                        bind(recommendation.expectedBenefit, at: 8, to: statement)
                        bind(recommendation.status.rawValue, at: 9, to: statement)
                        bindOptional(recommendation.selectedAction?.rawValue, at: 10, to: statement)
                        bindOptional(recommendation.actionNote, at: 11, to: statement)
                        try step(statement)
                    }
                }
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
        }
    }

    func fetchRecommendations() throws -> [Recommendation] {
        try locked {
            var result: [Recommendation] = []
            try withStatement("SELECT id, observation_id, created_at, pattern, evidence, recommended_change, where_it_belongs, expected_benefit, status, selected_action, action_note FROM recommendations ORDER BY created_at DESC;") { statement in
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let status = RecommendationStatus(rawValue: text(statement, 8)) else { continue }
                    let actionText = optionalText(statement, 9)
                    result.append(Recommendation(
                        id: text(statement, 0),
                        observationID: text(statement, 1),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                        pattern: text(statement, 3),
                        evidence: text(statement, 4),
                        recommendedChange: text(statement, 5),
                        whereItBelongs: text(statement, 6),
                        expectedBenefit: text(statement, 7),
                        status: status,
                        selectedAction: actionText.flatMap(RecommendationAction.init(rawValue:)),
                        actionNote: optionalText(statement, 10)
                    ))
                }
            }
            return result
        }
    }

    func updateRecommendation(id: String, status: RecommendationStatus, action: RecommendationAction?, note: String?) throws {
        try locked {
            try withStatement("UPDATE recommendations SET status = ?, selected_action = ?, action_note = ? WHERE id = ?;") { statement in
                bind(status.rawValue, at: 1, to: statement)
                bindOptional(action?.rawValue, at: 2, to: statement)
                bindOptional(note, at: 3, to: statement)
                bind(id, at: 4, to: statement)
                try step(statement)
            }
        }
    }

    func recordSource(_ source: AgentSource, enabled: Bool, permission: PermissionState, successfulAt: Date?, detail: String) throws {
        try locked {
            try withStatement("INSERT INTO source_status (source, enabled, permission, last_successful_read, detail) VALUES (?, ?, ?, ?, ?) ON CONFLICT(source) DO UPDATE SET enabled=excluded.enabled, permission=excluded.permission, last_successful_read=COALESCE(excluded.last_successful_read, source_status.last_successful_read), detail=excluded.detail;") { statement in
                bind(source.rawValue, at: 1, to: statement)
                sqlite3_bind_int(statement, 2, enabled ? 1 : 0)
                bind(permission.rawValue, at: 3, to: statement)
                if let successfulAt { sqlite3_bind_double(statement, 4, successfulAt.timeIntervalSince1970) }
                else { sqlite3_bind_null(statement, 4) }
                bind(detail, at: 5, to: statement)
                try step(statement)
            }
        }
    }

    func sourceDiagnostics() throws -> [SourceDiagnostic] {
        try locked {
            let counts = try eventCounts()
            var statuses: [AgentSource: SourceDiagnostic] = [:]
            try withStatement("SELECT source, enabled, permission, last_successful_read, detail FROM source_status;") { statement in
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let source = AgentSource(rawValue: text(statement, 0)), let permission = PermissionState(rawValue: text(statement, 2)) else { continue }
                    let lastRead = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                    statuses[source] = SourceDiagnostic(source: source, enabled: sqlite3_column_int(statement, 1) == 1, permission: permission, lastSuccessfulRead: lastRead, eventCount: counts[source, default: 0], detail: text(statement, 4))
                }
            }
            return AgentSource.allCases.map { source in
                statuses[source] ?? SourceDiagnostic(source: source, enabled: false, permission: .notRequested, lastSuccessfulRead: nil, eventCount: counts[source, default: 0], detail: "Not configured.")
            }
        }
    }

    func record(job: JobRun) throws {
        try locked {
            try withStatement("INSERT OR REPLACE INTO job_runs (id, job, started_at, finished_at, succeeded, detail) VALUES (?, ?, ?, ?, ?, ?);") { statement in
                bind(job.id, at: 1, to: statement)
                bind(job.job, at: 2, to: statement)
                sqlite3_bind_double(statement, 3, job.startedAt.timeIntervalSince1970)
                sqlite3_bind_double(statement, 4, job.finishedAt.timeIntervalSince1970)
                sqlite3_bind_int(statement, 5, job.succeeded ? 1 : 0)
                bind(job.detail, at: 6, to: statement)
                try step(statement)
            }
        }
    }

    func latestJob(named name: String) throws -> JobRun? {
        try fetchJobs(limit: 50).first { $0.job == name }
    }

    func fetchJobs(limit: Int = 12) throws -> [JobRun] {
        try locked {
            var jobs: [JobRun] = []
            try withStatement("SELECT id, job, started_at, finished_at, succeeded, detail FROM job_runs ORDER BY finished_at DESC LIMIT ?;") { statement in
                sqlite3_bind_int(statement, 1, Int32(limit))
                while sqlite3_step(statement) == SQLITE_ROW {
                    jobs.append(JobRun(
                        id: text(statement, 0),
                        job: text(statement, 1),
                        startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                        finishedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                        succeeded: sqlite3_column_int(statement, 4) == 1,
                        detail: text(statement, 5)
                    ))
                }
            }
            return jobs
        }
    }

    private func eventCounts() throws -> [AgentSource: Int] {
        var result: [AgentSource: Int] = [:]
        try withStatement("SELECT source, COUNT(*) FROM events GROUP BY source;") { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                if let source = AgentSource(rawValue: text(statement, 0)) {
                    result[source] = Int(sqlite3_column_int64(statement, 1))
                }
            }
        }
        return result
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "SQLite operation failed."
            sqlite3_free(error)
            throw EventStoreError.execute(message)
        }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw EventStoreError.statement(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func step(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw EventStoreError.execute(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bindOptional(_ value: String?, at index: Int32, to statement: OpaquePointer) {
        if let value { bind(value, at: index, to: statement) }
        else { sqlite3_bind_null(statement, index) }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func optionalText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return text(statement, index)
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
