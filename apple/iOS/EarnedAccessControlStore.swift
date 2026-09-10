import FamilyControls
import Foundation
import ManagedSettings

@MainActor
final class EarnedAccessControlStore: ObservableObject {
    @Published var selection = FamilyActivitySelection()
    @Published private(set) var authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published private(set) var isShielding = false
    @Published private(set) var status = "Allow Screen Time access, then choose apps to begin the local test."

    private let authorizationCenter = AuthorizationCenter.shared
    private let managedStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("dailyRoutine.earnedAccess"))
    private let shieldingKey = "dailyRoutine.earnedAccess.shielding.v1"

    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EarnedAccess", isDirectory: true)
    }

    private var selectionURL: URL { folder.appendingPathComponent("selection.json") }

    init() {
        if let data = try? Data(contentsOf: selectionURL),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        }
        isShielding = UserDefaults.standard.bool(forKey: shieldingKey)
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
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(selection).write(to: selectionURL, options: .atomic)
            if isShielding { applyShield() }
            else { refreshStatus(success: selectionSummary(prefix: "Selection saved")) }
        } catch {
            status = "The app selection could not be saved: \(error.localizedDescription)"
        }
    }

    func applyShield() {
        authorizationStatus = authorizationCenter.authorizationStatus
        guard isAuthorized else {
            managedStore.clearAllSettings()
            isShielding = false
            UserDefaults.standard.set(false, forKey: shieldingKey)
            status = "Allow Screen Time access before testing the block."
            return
        }
        guard hasSelection else {
            managedStore.clearAllSettings()
            isShielding = false
            UserDefaults.standard.set(false, forKey: shieldingKey)
            status = "Choose at least one app, category, or website first."
            return
        }

        managedStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        managedStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        managedStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        isShielding = true
        UserDefaults.standard.set(true, forKey: shieldingKey)
        status = "Test lock is active. Open one of the selected apps to confirm Apple shows the blocking screen."
    }

    func clearShield() {
        managedStore.clearAllSettings()
        isShielding = false
        UserDefaults.standard.set(false, forKey: shieldingKey)
        status = "Test lock removed. Your selected apps should open normally."
    }

    func refresh() {
        authorizationStatus = authorizationCenter.authorizationStatus
        if !isAuthorized && isShielding {
            clearShield()
        } else {
            refreshStatus()
        }
    }

    private func selectionSummary(prefix: String) -> String {
        let total = selectedApplicationCount + selectedCategoryCount + selectedWebsiteCount
        return "\(prefix): \(total) selection\(total == 1 ? "" : "s")."
    }

    private func refreshStatus(success: String? = nil) {
        if let success { status = success; return }
        if isAuthorized {
            if isShielding {
                status = "Test lock is active for \(selectedApplicationCount + selectedCategoryCount + selectedWebsiteCount) selection(s)."
            } else if hasSelection {
                status = selectionSummary(prefix: "Ready to test")
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
