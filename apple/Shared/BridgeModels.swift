import Foundation

enum NativeBridgeAction: String, Codable {
    case requestHealthAuthorization = "health.authorization.request"
    case requestHealthSummary = "health.summary.request"
    case updateWatchContext = "watch.context.update"
    case shareText = "share.text"
    case openTruthReminders = "truth.reminders.open"
    case openEarnedAccessControls = "earned.access.controls.open"
    case lockEarnedAccess = "earned.access.lock"
    case allowEarnedAccess = "earned.access.allow"
    case requestEarnedAccessStatus = "earned.access.status.request"
    case lockMorningFoundation = "morning.foundation.lock"
    case completeMorningFoundation = "morning.foundation.complete"
}

struct HealthSummary: Codable, Sendable {
    let date: Date
    let stepCount: Double
    let sleepHours: Double
    let workoutCount: Int
    let sleepStart: Date?
    let sleepEnd: Date?
    let sourceNames: [String]
}

enum WatchQuickAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case completeNext
    case addWater
    case recordMood
    case toggleRoutine
    case takeMedication
    case captureNote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .completeNext: "Complete next"
        case .addWater: "Water +1"
        case .recordMood: "Mood check-in"
        case .toggleRoutine: "Update routine"
        case .takeMedication: "Medication taken"
        case .captureNote: "Capture"
        }
    }
}

struct WatchRoutineItem: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let section: String
    let completed: Bool
    let action: WatchQuickAction
}

struct WatchCustomAction: Codable, Sendable, Hashable {
    let title: String
    let action: WatchQuickAction
    let itemId: String?
    let value: Double?
}

struct WatchEvent: Codable, Sendable {
    let id: UUID
    let action: WatchQuickAction
    let value: Double?
    let itemId: String?
    let text: String?
    let noteType: String?
    let createdAt: Date

    init(
        action: WatchQuickAction,
        value: Double? = nil,
        itemId: String? = nil,
        text: String? = nil,
        noteType: String? = nil
    ) {
        self.id = UUID()
        self.action = action
        self.value = value
        self.itemId = itemId
        self.text = text
        self.noteType = noteType
        self.createdAt = Date()
    }
}

struct WatchRoutineContext: Codable, Sendable {
    let dateKey: String
    let completed: Int
    let total: Int
    let nextItemName: String?
    let canCompleteNext: Bool?
    let truthBeforeTasksComplete: Bool?
    let lastActionMessage: String?
    let items: [WatchRoutineItem]?
    let customAction: WatchCustomAction?

    init(
        dateKey: String,
        completed: Int,
        total: Int,
        nextItemName: String?,
        canCompleteNext: Bool?,
        truthBeforeTasksComplete: Bool? = nil,
        lastActionMessage: String?,
        items: [WatchRoutineItem]? = nil,
        customAction: WatchCustomAction? = nil
    ) {
        self.dateKey = dateKey
        self.completed = completed
        self.total = total
        self.nextItemName = nextItemName
        self.canCompleteNext = canCompleteNext
        self.truthBeforeTasksComplete = truthBeforeTasksComplete
        self.lastActionMessage = lastActionMessage
        self.items = items
        self.customAction = customAction
    }
}
