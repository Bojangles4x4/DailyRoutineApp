import AppKit
import EventKit
import Foundation

protocol EventCollecting {
    var source: AgentSource { get }
    func collect(since: Date) async throws -> [AgentEvent]
}

enum CollectorError: LocalizedError {
    case permission(String)
    case unavailable(String)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .permission(let message), .unavailable(let message), .invalidData(let message): message
        }
    }
}

struct MessagesImportCollector: EventCollecting {
    let source = AgentSource.messages
    let fileURL: URL

    init(fileURL: URL = MessagesImportLocation.snapshotURL) {
        self.fileURL = fileURL
    }

    func collect(since: Date) async throws -> [AgentEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CollectorError.permission("Run Daily Routine Messages Importer and grant Full Disk Access only to that helper. The main Agent does not need Full Disk Access.")
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(MessagesImportEnvelope.self, from: data)
            guard envelope.version == MessagesImportEnvelope.currentVersion,
                  envelope.source == MessagesImportEnvelope.source else {
                throw CollectorError.invalidData("The Messages importer snapshot version was not recognized.")
            }
            return envelope.events.compactMap { record in
                guard record.occurredAt >= since else { return nil }
                let fromMe = record.direction == "outgoing"
                return AgentEvent(
                    id: "messages-\(record.externalID)",
                    occurredAt: record.occurredAt,
                    source: .messages,
                    category: .communication,
                    title: fromMe ? "Message sent to \(record.contact)" : "Message received from \(record.contact)",
                    summary: record.body,
                    metadata: ["direction": record.direction, "contact": record.contact, "importedBy": "messages-helper"],
                    sensitivity: .restricted,
                    externalID: record.externalID
                )
            }
        } catch let error as CollectorError {
            throw error
        } catch {
            throw CollectorError.invalidData("The Messages importer snapshot could not be read. Run the helper again to replace it safely.")
        }
    }
}

@MainActor
final class CalendarCollector: EventCollecting {
    let source = AgentSource.calendar
    private let store = EKEventStore()

    var authorizationStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func collect(since: Date) async throws -> [AgentEvent] {
        guard authorizationStatus == .fullAccess else {
            throw CollectorError.permission("Calendar access has not been granted.")
        }
        let end = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let predicate = store.predicateForEvents(withStart: since, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            let externalID = event.eventIdentifier ?? StableID.make(event.title ?? "Calendar event", event.startDate.ISO8601Format())
            let formatter = DateIntervalFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            var metadata = [
                "calendar": event.calendar.title,
                "allDay": event.isAllDay ? "true" : "false"
            ]
            if let location = event.location, !location.isEmpty { metadata["location"] = location }
            return AgentEvent(
                id: "calendar-\(StableID.make(externalID, event.startDate.ISO8601Format()))",
                occurredAt: event.startDate,
                source: .calendar,
                category: .calendar,
                title: event.title ?? "Calendar event",
                summary: formatter.string(from: event.startDate, to: event.endDate),
                metadata: metadata,
                sensitivity: .sensitive,
                externalID: "\(externalID)-\(event.startDate.timeIntervalSince1970)"
            )
        }
    }
}

struct DailyRoutineBackupCollector: EventCollecting {
    let source = AgentSource.dailyRoutine
    let fileURL: URL

    func collect(since: Date) async throws -> [AgentEvent] {
        let data = try Data(contentsOf: fileURL)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let state = (root["state"] as? [String: Any]) ?? root as [String: Any]?,
            let items = state["items"] as? [[String: Any]],
            let days = state["days"] as? [String: Any]
        else {
            throw CollectorError.invalidData("That file is not a valid Daily Routine snapshot or backup.")
        }
        let itemByID = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, [String: Any])? in
            guard let id = item["id"] as? String else { return nil }
            return (id, item)
        })
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        var events: [AgentEvent] = []
        for (dayKey, rawDay) in days {
            guard let date = dayFormatter.date(from: dayKey), date >= since, let day = rawDay as? [String: Any] else { continue }
            let entries = day["entries"] as? [String: Any] ?? [:]
            let skipped = day["skippedItems"] as? [String: Any] ?? [:]
            for (itemID, item) in itemByID where Self.isScheduled(item, on: date) {
                guard (item["kind"] as? String ?? "routine") == "routine" else { continue }
                let title = item["name"] as? String ?? "Routine item"
                let value = entries[itemID]
                let completed = Self.isCompleted(value: value, item: item)
                let wasSkipped = Self.boolValue(skipped[itemID])
                let externalID = "\(dayKey)-\(itemID)"
                events.append(AgentEvent(
                    id: "routine-\(StableID.make(externalID))",
                    occurredAt: Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: date) ?? date,
                    source: .dailyRoutine,
                    category: .routine,
                    title: title,
                    summary: wasSkipped ? "Excused" : completed ? "Completed" : "Not completed",
                    metadata: [
                        "date": dayKey,
                        "itemID": itemID,
                        "section": item["section"] as? String ?? "",
                        "completed": completed ? "true" : "false",
                        "excused": wasSkipped ? "true" : "false"
                    ],
                    sensitivity: .personal,
                    externalID: externalID
                ))
            }
        }
        return events
    }

    private static func isScheduled(_ item: [String: Any], on date: Date) -> Bool {
        let frequency = item["frequency"] as? String ?? "daily"
        let weekday = Calendar.current.component(.weekday, from: date)
        switch frequency {
        case "weekdays": return (2...6).contains(weekday)
        case "weekends": return weekday == 1 || weekday == 7
        case "custom":
            let selected = (item["days"] as? [NSNumber])?.map(\.intValue) ?? []
            return selected.contains(weekday - 1) || selected.contains(weekday)
        default: return true
        }
    }

    private static func isCompleted(value: Any?, item: [String: Any]) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.doubleValue > 0 }
        guard let object = value as? [String: Any] else { return false }
        if boolValue(object["taken"]) || boolValue(object["completed"]) || boolValue(object["reflected"]) { return true }
        if let completed = object["completed"] as? NSNumber { return completed.doubleValue > 0 }
        if let target = item["target"] as? NSNumber, let amount = object["value"] as? NSNumber { return amount.doubleValue >= target.doubleValue }
        return false
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }
}

@MainActor
final class WorkspaceActivityMonitor {
    private var observer: NSObjectProtocol?
    private let onEvent: (AgentEvent) -> Void

    init(onEvent: @escaping (AgentEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let date = Date()
            let bundleID = app.bundleIdentifier ?? "unknown"
            let title = app.localizedName ?? bundleID
            let event = AgentEvent(
                id: "app-\(StableID.make(bundleID, date.ISO8601Format()))",
                occurredAt: date,
                source: .appActivity,
                category: .application,
                title: title,
                summary: "Became the foreground app",
                metadata: ["bundleID": bundleID],
                sensitivity: .personal,
                externalID: "\(bundleID)-\(date.timeIntervalSince1970)"
            )
            Task { @MainActor [weak self] in self?.onEvent(event) }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

enum TestDataFactory {
    static func events(now: Date = Date()) -> [AgentEvent] {
        let calendar = Calendar.current
        var events: [AgentEvent] = []
        for dayOffset in 0..<5 {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            for visit in 0..<3 {
                let date = calendar.date(byAdding: .minute, value: -(visit * 35), to: day) ?? day
                events.append(makeEvent(date: date, source: .appActivity, category: .application, title: "Payroll workbook", summary: "Became the foreground app", suffix: "app-\(dayOffset)-\(visit)"))
            }
            events.append(AgentEvent(
                id: "test-routine-\(dayOffset)",
                occurredAt: day,
                source: .dailyRoutine,
                category: .routine,
                title: "Prepare for tomorrow",
                summary: dayOffset == 1 ? "Completed" : "Not completed",
                metadata: ["date": day.ISO8601Format(), "completed": dayOffset == 1 ? "true" : "false", "excused": "false"],
                sensitivity: .personal,
                externalID: "test-routine-\(dayOffset)"
            ))
        }
        events.append(makeEvent(date: now.addingTimeInterval(-5000), source: .messages, category: .communication, title: "Message received", summary: "Can you follow up on the insurance form?", suffix: "message-1", sensitivity: .restricted))
        events.append(makeEvent(date: now.addingTimeInterval(-90000), source: .messages, category: .communication, title: "Message received", summary: "Please remember to follow up with the benefits team.", suffix: "message-2", sensitivity: .restricted))
        return events
    }

    private static func makeEvent(date: Date, source: AgentSource, category: EventCategory, title: String, summary: String, suffix: String, sensitivity: SensitivityLevel = .personal) -> AgentEvent {
        AgentEvent(id: "test-\(suffix)", occurredAt: date, source: source, category: category, title: title, summary: summary, metadata: [:], sensitivity: sensitivity, externalID: suffix)
    }
}
