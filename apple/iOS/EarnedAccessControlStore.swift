import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

@MainActor
final class EarnedAccessControlStore: ObservableObject {
    @Published var selection = FamilyActivitySelection()
    @Published var essentialSelection = FamilyActivitySelection()
    @Published private(set) var authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published private(set) var isShielding = false
    @Published private(set) var protectionEnabled = false
    @Published private(set) var allowanceActive = false
    @Published private(set) var allowanceMinutes = 0
    @Published private(set) var allowanceRedemptionID = ""
    @Published private(set) var lastConsumedRedemptionID = ""
    @Published private(set) var morningGateEnabled = false
    @Published private(set) var status = "Allow Screen Time access, then choose apps to begin the local test."

    private let authorizationCenter = AuthorizationCenter.shared
    private let managedStore = ManagedSettingsStore(named: EarnedAccessShared.storeName)
    private let foundationStore = ManagedSettingsStore(named: EarnedAccessShared.foundationStoreName)
    private let activityCenter = DeviceActivityCenter()

    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EarnedAccess", isDirectory: true)
    }

    private var selectionURL: URL { folder.appendingPathComponent("selection.json") }

    init() {
        selection = EarnedAccessShared.loadSelection()
        essentialSelection = EarnedAccessShared.loadEssentialSelection()
        if selection.applicationTokens.isEmpty,
           selection.categoryTokens.isEmpty,
           selection.webDomainTokens.isEmpty,
           let data = try? Data(contentsOf: selectionURL),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
            try? EarnedAccessShared.saveSelection(saved)
        }
        readSharedState()
        if protectionEnabled, !allowanceActive, hasSelection {
            EarnedAccessShared.applyShield(selection: selection, to: managedStore)
            isShielding = true
        }
        refreshMorningGateShield()
        refreshStatus()
    }

    var selectedApplicationCount: Int { selection.applicationTokens.count }
    var selectedCategoryCount: Int { selection.categoryTokens.count }
    var selectedWebsiteCount: Int { selection.webDomainTokens.count }
    var essentialApplicationCount: Int { essentialSelection.applicationTokens.count }
    var essentialWebsiteCount: Int { essentialSelection.webDomainTokens.count }
    var isAuthorized: Bool {
        if authorizationStatus == .approved { return true }
        if #available(iOS 26.4, *) { return authorizationStatus == .approvedWithDataAccess }
        return false
    }
    var hasSelection: Bool {
        selectedApplicationCount + selectedCategoryCount + selectedWebsiteCount > 0
    }
    var hasEssentialSelection: Bool {
        essentialApplicationCount + essentialWebsiteCount > 0
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

    func saveEssentialSelection() {
        do {
            try EarnedAccessShared.saveEssentialSelection(essentialSelection)
            if morningGateEnabled { refreshMorningGateShield() }
            status = "Always-available app selection saved."
        } catch {
            status = "The always-available app selection could not be saved: \(error.localizedDescription)"
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
        EarnedAccessShared.clearAllowance()
        EarnedAccessShared.applyShield(selection: selection, to: managedStore)
        allowanceActive = false
        allowanceMinutes = 0
        allowanceRedemptionID = ""
        isShielding = true
        status = "Earned Access is locked. Complete a requirement to open the selected apps."
    }

    func allowAccess(minutes: Int, redemptionID: String) {
        readSharedState()
        if allowanceActive, allowanceRedemptionID == redemptionID {
            refreshStatus()
            return
        }
        if lastConsumedRedemptionID == redemptionID {
            refreshStatus(success: "That allowance has already been used. Complete another requirement to add more time.")
            return
        }
        authorizationStatus = authorizationCenter.authorizationStatus
        guard protectionEnabled, isAuthorized, hasSelection else {
            status = "Enable Earned Access and choose apps before starting an allowance."
            return
        }

        let safeMinutes = min(120, max(1, minutes))
        do {
            activityCenter.stopMonitoring([EarnedAccessShared.activityName])
            let calendar = Calendar.current
            let start = Date()
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            let components: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute, .second]
            let schedule = DeviceActivitySchedule(
                intervalStart: calendar.dateComponents(components, from: start),
                intervalEnd: calendar.dateComponents(components, from: end),
                repeats: false
            )
            let event: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                event = DeviceActivityEvent(
                    applications: selection.applicationTokens,
                    categories: selection.categoryTokens,
                    webDomains: selection.webDomainTokens,
                    threshold: DateComponents(minute: safeMinutes),
                    includesPastActivity: false
                )
            } else {
                event = DeviceActivityEvent(
                    applications: selection.applicationTokens,
                    categories: selection.categoryTokens,
                    webDomains: selection.webDomainTokens,
                    threshold: DateComponents(minute: safeMinutes)
                )
            }
            try activityCenter.startMonitoring(
                EarnedAccessShared.activityName,
                during: schedule,
                events: [EarnedAccessShared.eventName: event]
            )
            EarnedAccessShared.clearShield(from: managedStore)
            EarnedAccessShared.defaults.set(true, forKey: EarnedAccessShared.allowanceActiveKey)
            EarnedAccessShared.defaults.set(safeMinutes, forKey: EarnedAccessShared.allowanceMinutesKey)
            EarnedAccessShared.defaults.set(redemptionID, forKey: EarnedAccessShared.allowanceRedemptionIDKey)
            allowanceActive = true
            allowanceMinutes = safeMinutes
            allowanceRedemptionID = redemptionID
            isShielding = false
            status = "\(safeMinutes) minutes of selected-app use are available. Unused minutes remain available."
        } catch {
            lockIfEnabled()
            status = "The usage allowance could not start: \(error.localizedDescription)"
        }
    }

    func disableProtection() {
        activityCenter.stopMonitoring([EarnedAccessShared.activityName])
        EarnedAccessShared.clearAllowance()
        EarnedAccessShared.clearShield(from: managedStore)
        protectionEnabled = false
        allowanceActive = false
        allowanceMinutes = 0
        allowanceRedemptionID = ""
        isShielding = false
        EarnedAccessShared.defaults.set(false, forKey: EarnedAccessShared.protectionKey)
        status = "Earned Access protection is off. Your selected apps should open normally."
    }

    func enableMorningGate() {
        authorizationStatus = authorizationCenter.authorizationStatus
        guard isAuthorized else {
            status = "Allow Screen Time access before enabling the morning gate."
            return
        }
        guard hasEssentialSelection else {
            status = "Choose at least one always-available app before enabling the morning gate."
            return
        }
        morningGateEnabled = true
        EarnedAccessShared.defaults.set(true, forKey: EarnedAccessShared.morningGateEnabledKey)
        scheduleMorningGate()
        refreshMorningGateShield()
        status = "The morning gate is on. Daily Routine and your essential selections remain available."
    }

    func disableMorningGate() {
        activityCenter.stopMonitoring([EarnedAccessShared.foundationActivityName])
        EarnedAccessShared.defaults.set(false, forKey: EarnedAccessShared.morningGateEnabledKey)
        EarnedAccessShared.clearFoundationShield(from: foundationStore)
        morningGateEnabled = false
        status = "The morning Truth Before Tasks gate is off."
    }

    func updateMorningFoundation(dateKey: String, completed: Bool) {
        guard morningGateEnabled else { return }
        scheduleMorningGate()
        if completed {
            EarnedAccessShared.defaults.set(dateKey, forKey: EarnedAccessShared.morningFoundationCompleteDateKey)
            EarnedAccessShared.clearFoundationShield(from: foundationStore)
        } else if dateKey == EarnedAccessShared.localDateKey() {
            if EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.morningFoundationCompleteDateKey) == dateKey {
                EarnedAccessShared.defaults.removeObject(forKey: EarnedAccessShared.morningFoundationCompleteDateKey)
            }
            EarnedAccessShared.applyFoundationShield(exceptions: essentialSelection, to: foundationStore)
        }
    }

    func refresh() {
        authorizationStatus = authorizationCenter.authorizationStatus
        readSharedState()
        if !isAuthorized && (protectionEnabled || morningGateEnabled) {
            disableProtection()
            disableMorningGate()
            return
        }
        if protectionEnabled, !allowanceActive, hasSelection {
            EarnedAccessShared.applyShield(selection: selection, to: managedStore)
            isShielding = true
        }
        refreshMorningGateShield()
        refreshStatus()
    }

    var bridgeStatus: [String: String] {
        [
            "authorized": isAuthorized ? "true" : "false",
            "hasSelection": hasSelection ? "true" : "false",
            "protectionEnabled": protectionEnabled ? "true" : "false",
            "shielding": isShielding ? "true" : "false",
            "allowanceActive": allowanceActive ? "true" : "false",
            "allowanceMinutes": String(allowanceMinutes),
            "allowanceRedemptionID": allowanceRedemptionID,
            "lastConsumedRedemptionID": lastConsumedRedemptionID,
            "morningGateEnabled": morningGateEnabled ? "true" : "false",
            "message": status
        ]
    }

    private func readSharedState() {
        protectionEnabled = EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.protectionKey)
        isShielding = EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.shieldingKey)
        allowanceActive = EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.allowanceActiveKey)
        allowanceMinutes = EarnedAccessShared.defaults.integer(forKey: EarnedAccessShared.allowanceMinutesKey)
        allowanceRedemptionID = EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.allowanceRedemptionIDKey) ?? ""
        lastConsumedRedemptionID = EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.lastConsumedRedemptionIDKey) ?? ""
        morningGateEnabled = EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.morningGateEnabledKey)
    }

    private func scheduleMorningGate() {
        guard morningGateEnabled else { return }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        do {
            activityCenter.stopMonitoring([EarnedAccessShared.foundationActivityName])
            try activityCenter.startMonitoring(EarnedAccessShared.foundationActivityName, during: schedule)
        } catch {
            status = "The daily morning gate schedule could not start: \(error.localizedDescription)"
        }
    }

    private func refreshMorningGateShield() {
        guard morningGateEnabled else {
            EarnedAccessShared.clearFoundationShield(from: foundationStore)
            return
        }
        if EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.morningFoundationCompleteDateKey) == EarnedAccessShared.localDateKey() {
            EarnedAccessShared.clearFoundationShield(from: foundationStore)
        } else {
            EarnedAccessShared.applyFoundationShield(exceptions: essentialSelection, to: foundationStore)
        }
    }

    private func selectionSummary(prefix: String) -> String {
        let total = selectedApplicationCount + selectedCategoryCount + selectedWebsiteCount
        return "\(prefix): \(total) selection\(total == 1 ? "" : "s")."
    }

    private func refreshStatus(success: String? = nil) {
        if let success { status = success; return }
        if isAuthorized {
            if protectionEnabled && allowanceActive {
                status = "\(allowanceMinutes) minutes of selected-app use are available."
            } else if protectionEnabled && isShielding {
                status = "Earned Access is locked for \(selectedApplicationCount + selectedCategoryCount + selectedWebsiteCount) selection(s)."
            } else if hasSelection {
                status = selectionSummary(prefix: "Ready to enable")
            } else {
                status = "Screen Time access is authorized. Choose apps for Earned Access."
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
