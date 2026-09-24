import Foundation

struct MessagesImportEnvelope: Codable, Sendable {
    static let currentVersion = 1
    static let source = "apple_messages"

    let version: Int
    let source: String
    let exportedAt: Date
    let windowDays: Int
    let events: [MessagesImportRecord]
}

struct MessagesImportRecord: Codable, Hashable, Sendable {
    let externalID: String
    let occurredAt: Date
    let direction: String
    let contact: String
    let body: String
}

enum MessagesImportLocation {
    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Daily Routine Messages Importer", isDirectory: true)
    }

    static var snapshotURL: URL {
        directoryURL.appendingPathComponent("messages-import-v1.json")
    }
}
