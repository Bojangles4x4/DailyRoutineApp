import Foundation

struct RoutineWidgetSnapshot: Codable, Sendable {
    let completed: Int
    let total: Int
    let nextItemName: String?
    let lastActionMessage: String?
    let truthBeforeTasksComplete: Bool?
    let updatedAt: Date

    init(
        completed: Int,
        total: Int,
        nextItemName: String?,
        lastActionMessage: String?,
        truthBeforeTasksComplete: Bool? = nil,
        updatedAt: Date = Date()
    ) {
        self.completed = completed
        self.total = total
        self.nextItemName = nextItemName
        self.lastActionMessage = lastActionMessage
        self.truthBeforeTasksComplete = truthBeforeTasksComplete
        self.updatedAt = updatedAt
    }

    init(context: WatchRoutineContext) {
        self.init(
            completed: context.completed,
            total: context.total,
            nextItemName: context.nextItemName,
            lastActionMessage: context.lastActionMessage,
            truthBeforeTasksComplete: context.truthBeforeTasksComplete
        )
    }

    static let preview = RoutineWidgetSnapshot(
        completed: 6,
        total: 9,
        nextItemName: "Evening walk",
        lastActionMessage: nil,
        truthBeforeTasksComplete: true
    )

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

enum WidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.bojangles4x4.DailyRoutine"
    static let widgetKind = "DailyRoutineProgressWidget"
    private static let snapshotKey = "routineWidgetSnapshot"

    static func save(context: WatchRoutineContext) {
        guard let data = try? JSONEncoder().encode(RoutineWidgetSnapshot(context: context)) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func load() -> RoutineWidgetSnapshot? {
        guard
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(RoutineWidgetSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}
