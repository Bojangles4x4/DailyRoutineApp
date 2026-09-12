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
    static let allowanceActiveKey = "dailyRoutine.earnedAccess.allowanceActive.v2"
    static let allowanceMinutesKey = "dailyRoutine.earnedAccess.allowanceMinutes.v2"
    static let allowanceRedemptionIDKey = "dailyRoutine.earnedAccess.allowanceRedemptionID.v2"
    static let lastConsumedRedemptionIDKey = "dailyRoutine.earnedAccess.lastConsumedRedemptionID.v2"
    static let essentialSelectionKey = "dailyRoutine.morningFoundation.essentialSelection.v1"
    static let morningGateEnabledKey = "dailyRoutine.morningFoundation.enabled.v1"
    static let morningFoundationCompleteDateKey = "dailyRoutine.morningFoundation.completeDate.v1"
    static let storeName = ManagedSettingsStore.Name("dailyRoutine.earnedAccess")
    static let foundationStoreName = ManagedSettingsStore.Name("dailyRoutine.morningFoundation")
    static let activityName = DeviceActivityName("dailyRoutine.earnedAccess.usage")
    static let eventName = DeviceActivityEvent.Name("dailyRoutine.earnedAccess.budget")
    static let foundationActivityName = DeviceActivityName("dailyRoutine.morningFoundation.daily")

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

    static func loadEssentialSelection() -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: essentialSelectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    static func saveEssentialSelection(_ selection: FamilyActivitySelection) throws {
        defaults.set(try JSONEncoder().encode(selection), forKey: essentialSelectionKey)
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

    static func applyFoundationShield(exceptions: FamilyActivitySelection, to store: ManagedSettingsStore) {
        store.shield.applicationCategories = .all(except: exceptions.applicationTokens)
        store.shield.webDomainCategories = .all(except: exceptions.webDomainTokens)
    }

    static func clearFoundationShield(from store: ManagedSettingsStore) {
        store.clearAllSettings()
    }

    static func clearAllowance(completed: Bool = false) {
        if completed, let redemptionID = defaults.string(forKey: allowanceRedemptionIDKey), !redemptionID.isEmpty {
            defaults.set(redemptionID, forKey: lastConsumedRedemptionIDKey)
        }
        defaults.set(false, forKey: allowanceActiveKey)
        defaults.removeObject(forKey: allowanceMinutesKey)
        defaults.removeObject(forKey: allowanceRedemptionIDKey)
        defaults.removeObject(forKey: unlockedUntilKey)
    }

    static func localDateKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
