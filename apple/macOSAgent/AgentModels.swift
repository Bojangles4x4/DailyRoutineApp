import Foundation

enum AgentSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case messages
    case appActivity = "app_activity"
    case calendar
    case dailyRoutine = "daily_routine"
    case testData = "test_data"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .messages: "Apple Messages"
        case .appActivity: "App activity"
        case .calendar: "Calendar"
        case .dailyRoutine: "Daily Routine"
        case .testData: "Test data"
        }
    }
}

enum EventCategory: String, Codable, Sendable {
    case communication
    case application
    case calendar
    case routine
    case project
    case followUp = "follow_up"
    case system
}

enum SensitivityLevel: String, Codable, CaseIterable, Sendable {
    case low
    case personal
    case sensitive
    case restricted

    var title: String { rawValue.capitalized }
}

struct AgentEvent: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let occurredAt: Date
    let source: AgentSource
    let category: EventCategory
    let title: String
    let summary: String
    let metadata: [String: String]
    let sensitivity: SensitivityLevel
    let externalID: String
}

struct Observation: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let createdAt: Date
    let kind: String
    let title: String
    let evidence: [String]
    let score: Double
    let eventIDs: [String]
}

enum RecommendationStatus: String, Codable, Sendable {
    case open
    case staged
    case ignored
    case notUseful = "not_useful"
    case watching
}

enum RecommendationAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case addToRoutine = "add_to_routine"
    case changeReminder = "change_reminder"
    case createProject = "create_project"
    case createAutomation = "create_automation"
    case ignore
    case notUseful = "not_useful"
    case watchLonger = "watch_longer"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addToRoutine: "Add to routine"
        case .changeReminder: "Change reminder"
        case .createProject: "Create project"
        case .createAutomation: "Create automation"
        case .ignore: "Ignore"
        case .notUseful: "Not useful"
        case .watchLonger: "Watch longer"
        }
    }

    var requiresFuturePermission: Bool {
        switch self {
        case .addToRoutine, .changeReminder, .createProject, .createAutomation: true
        case .ignore, .notUseful, .watchLonger: false
        }
    }
}

struct Recommendation: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let observationID: String
    let createdAt: Date
    let pattern: String
    let evidence: String
    let recommendedChange: String
    let whereItBelongs: String
    let expectedBenefit: String
    var status: RecommendationStatus
    var selectedAction: RecommendationAction?
    var actionNote: String?
}

enum PermissionState: String, Codable, Sendable {
    case notRequested = "not_requested"
    case connected
    case denied
    case unavailable
    case needsFullDiskAccess = "needs_full_disk_access"
    case needsMessagesImporter = "needs_messages_importer"

    var title: String {
        switch self {
        case .notRequested: "Not connected"
        case .connected: "Connected"
        case .denied: "Permission denied"
        case .unavailable: "Unavailable"
        case .needsFullDiskAccess: "Needs Full Disk Access"
        case .needsMessagesImporter: "Needs Messages Importer"
        }
    }
}

struct SourceDiagnostic: Identifiable, Codable, Hashable, Sendable {
    var id: String { source.rawValue }
    let source: AgentSource
    let enabled: Bool
    let permission: PermissionState
    let lastSuccessfulRead: Date?
    let eventCount: Int
    let detail: String
}

struct JobRun: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let job: String
    let startedAt: Date
    let finishedAt: Date
    let succeeded: Bool
    let detail: String
}

enum StableID {
    static func make(_ parts: String...) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in parts.joined(separator: "|").utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
