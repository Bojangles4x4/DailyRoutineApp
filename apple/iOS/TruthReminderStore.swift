import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UIKit
import UserNotifications

struct TruthReminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var imageName: String?
    var selected = true
}

struct TruthReminderPresentation: Identifiable, Equatable {
    let presentationID: String
    let entry: TruthReminder
    let blocking: Bool
    let slotMinute: Int?
    let queuePosition: Int
    let queueTotal: Int

    var id: String { presentationID }
}

struct TruthReminderPresentationDecision: Equatable {
    let entryID: UUID
    let blocking: Bool
}

struct TruthReminderSettings: Codable {
    var enabled = false
    var startMinute = 8 * 60
    var endMinute = 20 * 60
    var interval = 30
    var shuffle = false
    var pauseAppsUntilReviewed = false
    var entries: [TruthReminder] = []
    var scheduledDay = ""
    var scheduledEntryIDs: [String: String] = [:]
    var lastAcknowledgedAt: Date?
    var acknowledgedDay: String?
    var acknowledgedCount: Int?
    var reviewDay: String?
    var reviewTrackingStartMinute: Int?
    var reviewedMinutes: [Int] = []

    private enum CodingKeys: String, CodingKey {
        case enabled, startMinute, endMinute, interval, shuffle, pauseAppsUntilReviewed, entries
        case scheduledDay, scheduledEntryIDs, lastAcknowledgedAt, acknowledgedDay, acknowledgedCount
        case reviewDay, reviewTrackingStartMinute, reviewedMinutes
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        startMinute = try values.decodeIfPresent(Int.self, forKey: .startMinute) ?? 8 * 60
        endMinute = try values.decodeIfPresent(Int.self, forKey: .endMinute) ?? 20 * 60
        interval = try values.decodeIfPresent(Int.self, forKey: .interval) ?? 30
        shuffle = try values.decodeIfPresent(Bool.self, forKey: .shuffle) ?? false
        // App pausing is a separate, explicit choice; notification-only schedules stay notification-only.
        pauseAppsUntilReviewed = try values.decodeIfPresent(Bool.self, forKey: .pauseAppsUntilReviewed) ?? false
        entries = try values.decodeIfPresent([TruthReminder].self, forKey: .entries) ?? []
        scheduledDay = try values.decodeIfPresent(String.self, forKey: .scheduledDay) ?? ""
        scheduledEntryIDs = try values.decodeIfPresent([String: String].self, forKey: .scheduledEntryIDs) ?? [:]
        lastAcknowledgedAt = try values.decodeIfPresent(Date.self, forKey: .lastAcknowledgedAt)
        acknowledgedDay = try values.decodeIfPresent(String.self, forKey: .acknowledgedDay)
        acknowledgedCount = try values.decodeIfPresent(Int.self, forKey: .acknowledgedCount)
        reviewDay = try values.decodeIfPresent(String.self, forKey: .reviewDay)
        reviewTrackingStartMinute = try values.decodeIfPresent(Int.self, forKey: .reviewTrackingStartMinute)
        reviewedMinutes = try values.decodeIfPresent([Int].self, forKey: .reviewedMinutes) ?? []
    }
}

@MainActor
final class TruthReminderStore: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var settings = TruthReminderSettings()
    @Published var status = "Reminders are off. Add a truth, then enable your schedule."
    @Published var busy = false
    @Published var pendingPresentation: TruthReminderPresentation?
    private let center = UNUserNotificationCenter.current()
    private let activityCenter = DeviceActivityCenter()
    private let truthGateStore = ManagedSettingsStore(named: EarnedAccessShared.truthReminderStoreName)
    private let prefix = "dailyRoutine.truth."
    private let categoryIdentifier = "dailyRoutine.truth.category"
    private let acknowledgeActionIdentifier = "dailyRoutine.truth.acknowledge"
    private let safetyUnlockActionIdentifier = "dailyRoutine.truth.safetyUnlock"
    private var queuedNotificationEntryID: UUID?
    private var presentationHostIsReady = false
    private var presentationTask: Task<Void, Never>?
    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TruthReminders", isDirectory: true)
    }

    override init() {
        super.init()
        if let data = try? Data(contentsOf: folder.appendingPathComponent("settings.json")),
           let saved = try? JSONDecoder().decode(TruthReminderSettings.self, from: data) { settings = saved }
        center.delegate = self
        let acknowledge = UNNotificationAction(identifier: acknowledgeActionIdentifier, title: "Review now", options: [.foreground])
        let safetyUnlock = UNNotificationAction(identifier: safetyUnlockActionIdentifier, title: "Safety unlock 15 min", options: [.authenticationRequired])
        center.setNotificationCategories([UNNotificationCategory(identifier: categoryIdentifier, actions: [acknowledge, safetyUnlock], intentIdentifiers: [])])
    }

    var scheduleSummary: String {
        let format: (Int) -> String = { minute in
            let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
            return date.formatted(date: .omitted, time: .shortened)
        }
        return "\(format(settings.startMinute))–\(format(settings.endMinute)) · every \(settings.interval == 60 ? "hour" : settings.interval == 120 ? "2 hours" : "30 minutes")"
    }

    var gateIsActive: Bool {
        EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.truthReminderGateActiveKey)
    }

    var safetyUnlockCountToday: Int {
        let defaults = EarnedAccessShared.defaults
        guard defaults.string(forKey: EarnedAccessShared.truthReminderSafetyUnlockDayKey) == EarnedAccessShared.localDateKey() else { return 0 }
        return defaults.integer(forKey: EarnedAccessShared.truthReminderSafetyUnlockCountKey)
    }

    var lastSafetyUnlockAt: Date? {
        let defaults = EarnedAccessShared.defaults
        guard defaults.string(forKey: EarnedAccessShared.truthReminderSafetyUnlockDayKey) == EarnedAccessShared.localDateKey(),
              defaults.object(forKey: EarnedAccessShared.truthReminderSafetyUnlockLastAtKey) != nil
        else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: EarnedAccessShared.truthReminderSafetyUnlockLastAtKey))
    }

    private var morningFoundationIsIncomplete: Bool {
        EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.morningGateEnabledKey)
            && EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.morningFoundationCompleteDateKey) != EarnedAccessShared.localDateKey()
    }

    func imageURL(_ name: String) -> URL { folder.appendingPathComponent(name) }

    private func persist() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: folder.appendingPathComponent("settings.json"), options: .atomic)
    }

    func saveEntry(id: UUID?, text: String, imageData: Data?, keepImage: Bool) async -> Bool {
        guard !busy else { return false }
        do {
            let existing = settings.entries.first { $0.id == id }
            var entry = existing ?? TruthReminder(text: "")
            entry.text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
            if !keepImage { entry.imageName = nil }
            if let imageData {
                guard let image = UIImage(data: imageData), image.size.width > 0, image.size.height > 0 else {
                    status = "That photo could not be read."; return false
                }
                let scale = min(1, 1200 / max(image.size.width, image.size.height))
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return false }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = UUID().uuidString + ".jpg"
                try jpeg.write(to: imageURL(name), options: .atomic)
                entry.imageName = name
            }
            guard !entry.text.isEmpty || entry.imageName != nil else { status = "Add text or a photo first."; return false }
            if let index = settings.entries.firstIndex(where: { $0.id == entry.id }) { settings.entries[index] = entry }
            else {
                guard settings.entries.count < 50 else { status = "Your library can hold 50 entries."; return false }
                settings.entries.append(entry)
            }
            try persist()
            if settings.enabled { await apply(requestPermission: false) }
            else { status = "Saved in your reminder library." }
            return true
        } catch { status = "Could not save the reminder: \(error.localizedDescription)"; return false }
    }

    func remove(_ entry: TruthReminder) async {
        guard !busy else { return }
        let previous = settings
        settings.entries.removeAll { $0.id == entry.id }
        do {
            try persist()
            // Old photo files stay available to pending notification attachments until rescheduling completes.
            if settings.enabled { await apply(requestPermission: false) }
        } catch { settings = previous; status = "Could not remove that reminder: \(error.localizedDescription)" }
    }

    func refreshForNewDay() async {
        let now = Date()
        prepareReviewState(now: now)
        _ = validatedActiveGateEntry(now: now)
        guard settings.enabled, !busy else { return }
        let day = Calendar.current.startOfDay(for: Date()).description
        if settings.scheduledDay != day || settings.scheduledEntryIDs.isEmpty {
            await apply(requestPermission: false)
            return
        }
        if settings.pauseAppsUntilReviewed {
            do {
                try scheduleNextTruthGate()
            } catch {
                status = "Truth reminders are scheduled, but app pausing needs attention: \(error.localizedDescription)"
            }
        }
    }

    func apply(requestPermission: Bool = true) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if !settings.enabled {
                await clearPending()
                disableTruthGate()
                try persist()
                status = "Reminders are off. Your library is saved."
                return
            }
            guard settings.startMinute >= 0, settings.endMinute < 1440,
                  settings.startMinute <= settings.endMinute, [30, 60, 120].contains(settings.interval) else {
                status = "Choose an end time after the start time, within the same day."; return
            }
            var entries = settings.shuffle ? settings.entries : settings.entries.filter(\.selected)
            guard !entries.isEmpty else {
                await clearPending()
                settings.enabled = false
                disableTruthGate()
                try persist()
                status = "Choose at least one entry before enabling reminders."
                return
            }
            var authorization = await center.notificationSettings().authorizationStatus
            if authorization == .notDetermined && requestPermission {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                authorization = await center.notificationSettings().authorizationStatus
            }
            guard authorization == .authorized || authorization == .provisional else {
                status = "Notifications are not allowed. Enable them in iPhone Settings → Notifications → Daily Routine."
                return
            }
            if settings.shuffle { entries.shuffle() }
            let minutes = Array(stride(from: settings.startMinute, through: settings.endMinute, by: settings.interval))
            var requests: [UNNotificationRequest] = []
            settings.scheduledEntryIDs = [:]
            for (index, minute) in minutes.enumerated() {
                let entry = entries[index % entries.count]
                settings.scheduledEntryIDs[String(minute)] = entry.id.uuidString
                let content = UNMutableNotificationContent()
                content.title = "A moment of truth"
                content.body = entry.text.isEmpty ? "Pause and reflect on your chosen picture." : entry.text
                content.sound = .default
                content.threadIdentifier = "truth-reminders"
                content.categoryIdentifier = categoryIdentifier
                content.userInfo = [
                    "truthReminderID": entry.id.uuidString,
                    "truthReminderMinute": minute
                ]
                if let imageName = entry.imageName {
                    // Notification attachments may be moved by the system; keep the library original.
                    let attachmentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                    try FileManager.default.copyItem(at: imageURL(imageName), to: attachmentURL)
                    content.attachments = [try UNNotificationAttachment(identifier: entry.id.uuidString, url: attachmentURL)]
                }
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minute / 60, minute: minute % 60), repeats: true)
                requests.append(UNNotificationRequest(identifier: prefix + String(minute), content: content, trigger: trigger))
            }
            let old = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
            do {
                for request in requests { try await center.add(request) }
            } catch {
                // Restore the last working schedule if replacement was interrupted.
                center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier))
                for request in old { try? await center.add(request) }
                throw error
            }
            let ids = Set(requests.map(\.identifier))
            center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier).filter { !ids.contains($0) })
            settings.scheduledDay = Calendar.current.startOfDay(for: Date()).description
            try persist()
            if settings.pauseAppsUntilReviewed {
                try scheduleNextTruthGate()
            } else {
                disableTruthGate()
            }
            status = "Scheduled \(requests.count) reminders each day from \(scheduleSummary). \(settings.pauseAppsUntilReviewed ? "Each reminder pauses nonessential apps until you review it." : "Notifications will not pause other apps.")"
        } catch { status = "Could not update reminders: \(error.localizedDescription)" }
    }

    private func clearPending() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier
        let rawID = response.notification.request.content.userInfo["truthReminderID"] as? String
        let minute = (response.notification.request.content.userInfo["truthReminderMinute"] as? Int)
            ?? Int(identifier.split(separator: ".").last.map(String.init) ?? "")

        if identifier.hasPrefix("dailyRoutine.truth."),
           actionIdentifier == "dailyRoutine.truth.safetyUnlock" {
            _ = Self.performSafetyUnlock(
                minute: minute,
                entryID: rawID,
                now: Date()
            )
            completionHandler()
            return
        }

        // Finish the system notification handoff on the callback path before touching
        // SwiftUI. On a cold launch, awaiting the main actor from the async delegate
        // can overlap UIKit's background state-restoration transaction and abort the app.
        completionHandler()

        guard identifier.hasPrefix("dailyRoutine.truth."),
              actionIdentifier == "dailyRoutine.truth.acknowledge"
                || actionIdentifier == UNNotificationDefaultActionIdentifier
        else { return }

        Task { @MainActor [weak self] in
            self?.queuePresentation(entryID: rawID.flatMap(UUID.init(uuidString:)))
        }
    }

    func acknowledge(_ presentation: TruthReminderPresentation) {
        acknowledge(entryID: presentation.entry.id, slotMinute: presentation.slotMinute)
    }

    func appDidBecomeActive() async {
        await refreshForNewDay()
        presentationHostIsReady = true
        requestPresentationReconciliation()
    }

    func appDidResignActive() {
        presentationHostIsReady = false
        presentationTask?.cancel()
        presentationTask = nil
    }

    func morningFoundationDidChange(completed: Bool) {
        if !completed || morningFoundationIsIncomplete {
            suspendTruthGateForMorningFoundation()
            status = "Truth reminders will begin after today’s opening is complete."
            return
        }
        guard settings.enabled && settings.pauseAppsUntilReviewed else { return }
        do {
            settings.reviewDay = EarnedAccessShared.localDateKey()
            settings.reviewTrackingStartMinute = nil
            settings.reviewedMinutes = []
            try persist()
            try scheduleNextTruthGate()
            requestPresentationReconciliation()
        } catch {
            status = "Today’s opening is complete, but the next truth-reminder pause could not be scheduled: \(error.localizedDescription)"
        }
    }

    func dismissPresentation() {
        guard !gateIsActive else { return }
        pendingPresentation = nil
    }

    func safetyUnlockForFifteenMinutes() {
        let now = Date()
        let minute = pendingPresentation?.slotMinute ?? pendingMinutes(now: now).first ?? activeGateMinute()
        let entryID = minute.flatMap { settings.scheduledEntryIDs[String($0)] }
        let scheduled = Self.performSafetyUnlock(minute: minute, entryID: entryID, now: now)
        queuedNotificationEntryID = nil
        pendingPresentation = nil
        let remaining = pendingMinutes(now: now).count
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(15 * 60)
        let unlockUntil = min(now.addingTimeInterval(15 * 60), midnight)
        status = scheduled
            ? "Safety unlock is on until \(unlockUntil.formatted(date: .omitted, time: .shortened)). \(remaining) reminder\(remaining == 1 ? "" : "s") still waiting."
            : "The safety unlock could not be scheduled, so the app pause remains in place."
    }

    private func acknowledge(entryID: UUID?, slotMinute: Int?) {
        let now = Date()
        prepareReviewState(now: now)
        if let slotMinute, settings.reviewedMinutes.contains(slotMinute) {
            pendingPresentation = nil
            requestPresentationReconciliation()
            return
        }
        let today = Calendar.current.startOfDay(for: Date()).description
        settings.acknowledgedCount = settings.acknowledgedDay == today ? (settings.acknowledgedCount ?? 0) + 1 : 1
        settings.acknowledgedDay = today
        settings.lastAcknowledgedAt = now
        if let slotMinute {
            if !settings.reviewedMinutes.contains(slotMinute) {
                settings.reviewedMinutes.append(slotMinute)
                settings.reviewedMinutes.sort()
            }
        }
        do {
            try persist()
        } catch {
            status = "This reminder could not be saved as reviewed, so the app pause remains in place."
            return
        }
        queuedNotificationEntryID = nil
        pendingPresentation = nil
        let remaining = pendingMinutes(now: now)
        do {
            if !remaining.isEmpty {
                try activateGateImmediately(for: remaining[0], now: now)
                status = "Reviewed. \(remaining.count) reminder\(remaining.count == 1 ? "" : "s") still waiting."
                requestPresentationReconciliation()
                return
            }
            clearActiveGate(stopMonitoring: true)
            EarnedAccessShared.clearTruthReminderSafetyUnlock()
            if settings.enabled && settings.pauseAppsUntilReviewed { try scheduleNextTruthGate(after: now) }
            let morningStillLocked = EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.morningGateEnabledKey)
                && EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.morningFoundationCompleteDateKey) != EarnedAccessShared.localDateKey()
            status = morningStillLocked
                ? "Truth reminder cleared. The Morning Gate is still protecting apps until today’s opening is complete."
                : "Acknowledged at \(now.formatted(date: .omitted, time: .shortened))."
        } catch {
            status = "Acknowledged, but the next app pause could not be scheduled: \(error.localizedDescription)"
        }
    }

    private func queuePresentation(entryID: UUID?) {
        queuedNotificationEntryID = entryID
            ?? activeGateEntryID()
            ?? settings.entries.first(where: { settings.shuffle || $0.selected })?.id
        requestPresentationReconciliation()
    }

    private func requestPresentationReconciliation() {
        guard presentationHostIsReady else { return }
        presentationTask?.cancel()
        presentationTask = Task { @MainActor [weak self] in
            // Notification callbacks can arrive while SwiftUI is still constructing the
            // launch window. One run-loop turn gives the single presentation host time
            // to attach and collapses duplicate app/task/scene callbacks into one route.
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.reconcilePendingPresentation()
        }
    }

    private func reconcilePendingPresentation(now: Date = Date()) {
        guard presentationHostIsReady else { return }
        guard !morningFoundationIsIncomplete else {
            queuedNotificationEntryID = nil
            if pendingPresentation?.blocking == true { pendingPresentation = nil }
            return
        }

        prepareReviewState(now: now)
        let waiting = settings.pauseAppsUntilReviewed ? pendingMinutes(now: now) : []
        if let minute = waiting.first,
           let entry = entry(for: minute) {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
            let nowMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            let fullSchedule = Array(stride(from: settings.startMinute, through: settings.endMinute, by: settings.interval))
            let allDue = Self.dueUnreviewedMinutes(
                scheduleMinutes: fullSchedule,
                trackingStartMinute: settings.reviewTrackingStartMinute ?? minute,
                reviewedMinutes: [],
                nowMinute: nowMinute
            ).filter { self.entry(for: $0) != nil }
            let position = (allDue.firstIndex(of: minute) ?? 0) + 1
            queuedNotificationEntryID = nil
            let route = TruthReminderPresentation(
                presentationID: "\(EarnedAccessShared.localDateKey(now)):\(minute)",
                entry: entry,
                blocking: true,
                slotMinute: minute,
                queuePosition: position,
                queueTotal: allDue.count
            )
            if pendingPresentation != route { pendingPresentation = route }
            return
        }

        _ = validatedActiveGateEntry(now: now)
        let availableIDs = Set(settings.entries.map(\.id))
        let decision = Self.presentationDecision(
            queuedEntryID: queuedNotificationEntryID,
            activeGateEntryID: nil,
            availableEntryIDs: availableIDs,
            morningFoundationIsIncomplete: false
        )
        queuedNotificationEntryID = nil

        guard let decision,
              let entry = settings.entries.first(where: { $0.id == decision.entryID })
        else { return }
        let route = TruthReminderPresentation(
            presentationID: "notification:\(entry.id.uuidString)",
            entry: entry,
            blocking: decision.blocking,
            slotMinute: nil,
            queuePosition: 1,
            queueTotal: 1
        )
        if pendingPresentation != route { pendingPresentation = route }
    }

    nonisolated static func presentationDecision(
        queuedEntryID: UUID?,
        activeGateEntryID: UUID?,
        availableEntryIDs: Set<UUID>,
        morningFoundationIsIncomplete: Bool
    ) -> TruthReminderPresentationDecision? {
        guard !morningFoundationIsIncomplete else { return nil }
        if let activeGateEntryID, availableEntryIDs.contains(activeGateEntryID) {
            return TruthReminderPresentationDecision(entryID: activeGateEntryID, blocking: true)
        }
        if let queuedEntryID, availableEntryIDs.contains(queuedEntryID) {
            return TruthReminderPresentationDecision(entryID: queuedEntryID, blocking: false)
        }
        return nil
    }

    private func activeGateEntryID() -> UUID? {
        if let raw = EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.truthReminderGateEntryIDKey),
           let id = UUID(uuidString: raw) { return id }
        let minute = EarnedAccessShared.defaults.integer(forKey: EarnedAccessShared.truthReminderGateMinuteKey)
        return settings.scheduledEntryIDs[String(minute)].flatMap(UUID.init(uuidString:))
    }

    private func activeGateMinute() -> Int? {
        let defaults = EarnedAccessShared.defaults
        guard defaults.object(forKey: EarnedAccessShared.truthReminderGateMinuteKey) != nil else { return nil }
        return defaults.integer(forKey: EarnedAccessShared.truthReminderGateMinuteKey)
    }

    private func entry(for minute: Int) -> TruthReminder? {
        settings.scheduledEntryIDs[String(minute)]
            .flatMap(UUID.init(uuidString:))
            .flatMap { id in settings.entries.first { $0.id == id } }
    }

    private func prepareReviewState(now: Date) {
        let day = EarnedAccessShared.localDateKey(now)
        guard settings.reviewDay != day else { return }
        settings.reviewDay = day
        settings.reviewedMinutes = []
        let defaults = EarnedAccessShared.defaults
        if defaults.bool(forKey: EarnedAccessShared.truthReminderGateActiveKey),
           defaults.string(forKey: EarnedAccessShared.truthReminderGateDateKey) == day {
            settings.reviewTrackingStartMinute = defaults.integer(forKey: EarnedAccessShared.truthReminderGateMinuteKey)
        } else if defaults.string(forKey: EarnedAccessShared.truthReminderGateNextDateKey) == day,
                  defaults.object(forKey: EarnedAccessShared.truthReminderGateNextMinuteKey) != nil {
            settings.reviewTrackingStartMinute = defaults.integer(forKey: EarnedAccessShared.truthReminderGateNextMinuteKey)
        } else {
            settings.reviewTrackingStartMinute = nil
        }
        let safetyDay = defaults.string(forKey: EarnedAccessShared.truthReminderSafetyUnlockDayKey)
        if safetyDay != day { EarnedAccessShared.clearTruthReminderSafetyUnlock() }
        try? persist()
    }

    private func pendingMinutes(now: Date) -> [Int] {
        prepareReviewState(now: now)
        guard settings.reviewDay == EarnedAccessShared.localDateKey(now),
              let start = settings.reviewTrackingStartMinute
        else { return [] }
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let schedule = Array(stride(from: settings.startMinute, through: settings.endMinute, by: settings.interval))
        return Self.dueUnreviewedMinutes(
            scheduleMinutes: schedule,
            trackingStartMinute: start,
            reviewedMinutes: Set(settings.reviewedMinutes),
            nowMinute: nowMinute
        ).filter { entry(for: $0) != nil }
    }

    nonisolated static func dueUnreviewedMinutes(
        scheduleMinutes: [Int],
        trackingStartMinute: Int,
        reviewedMinutes: Set<Int>,
        nowMinute: Int
    ) -> [Int] {
        scheduleMinutes
            .filter { $0 >= trackingStartMinute && $0 <= nowMinute && !reviewedMinutes.contains($0) }
            .sorted()
    }

    private func validatedActiveGateEntry(now: Date = Date()) -> TruthReminder? {
        if safetyUnlockIsActive(now: now) {
            if gateIsActive { EarnedAccessShared.clearTruthReminderGate(from: truthGateStore) }
            return nil
        }
        guard gateIsActive else { return nil }
        guard !morningFoundationIsIncomplete else {
            suspendTruthGateForMorningFoundation()
            status = "Truth reminders will begin after today’s opening is complete."
            return nil
        }
        let defaults = EarnedAccessShared.defaults
        let hasExpiry = defaults.object(forKey: EarnedAccessShared.truthReminderGateExpiresAtKey) != nil
        let expiry = defaults.double(forKey: EarnedAccessShared.truthReminderGateExpiresAtKey)
        let gateDate = defaults.string(forKey: EarnedAccessShared.truthReminderGateDateKey)
        let entry = activeGateEntryID().flatMap { id in settings.entries.first { $0.id == id } }
        guard settings.enabled,
              settings.pauseAppsUntilReviewed,
              hasExpiry,
              expiry > now.timeIntervalSince1970,
              gateDate == EarnedAccessShared.localDateKey(now),
              let entry
        else {
            clearActiveGate(stopMonitoring: true)
            status = "A stale truth-reminder lock was cleared."
            return nil
        }
        return entry
    }

    private func clearActiveGate(stopMonitoring: Bool) {
        if stopMonitoring { activityCenter.stopMonitoring([EarnedAccessShared.truthReminderActivityName]) }
        EarnedAccessShared.clearTruthReminderGate(from: truthGateStore)
    }

    private func safetyUnlockIsActive(now: Date) -> Bool {
        let defaults = EarnedAccessShared.defaults
        return defaults.string(forKey: EarnedAccessShared.truthReminderSafetyUnlockDayKey) == EarnedAccessShared.localDateKey(now)
            && defaults.double(forKey: EarnedAccessShared.truthReminderSafetyUnlockUntilKey) > now.timeIntervalSince1970
    }

    private func suspendTruthGateForMorningFoundation() {
        activityCenter.stopMonitoring([EarnedAccessShared.truthReminderActivityName])
        EarnedAccessShared.defaults.removeObject(forKey: EarnedAccessShared.truthReminderGateNextMinuteKey)
        EarnedAccessShared.defaults.removeObject(forKey: EarnedAccessShared.truthReminderGateNextDateKey)
        EarnedAccessShared.defaults.removeObject(forKey: EarnedAccessShared.truthReminderGateNextEntryIDKey)
        EarnedAccessShared.defaults.removeObject(forKey: EarnedAccessShared.truthReminderGateNextExpiresAtKey)
        EarnedAccessShared.clearTruthReminderGate(from: truthGateStore)
        queuedNotificationEntryID = nil
        pendingPresentation = nil
    }

    private func disableTruthGate() {
        suspendTruthGateForMorningFoundation()
        EarnedAccessShared.defaults.set(false, forKey: EarnedAccessShared.truthReminderGateEnabledKey)
        EarnedAccessShared.clearTruthReminderSafetyUnlock()
    }

    private func scheduleNextTruthGate(after date: Date = Date()) throws {
        guard settings.enabled && settings.pauseAppsUntilReviewed else {
            disableTruthGate()
            return
        }
        guard !morningFoundationIsIncomplete else {
            suspendTruthGateForMorningFoundation()
            status = "Truth reminders will begin after today’s opening is complete."
            return
        }
        guard screenTimeIsAuthorized else {
            throw NSError(domain: "TruthReminderGate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Allow Screen Time in Earned Access before enabling reminder pauses."])
        }
        let essential = EarnedAccessShared.loadEssentialSelection()
        guard !essential.applicationTokens.isEmpty || !essential.webDomainTokens.isEmpty else {
            throw NSError(domain: "TruthReminderGate", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose your always-available apps in Earned Access before enabling reminder pauses."])
        }
        prepareReviewState(now: date)
        if safetyUnlockIsActive(now: date) {
            let unlockUntil = Date(timeIntervalSince1970: EarnedAccessShared.defaults.double(forKey: EarnedAccessShared.truthReminderSafetyUnlockUntilKey))
            let minute = pendingMinutes(now: date).first
                ?? settings.reviewTrackingStartMinute
                ?? settings.startMinute
            try scheduleGateActivity(startingAt: unlockUntil, minute: minute)
            return
        }
        if let waiting = pendingMinutes(now: date).first {
            try activateGateImmediately(for: waiting, now: date)
            return
        }
        let minutes = Array(stride(from: settings.startMinute, through: settings.endMinute, by: settings.interval))
        guard let next = nextOccurrence(in: minutes, after: date) else { return }
        let nextDay = EarnedAccessShared.localDateKey(next.date)
        if settings.reviewDay == nextDay, settings.reviewTrackingStartMinute == nil {
            settings.reviewTrackingStartMinute = next.minute
        }
        try persist()
        try scheduleGateActivity(startingAt: next.date, minute: next.minute)
    }

    private func activateGateImmediately(for minute: Int, now: Date) throws {
        let defaults = EarnedAccessShared.defaults
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(24 * 60 * 60)
        if defaults.double(forKey: EarnedAccessShared.truthReminderGateNextExpiresAtKey) < end.timeIntervalSince1970 - 5 {
            try scheduleGateActivity(startingAt: now.addingTimeInterval(5), minute: minute)
        }
        defaults.set(true, forKey: EarnedAccessShared.truthReminderGateEnabledKey)
        defaults.set(true, forKey: EarnedAccessShared.truthReminderGateActiveKey)
        defaults.set(minute, forKey: EarnedAccessShared.truthReminderGateMinuteKey)
        defaults.set(now.timeIntervalSince1970, forKey: EarnedAccessShared.truthReminderGateActivatedAtKey)
        defaults.set(end.timeIntervalSince1970, forKey: EarnedAccessShared.truthReminderGateExpiresAtKey)
        defaults.set(EarnedAccessShared.localDateKey(now), forKey: EarnedAccessShared.truthReminderGateDateKey)
        if let entryID = settings.scheduledEntryIDs[String(minute)] {
            defaults.set(entryID, forKey: EarnedAccessShared.truthReminderGateEntryIDKey)
        }
        EarnedAccessShared.applyFoundationShield(exceptions: EarnedAccessShared.loadEssentialSelection(), to: truthGateStore)
    }

    private func scheduleGateActivity(startingAt start: Date, minute: Int) throws {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) ?? start.addingTimeInterval(24 * 60 * 60)
        guard start < end else { return }
        activityCenter.stopMonitoring([EarnedAccessShared.truthReminderActivityName])
        let defaults = EarnedAccessShared.defaults
        defaults.set(true, forKey: EarnedAccessShared.truthReminderGateEnabledKey)
        defaults.set(settings.startMinute, forKey: EarnedAccessShared.truthReminderGateDailyStartMinuteKey)
        defaults.set(minute, forKey: EarnedAccessShared.truthReminderGateNextMinuteKey)
        defaults.set(EarnedAccessShared.localDateKey(start), forKey: EarnedAccessShared.truthReminderGateNextDateKey)
        if let entryID = settings.scheduledEntryIDs[String(minute)] {
            defaults.set(entryID, forKey: EarnedAccessShared.truthReminderGateNextEntryIDKey)
        } else {
            defaults.removeObject(forKey: EarnedAccessShared.truthReminderGateNextEntryIDKey)
        }
        defaults.set(end.timeIntervalSince1970, forKey: EarnedAccessShared.truthReminderGateNextExpiresAtKey)
        let components: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute, .second]
        try activityCenter.startMonitoring(
            EarnedAccessShared.truthReminderActivityName,
            during: DeviceActivitySchedule(
                intervalStart: calendar.dateComponents(components, from: start),
                intervalEnd: calendar.dateComponents(components, from: end),
                repeats: false
            )
        )
    }

    nonisolated static func performSafetyUnlock(minute: Int?, entryID: String?, now: Date) -> Bool {
        let calendar = Calendar.current
        let day = EarnedAccessShared.localDateKey(now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(24 * 60 * 60)
        let unlockUntil = min(now.addingTimeInterval(15 * 60), endOfDay)
        guard unlockUntil == endOfDay || minute != nil else { return false }
        let defaults = EarnedAccessShared.defaults
        let previousCount = defaults.string(forKey: EarnedAccessShared.truthReminderSafetyUnlockDayKey) == day
            ? defaults.integer(forKey: EarnedAccessShared.truthReminderSafetyUnlockCountKey)
            : 0
        defaults.set(day, forKey: EarnedAccessShared.truthReminderSafetyUnlockDayKey)
        defaults.set(previousCount + 1, forKey: EarnedAccessShared.truthReminderSafetyUnlockCountKey)
        defaults.set(now.timeIntervalSince1970, forKey: EarnedAccessShared.truthReminderSafetyUnlockLastAtKey)
        defaults.set(unlockUntil.timeIntervalSince1970, forKey: EarnedAccessShared.truthReminderSafetyUnlockUntilKey)

        let center = DeviceActivityCenter()
        center.stopMonitoring([EarnedAccessShared.truthReminderActivityName])
        let store = ManagedSettingsStore(named: EarnedAccessShared.truthReminderStoreName)
        EarnedAccessShared.clearTruthReminderGate(from: store)
        guard unlockUntil < endOfDay, let minute else { return true }

        defaults.set(true, forKey: EarnedAccessShared.truthReminderGateEnabledKey)
        defaults.set(minute, forKey: EarnedAccessShared.truthReminderGateNextMinuteKey)
        defaults.set(day, forKey: EarnedAccessShared.truthReminderGateNextDateKey)
        if let entryID, !entryID.isEmpty {
            defaults.set(entryID, forKey: EarnedAccessShared.truthReminderGateNextEntryIDKey)
        }
        defaults.set(endOfDay.timeIntervalSince1970, forKey: EarnedAccessShared.truthReminderGateNextExpiresAtKey)
        let components: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute, .second]
        do {
            try center.startMonitoring(
                EarnedAccessShared.truthReminderActivityName,
                during: DeviceActivitySchedule(
                    intervalStart: calendar.dateComponents(components, from: unlockUntil),
                    intervalEnd: calendar.dateComponents(components, from: endOfDay),
                    repeats: false
                )
            )
            return true
        } catch {
            EarnedAccessShared.clearTruthReminderSafetyUnlock()
            defaults.set(true, forKey: EarnedAccessShared.truthReminderGateActiveKey)
            defaults.set(minute, forKey: EarnedAccessShared.truthReminderGateMinuteKey)
            defaults.set(now.timeIntervalSince1970, forKey: EarnedAccessShared.truthReminderGateActivatedAtKey)
            defaults.set(endOfDay.timeIntervalSince1970, forKey: EarnedAccessShared.truthReminderGateExpiresAtKey)
            defaults.set(day, forKey: EarnedAccessShared.truthReminderGateDateKey)
            if let entryID, !entryID.isEmpty {
                defaults.set(entryID, forKey: EarnedAccessShared.truthReminderGateEntryIDKey)
            }
            EarnedAccessShared.applyFoundationShield(exceptions: EarnedAccessShared.loadEssentialSelection(), to: store)
            return false
        }
    }

    private func nextOccurrence(in minutes: [Int], after date: Date) -> (minute: Int, date: Date)? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: start) else { continue }
            for minute in minutes {
                guard let candidate = calendar.date(byAdding: .minute, value: minute, to: day), candidate > date else { continue }
                return (minute, candidate)
            }
        }
        return nil
    }

    private var screenTimeIsAuthorized: Bool {
        let authorization = AuthorizationCenter.shared.authorizationStatus
        if authorization == .approved { return true }
        if #available(iOS 26.4, *) { return authorization == .approvedWithDataAccess }
        return false
    }
}
