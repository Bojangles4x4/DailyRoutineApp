import Foundation

enum RoutineSharedActionID {
    static let setCheckboxCompletion = "routine.checkbox.set"
}

struct RoutineSharedItemSnapshot: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let section: String
    let completed: Bool
    let actionID: String
}

struct RoutineSharedSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let revision: Int
    let localDateKey: String
    let timeZoneIdentifier: String
    let foundationComplete: Bool
    let completed: Int
    let total: Int
    let nextItem: RoutineSharedItemSnapshot?
    let eligibleItems: [RoutineSharedItemSnapshot]
    let updatedAt: String

    var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && revision >= 0
            && Self.isValidDateKey(localDateKey)
            && !timeZoneIdentifier.isEmpty
            && completed >= 0
            && total >= completed
            && RoutineSharedDate.parse(updatedAt) != nil
            && eligibleItems.count <= 24
            && Set(eligibleItems.map(\.id)).count == eligibleItems.count
            && eligibleItems.allSatisfy {
                !$0.id.isEmpty
                    && $0.id.count <= 160
                    && !$0.title.isEmpty
                    && $0.title.count <= 160
                    && !Self.containsSensitiveLabel($0.title)
                    && $0.actionID == RoutineSharedActionID.setCheckboxCompletion
            }
            && (nextItem == nil || eligibleItems.contains(nextItem!))
    }

    static func isValidDateKey(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    static func containsSensitiveLabel(_ value: String) -> Bool {
        value.range(
            of: #"\b(pray|prayer|scripture|meds?|medication|medicine|health)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

enum RoutineSharedCommandStatus: String, Codable, Sendable {
    case pending
    case applied
    case rejected
    case superseded
}

struct RoutineSharedCommand: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: String
    let actionID: String
    let origin: String
    let createdAt: String
    let localDateKey: String
    let timeZoneIdentifier: String
    let targetID: String?
    let expectedRevision: Int?
    let requiresFoundationComplete: Bool
    let payload: [String: String]

    var validationMessage: String? {
        guard schemaVersion == Self.currentSchemaVersion else { return "Unsupported command schema." }
        guard !id.isEmpty, id.count <= 160 else { return "Invalid command ID." }
        guard actionID == RoutineSharedActionID.setCheckboxCompletion else { return "Unsupported action." }
        guard ["widget", "app-intent", "shortcut", "watch", "web", "test"].contains(origin) else { return "Unsupported command origin." }
        guard RoutineSharedDate.parse(createdAt) != nil else { return "Invalid creation date." }
        guard RoutineSharedSnapshot.isValidDateKey(localDateKey) else { return "Invalid local date." }
        guard !timeZoneIdentifier.isEmpty, timeZoneIdentifier.count <= 100 else { return "Invalid time zone." }
        guard let targetID, !targetID.isEmpty, targetID.count <= 160 else { return "A target is required." }
        guard let expectedRevision, expectedRevision >= 0 else { return "An expected state revision is required." }
        guard requiresFoundationComplete else { return "Checkbox actions must require the Morning Foundation." }
        guard ["true", "false"].contains(payload["completed"]) else { return "A completed value is required." }
        return nil
    }
}

struct RoutineSharedCommandRecord: Codable, Equatable, Sendable {
    var command: RoutineSharedCommand
    var status: RoutineSharedCommandStatus
    var resolvedAt: String?
    var stateRevision: Int?
    var message: String?
}

struct RoutineSharedCommandJournal: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = Self.currentSchemaVersion
    var revision = 0
    var records: [RoutineSharedCommandRecord] = []
}

enum RoutineSharedStateStoreError: LocalizedError {
    case unavailable
    case invalidSnapshot
    case invalidCommand(String)
    case coordination(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Shared routine storage is unavailable."
        case .invalidSnapshot:
            "The shared routine snapshot was invalid."
        case .invalidCommand(let message):
            message
        case .coordination(let message):
            message
        }
    }
}

final class RoutineSharedStateStore {
    static let appGroupIdentifier = "group.com.bojangles4x4.DailyRoutine"

    private let directoryURL: URL?
    private let fileManager: FileManager
    private let processLock = NSLock()
    private let snapshotFileName = "routine-shared-snapshot-v1.json"
    private let journalFileName = "routine-command-journal-v1.json"
    private let maximumJournalRecords = 200

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        )
        if let directoryURL = self.directoryURL {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    var isAvailable: Bool { directoryURL != nil }

    func save(snapshot: RoutineSharedSnapshot) throws {
        guard snapshot.isValid else { throw RoutineSharedStateStoreError.invalidSnapshot }
        try withProcessLock {
            try coordinatedWrite(to: snapshotURL) { url in
                try Self.encoder.encode(snapshot).write(to: url, options: .atomic)
            }
        }
    }

    func loadSnapshot() throws -> RoutineSharedSnapshot? {
        try withProcessLock {
            try coordinatedRead(from: snapshotURL) { url in
                guard fileManager.fileExists(atPath: url.path) else { return nil }
                let snapshot = try Self.decoder.decode(RoutineSharedSnapshot.self, from: Data(contentsOf: url))
                guard snapshot.isValid else { throw RoutineSharedStateStoreError.invalidSnapshot }
                return snapshot
            }
        }
    }

    @discardableResult
    func enqueue(_ command: RoutineSharedCommand) throws -> RoutineSharedCommandRecord {
        if let message = command.validationMessage {
            throw RoutineSharedStateStoreError.invalidCommand(message)
        }
        return try withProcessLock {
            try updateJournal { journal in
                if let existing = journal.records.first(where: { $0.command.id == command.id }) {
                    return existing
                }
                let record = RoutineSharedCommandRecord(
                    command: command,
                    status: .pending,
                    resolvedAt: nil,
                    stateRevision: nil,
                    message: nil
                )
                journal.records.append(record)
                journal.revision += 1
                Self.prune(&journal, maximum: maximumJournalRecords)
                return record
            }
        }
    }

    func pendingCommands() throws -> [RoutineSharedCommand] {
        try loadJournal().records
            .filter { $0.status == .pending }
            .map(\.command)
    }

    @discardableResult
    func resolve(
        commandID: String,
        status: RoutineSharedCommandStatus,
        stateRevision: Int?,
        message: String?
    ) throws -> RoutineSharedCommandRecord? {
        guard status != .pending else {
            throw RoutineSharedStateStoreError.invalidCommand("A resolved command cannot remain pending.")
        }
        return try withProcessLock {
            try updateJournal { journal in
                guard let index = journal.records.firstIndex(where: { $0.command.id == commandID }) else {
                    return nil
                }
                if journal.records[index].status != .pending {
                    return journal.records[index]
                }
                journal.records[index].status = status
                journal.records[index].resolvedAt = ISO8601DateFormatter.bridge.string(from: Date())
                journal.records[index].stateRevision = stateRevision
                journal.records[index].message = message.map { String($0.prefix(240)) }
                journal.revision += 1
                return journal.records[index]
            }
        }
    }

    func record(commandID: String) throws -> RoutineSharedCommandRecord? {
        try loadJournal().records.first { $0.command.id == commandID }
    }

    private var snapshotURL: URL {
        get throws {
            guard let directoryURL else { throw RoutineSharedStateStoreError.unavailable }
            return directoryURL.appendingPathComponent(snapshotFileName, isDirectory: false)
        }
    }

    private var journalURL: URL {
        get throws {
            guard let directoryURL else { throw RoutineSharedStateStoreError.unavailable }
            return directoryURL.appendingPathComponent(journalFileName, isDirectory: false)
        }
    }

    private func loadJournal() throws -> RoutineSharedCommandJournal {
        try withProcessLock {
            try coordinatedRead(from: journalURL) { url in
                try readJournal(at: url)
            }
        }
    }

    private func updateJournal<Result>(
        _ update: (inout RoutineSharedCommandJournal) throws -> Result
    ) throws -> Result {
        try coordinatedWrite(to: journalURL) { url in
            var journal = try readJournal(at: url)
            let result = try update(&journal)
            try Self.encoder.encode(journal).write(to: url, options: .atomic)
            return result
        }
    }

    private func readJournal(at url: URL) throws -> RoutineSharedCommandJournal {
        guard fileManager.fileExists(atPath: url.path) else { return RoutineSharedCommandJournal() }
        let journal = try Self.decoder.decode(RoutineSharedCommandJournal.self, from: Data(contentsOf: url))
        guard journal.schemaVersion == RoutineSharedCommandJournal.currentSchemaVersion else {
            throw RoutineSharedStateStoreError.invalidCommand("Unsupported command journal schema.")
        }
        return journal
    }

    private func coordinatedRead<Value>(
        from url: URL,
        _ read: (URL) throws -> Value
    ) throws -> Value {
        var coordinationError: NSError?
        var outcome: Swift.Result<Value, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            outcome = Swift.Result { try read(coordinatedURL) }
        }
        if let coordinationError {
            throw RoutineSharedStateStoreError.coordination(coordinationError.localizedDescription)
        }
        guard let outcome else {
            throw RoutineSharedStateStoreError.coordination("Shared-state read did not complete.")
        }
        return try outcome.get()
    }

    private func coordinatedWrite<Value>(
        to url: URL,
        _ write: (URL) throws -> Value
    ) throws -> Value {
        var coordinationError: NSError?
        var outcome: Swift.Result<Value, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinatedURL in
            outcome = Swift.Result { try write(coordinatedURL) }
        }
        if let coordinationError {
            throw RoutineSharedStateStoreError.coordination(coordinationError.localizedDescription)
        }
        guard let outcome else {
            throw RoutineSharedStateStoreError.coordination("Shared-state write did not complete.")
        }
        return try outcome.get()
    }

    private func withProcessLock<Result>(_ operation: () throws -> Result) throws -> Result {
        processLock.lock()
        defer { processLock.unlock() }
        return try operation()
    }

    private static func prune(_ journal: inout RoutineSharedCommandJournal, maximum: Int) {
        guard journal.records.count > maximum else { return }
        let pending = journal.records.filter { $0.status == .pending }
        let resolved = journal.records.filter { $0.status != .pending }
        let resolvedLimit = max(0, maximum - pending.count)
        journal.records = Array(resolved.suffix(resolvedLimit)) + pending
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}

private extension ISO8601DateFormatter {
    static let bridge: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let bridgeWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private enum RoutineSharedDate {
    static func parse(_ value: String) -> Date? {
        ISO8601DateFormatter.bridgeWithFractionalSeconds.date(from: value)
            ?? ISO8601DateFormatter.bridge.date(from: value)
    }
}
