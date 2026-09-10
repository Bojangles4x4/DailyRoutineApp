import Foundation
import UIKit
import UserNotifications

struct TruthReminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var imageName: String?
    var selected = true
}

struct TruthReminderSettings: Codable {
    var enabled = false
    var startMinute = 8 * 60
    var endMinute = 20 * 60
    var interval = 30
    var shuffle = false
    var entries: [TruthReminder] = []
    var scheduledDay = ""
}

@MainActor
final class TruthReminderStore: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var settings = TruthReminderSettings()
    @Published var status = "Reminders are off. Add a truth, then enable your schedule."
    @Published var busy = false
    private let center = UNUserNotificationCenter.current()
    private let prefix = "dailyRoutine.truth."
    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TruthReminders", isDirectory: true)
    }

    override init() {
        super.init()
        if let data = try? Data(contentsOf: folder.appendingPathComponent("settings.json")),
           let saved = try? JSONDecoder().decode(TruthReminderSettings.self, from: data) { settings = saved }
        center.delegate = self
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
        guard settings.enabled, !busy else { return }
        let day = Calendar.current.startOfDay(for: Date()).description
        if settings.scheduledDay != day { await apply(requestPermission: false) }
    }

    func apply(requestPermission: Bool = true) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if !settings.enabled {
                await clearPending()
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
            for (index, minute) in minutes.enumerated() {
                let entry = entries[index % entries.count]
                let content = UNMutableNotificationContent()
                content.title = "A moment of truth"
                content.body = entry.text.isEmpty ? "Pause and reflect on your chosen picture." : entry.text
                content.sound = .default
                content.threadIdentifier = "truth-reminders"
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
            status = "Scheduled \(requests.count) reminders per day. \(settings.shuffle ? "The mix refreshes when you open the app on a new day." : "Your selected entries repeat in library order.")"
        } catch { status = "Could not update reminders: \(error.localizedDescription)" }
    }

    private func clearPending() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
