import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

@MainActor
final class EarnedAccessControlStore: ObservableObject {
    @Published var selection = FamilyActivitySelection()
    @Published private(set) var authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published private(set) var isShielding = false
    @Published private(set) var protectionEnabled = false
    @Published private(set) var unlockedUntil: Date?
    @Published private(set) var status = "Allow Screen Time access, then choose apps to begin the local test."

    private let authorizationCenter = AuthorizationCenter.shared
    private let managedStore = ManagedSettingsStore(named: EarnedAccessShared.storeName)
    private let activityCenter = DeviceActivityCenter()

    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EarnedAccess", isDirectory: true)
    }

    private var selectionURL: URL { folder.appendingPathComponent("selection.json") }

    init() {
        selection = EarnedAccessShared.loadSelection()
        if selection.applicationTokens.isEmpty,
           selection.categoryTokens.isEmpty,
           selection.webDomainTokens.isEmpty,
           let data = try? Data(contentsOf: selectionURL),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
            try? EarnedAccessShared.saveSelection(saved)
        }
        protectionEnabled = EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.protectionKey)
        isShielding = EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.shieldingKey)
        unlockedUntil = EarnedAccessShared.defaults.object(forKey: EarnedAccessShared.unlockedUntilKey) as? Date
        if protectionEnabled, let unlockedUntil, unlockedUntil <= Date() {
            EarnedAccessShared.applyShield(selection: selection, to: managedStore)
            self.unlockedUntil = nil
            isShielding = true
        }
        refreshStatus()
    }

    var selectedApplicationCount: Int { selection.applicationTokens.count }
    var selectedCategoryCount: Int { selection.categoryTokens.count }
    var selectedWebsiteCount: Int { selection.webDomainTokens.count }
    var isAuthorized: Bool {
        if authorizationStatus == .approved { return true }
        if #available(iOS 26.4, *) { return authorizationStatus == .approvedWithDataAccess }
        return false
    }
    var hasSelection: Bool {
        selectedApplicationCount + selectedCategoryCount + selectedWebsiteCount > 0
    }

    func requestAuthorization() async {
        do {
            try await authorizationCenter.requestAuthorization(for: .individual)
            authorizationStatus = authorizationCenter.authorizationStatus
            refreshStatus(success: "Screen Time access is authorized. Choose the apps you want Daily Routine to manage.")
        } catch {
            authorizationStatus = authorizationCenter.authorizationStatus
            status = "Screen Time access was not authorized: \(error.localizedDescription)"
        }
    }

    func saveSelection() {
        do {
            try EarnedAccessShared.saveSelection(selection)
            if protectionEnabled && isShielding { lockIfEnabled() }
            else { refreshStatus(success: selectionSummary(prefix: "Selection saved")) }
        } catch {
            status = "The app selection could not be saved: \(error.localizedDescription)"
        }
    }

    func enableProtection() {
        protectionEnabled = true
        EarnedAccessShared.defaults.set(true, forKey: EarnedAccessShared.protectionKey)
        lockIfEnabled()
    }

    func lockIfEnabled() {
        authorizationStatus = authorizationCenter.authorizationStatus
        guard isAuthorized else {
            EarnedAccessShared.clearShield(from: managedStore)
            isShielding = false
            status = "Allow Screen Time access before enabling Earned Access."
            return
        }
        guard hasSelection else {
            EarnedAccessShared.clearShield(from: managedStore)
            isShielding = false
            status = "Choose at least one app, category, or website first."
            return
        }
        guard protectionEnabled else {
            status = "Earned Access protection is off. Enable it before starting a requirement."
            return
        }

        activityCenter.stopMonitoring([EarnedAccessShared.activityName])
        EarnedAccessShared.applyShield(selection: selection, to: managedStore)
        isShielding = true
        unlockedUntil = nil
        status = "Earned Access is locked. Complete a requirement to open the selected apps."
    }

    func allowAccess(until end: Date) {
        refresh()
        guard protectionEnabled, isAuthorized, hasSelection else {
            status = "Enable Earned Access and choose apps before starting an allowance."
            return
        }
        guard end > Date() else { lockIfEnabled(); return }

        do {
            activityCenter.stopMonitoring([EarnedAccessShared.activityName])
            let calendar = Calendar.current
            let components: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute, .second]
            let schedule = DeviceActivitySchedule(
                intervalStart: calendar.dateComponents(components, from: Date()),
                intervalEnd: calendar.dateComponents(components, from: end),
                repeats: false
            )
            try activityCenter.startMonitoring(EarnedAccessShared.activityName, during: schedule)
            EarnedAccessShared.clearShield(from: managedStore)
            EarnedAccessShared.defaults.set(end, forKey: EarnedAccessShared.unlockedUntilKey)
            isShielding = false
            unlockedUntil = end
            status = "Access is open until \(end.formatted(date: .omitted, time: .shortened)). It will lock again automatically."
        } catch {
            lockIfEnabled()
            status = "The timed allowance could not start: \(error.localizedDescription)"
        }
    }

    func disableProtection() {
        activityCenter.stopMonitoring([EarnedAccessShared.activityName])
        EarnedAccessShared.clearShield(from: managedStore)
        protectionEnabled = false
        isShielding = false
        unlockedUntil = nil
        EarnedAccessShared.defaults.set(false, forKey: EarnedAccessShared.protectionKey)
        EarnedAccessShared.defaults.removeObject(forKey: EarnedAccessShared.unlockedUntilKey)
        status = "Earned Access protection is off. Your selected apps should open normally."
    }

    func refresh() {
        authorizationStatus = authorizationCenter.authorizationStatus
        protectionEnabled = EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.protectionKey)
        isShielding = EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.shieldingKey)
        unlockedUntil = EarnedAccessShared.defaults.object(forKey: EarnedAccessShared.unlockedUntilKey) as? Date
        if !isAuthorized && protectionEnabled {
            disableProtection()
            return
        }
        if protectionEnabled, let unlockedUntil, unlockedUntil <= Date() {
            lockIfEnabled()
            return
        }
        refreshStatus()
    }

    var bridgeStatus: [String: String] {
        [
            "authorized": isAuthorized ? "true" : "false",
            "hasSelection": hasSelection ? "true" : "false",
            "protectionEnabled": protectionEnabled ? "true" : "false",
            "shielding": isShielding ? "true" : "false",
            "unlockedUntil": unlockedUntil?.ISO8601Format() ?? "",
            "message": status
        ]
    }

    private func selectionSummary(prefix: String) -> String {
        let total = selectedApplicationCount + selectedCategoryCount + selectedWebsiteCount
        return "\(prefix): \(total) selection\(total == 1 ? "" : "s")."
    }

    private func refreshStatus(success: String? = nil) {
        if let success { status = success; return }
        if isAuthorized {
            if protectionEnabled, let unlockedUntil, unlockedUntil > Date() {
                status = "Access is open until \(unlockedUntil.formatted(date: .omitted, time: .shortened))."
            } else if protectionEnabled && isShielding {
                status = "Earned Access is locked for \(selectedApplicationCount + selectedCategoryCount + selectedWebsiteCount) selection(s)."
            } else if hasSelection {
                status = selectionSummary(prefix: "Ready to enable")
            } else {
                status = "Screen Time access is authorized. Choose apps for the local test."
            }
        } else if authorizationStatus == .denied {
            status = "Screen Time access is off. Enable it in iPhone Settings to continue testing."
        } else if authorizationStatus == .notDetermined {
            status = "Allow Screen Time access, then choose apps to begin the local test."
        } else {
            status = "Screen Time authorization is unavailable."
        }
    }
}
