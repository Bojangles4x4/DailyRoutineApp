import Foundation

enum NativeBridgeAction: String, Codable {
    case requestHealthAuthorization = "health.authorization.request"
    case requestHealthSummary = "health.summary.request"
    case updateWatchContext = "watch.context.update"
}

struct HealthSummary: Codable, Sendable {
    let date: Date
    let stepCount: Double
    let sleepHours: Double
    let workoutCount: Int
}

enum WatchQuickAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case completeNext
    case addWater
    case recordMood

    var id: String { rawValue }

    var title: String {
        switch self {
        case .completeNext: "Complete next"
        case .addWater: "Water +1"
        case .recordMood: "Mood check-in"
        }
    }
}

struct WatchEvent: Codable, Sendable {
    let id: UUID
    let action: WatchQuickAction
    let value: Double?
    let createdAt: Date

    init(action: WatchQuickAction, value: Double? = nil) {
        self.id = UUID()
        self.action = action
        self.value = value
        self.createdAt = Date()
    }
}

struct WatchRoutineContext: Codable, Sendable {
    let dateKey: String
    let completed: Int
    let total: Int
    let nextItemName: String?
}
