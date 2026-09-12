import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

enum EarnedAccessShared {
    static let suiteName = "group.com.bojangles4x4.DailyRoutine"
    static let selectionKey = "dailyRoutine.earnedAccess.selection.v1"
    static let protectionKey = "dailyRoutine.earnedAccess.protection.v1"
    static let shieldingKey = "dailyRoutine.earnedAccess.shielding.v1"
    static let unlockedUntilKey = "dailyRoutine.earnedAccess.unlockedUntil.v1"
    static let storeName = ManagedSettingsStore.Name("dailyRoutine.earnedAccess")
    static let activityName = DeviceActivityName("dailyRoutine.earnedAccess.allowance")

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func loadSelection() -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    static func saveSelection(_ selection: FamilyActivitySelection) throws {
        defaults.set(try JSONEncoder().encode(selection), forKey: selectionKey)
    }

    static func applyShield(selection: FamilyActivitySelection, to store: ManagedSettingsStore) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        defaults.set(true, forKey: shieldingKey)
        defaults.removeObject(forKey: unlockedUntilKey)
    }

    static func clearShield(from store: ManagedSettingsStore) {
        store.clearAllSettings()
        defaults.set(false, forKey: shieldingKey)
    }
}
