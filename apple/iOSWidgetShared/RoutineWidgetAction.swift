import AppIntents
import Foundation
import WidgetKit

enum RoutineHomeWidgetConstants {
    static let kind = "DailyRoutineHomeWidget"
}

private struct DeferredRoutineSuggestions: Codable {
    let localDateKey: String
    let timeZoneIdentifier: String
    var itemIDs: [String]
}

enum RoutineSuggestionPreferenceStore {
    private static let key = "routine-widget-deferred-suggestions-v1"

    static func itemIDs(localDateKey: String, timeZoneIdentifier: String) -> [String] {
        guard
            let data = defaults.data(forKey: key),
            let value = try? JSONDecoder().decode(DeferredRoutineSuggestions.self, from: data),
            value.localDateKey == localDateKey,
            value.timeZoneIdentifier == timeZoneIdentifier
        else { return [] }
        return value.itemIDs
    }

    static func deferItem(
        _ itemID: String,
        eligibleItemIDs: [String],
        localDateKey: String,
        timeZoneIdentifier: String
    ) {
        var itemIDs = itemIDs(localDateKey: localDateKey, timeZoneIdentifier: timeZoneIdentifier)
        itemIDs.removeAll { $0 == itemID }
        itemIDs.append(itemID)
        let remainingIDs = Set(eligibleItemIDs)
        if !remainingIDs.isEmpty, remainingIDs.allSatisfy({ itemIDs.contains($0) }) {
            itemIDs = [itemID]
        }
        let value = DeferredRoutineSuggestions(
            localDateKey: localDateKey,
            timeZoneIdentifier: timeZoneIdentifier,
            itemIDs: itemIDs
        )
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: RoutineSharedStateStore.appGroupIdentifier) ?? .standard
    }
}

struct DeferRoutineSuggestionIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Another Routine"
    static var description = IntentDescription("Moves the current suggestion aside without completing or skipping it.")
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Parameter(title: "Routine Item") var targetID: String
    @Parameter(title: "Eligible Routine Items") var eligibleItemIDs: [String]
    @Parameter(title: "Local Date") var localDateKey: String
    @Parameter(title: "Time Zone") var timeZoneIdentifier: String

    init() {}

    init(targetID: String, eligibleItemIDs: [String], localDateKey: String, timeZoneIdentifier: String) {
        self.targetID = targetID
        self.eligibleItemIDs = eligibleItemIDs
        self.localDateKey = localDateKey
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    func perform() async throws -> some IntentResult {
        RoutineSuggestionPreferenceStore.deferItem(
            targetID,
            eligibleItemIDs: eligibleItemIDs,
            localDateKey: localDateKey,
            timeZoneIdentifier: timeZoneIdentifier
        )
        WidgetCenter.shared.reloadTimelines(ofKind: RoutineHomeWidgetConstants.kind)
        return .result()
    }
}

struct CompleteRoutineItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Routine Item"
    static var description = IntentDescription("Completes one eligible Daily Routine checkbox after Truth Before Tasks and any configured convictions.")
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

struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Water"
    static var description = IntentDescription("Adds one serving to today’s Daily Routine water goal.")
    static var openAppWhenRun = true
    static var isDiscoverable = false

    @Parameter(title: "Water Item") var targetID: String
    @Parameter(title: "State Revision") var expectedRevision: Int
    @Parameter(title: "Local Date") var localDateKey: String
    @Parameter(title: "Time Zone") var timeZoneIdentifier: String

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
            actionID: RoutineSharedActionID.addWater,
            origin: "widget",
            createdAt: ISO8601DateFormatter.bridge.string(from: Date()),
            localDateKey: localDateKey,
            timeZoneIdentifier: timeZoneIdentifier,
            targetID: targetID,
            expectedRevision: expectedRevision,
            requiresFoundationComplete: true,
            payload: ["delta": "1"]
        )
        _ = try RoutineSharedStateStore().enqueue(command)
        WidgetCenter.shared.reloadTimelines(ofKind: RoutineHomeWidgetConstants.kind)
        return .result()
    }
}
