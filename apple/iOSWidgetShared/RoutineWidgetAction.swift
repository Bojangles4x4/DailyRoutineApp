import AppIntents
import Foundation
import WidgetKit

enum RoutineHomeWidgetConstants {
    static let kind = "DailyRoutineHomeWidget"
}

struct CompleteRoutineItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Routine Item"
    static var description = IntentDescription("Completes one eligible Daily Routine checkbox after the Morning Foundation.")
    static var openAppWhenRun = true
    static var isDiscoverable = false

    @Parameter(title: "Routine Item")
    var targetID: String

    @Parameter(title: "State Revision")
    var expectedRevision: Int

    @Parameter(title: "Local Date")
    var localDateKey: String

    @Parameter(title: "Time Zone")
    var timeZoneIdentifier: String

    init() {}

    init(targetID: String, expectedRevision: Int, localDateKey: String, timeZoneIdentifier: String) {
        self.targetID = targetID
        self.expectedRevision = expectedRevision
        self.localDateKey = localDateKey
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    func perform() async throws -> some IntentResult {
        let command = RoutineSharedCommand(
            schemaVersion: RoutineSharedCommand.currentSchemaVersion,
            id: UUID().uuidString,
            actionID: RoutineSharedActionID.setCheckboxCompletion,
            origin: "widget",
            createdAt: ISO8601DateFormatter.bridge.string(from: Date()),
            localDateKey: localDateKey,
            timeZoneIdentifier: timeZoneIdentifier,
            targetID: targetID,
            expectedRevision: expectedRevision,
            requiresFoundationComplete: true,
            payload: ["completed": "true"]
        )

        _ = try RoutineSharedStateStore().enqueue(command)
        WidgetCenter.shared.reloadTimelines(ofKind: RoutineHomeWidgetConstants.kind)
        return .result()
    }
}
