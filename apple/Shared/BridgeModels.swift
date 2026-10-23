import Foundation

enum NativeBridgeAction: String, Codable {
    case updateAppearance = "app.appearance.update"
    case requestHealthAuthorization = "health.authorization.request"
    case requestHealthSummary = "health.summary.request"
    case configureStepRewards = "health.step-rewards.configure"
    case updateWatchContext = "watch.context.update"
    case shareText = "share.text"
    case shareFile = "share.file"
    case saveSafetySnapshot = "safety.snapshot.save"
    case requestSafetySnapshotStatus = "safety.snapshot.status.request"
    case loadSafetySnapshot = "safety.snapshot.load"
    case openTruthReminders = "truth.reminders.open"
    case openEarnedAccessControls = "earned.access.controls.open"
    case lockEarnedAccess = "earned.access.lock"
    case allowEarnedAccess = "earned.access.allow"
    case requestEarnedAccessStatus = "earned.access.status.request"
    case reconcileDayBoundary = "day.boundary.reconcile"
    case lockMorningFoundation = "morning.foundation.lock"
    case completeMorningFoundation = "morning.foundation.complete"
    case publishRoutineSnapshot = "routine.snapshot.publish"
    case requestRoutineCommands = "routine.commands.request"
    case acknowledgeRoutineCommand = "routine.command.acknowledge"
}

struct HealthSummary: Codable, Sendable {
    let date: Date
    let stepCount: Double
    let stepSampleEnd: Date?
    let deviceStepsSinceStart: Double?
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
    let medicationList: [String]?

    init(
        id: String,
        name: String,
        section: String,
        completed: Bool,
        action: WatchQuickAction,
        medicationList: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.section = section
        self.completed = completed
        self.action = action
        self.medicationList = medicationList
    }
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
    let contextDateKey: String?
    let timeZoneIdentifier: String?

    init(
        id: UUID = UUID(),
        action: WatchQuickAction,
        value: Double? = nil,
        itemId: String? = nil,
        text: String? = nil,
        noteType: String? = nil,
        createdAt: Date = Date(),
        contextDateKey: String? = nil,
        timeZoneIdentifier: String? = nil
    ) {
        self.id = id
        self.action = action
        self.value = value
        self.itemId = itemId
        self.text = text
        self.noteType = noteType
        self.createdAt = createdAt
        self.contextDateKey = contextDateKey
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

struct WatchRoutineContext: Codable, Sendable {
    let dateKey: String
    let timeZoneIdentifier: String?
    let completed: Int
    let total: Int
    let nextItemName: String?
    let canCompleteNext: Bool?
    let truthBeforeTasksComplete: Bool?
    let lastActionMessage: String?
    let items: [WatchRoutineItem]?
    let customAction: WatchCustomAction?
    let stepCount: Int?
    let healthUpdatedAt: String?

    init(
        dateKey: String,
        timeZoneIdentifier: String? = nil,
        completed: Int,
        total: Int,
        nextItemName: String?,
        canCompleteNext: Bool?,
        truthBeforeTasksComplete: Bool? = nil,
        lastActionMessage: String?,
        items: [WatchRoutineItem]? = nil,
        customAction: WatchCustomAction? = nil,
        stepCount: Int? = nil,
        healthUpdatedAt: String? = nil
    ) {
        self.dateKey = dateKey
        self.timeZoneIdentifier = timeZoneIdentifier
        self.completed = completed
        self.total = total
        self.nextItemName = nextItemName
        self.canCompleteNext = canCompleteNext
        self.truthBeforeTasksComplete = truthBeforeTasksComplete
        self.lastActionMessage = lastActionMessage
        self.items = items
        self.customAction = customAction
        self.stepCount = stepCount
        self.healthUpdatedAt = healthUpdatedAt
    }
}
