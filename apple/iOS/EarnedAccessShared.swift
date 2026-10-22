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
    static let allowanceRemainingMinutesKey = "dailyRoutine.earnedAccess.allowanceRemainingMinutes.v3"
    static let allowanceExpiresAtKey = "dailyRoutine.earnedAccess.expiresAt.v3"
    static let allowanceDateKey = "dailyRoutine.earnedAccess.dateKey.v4"
    static let allowanceRedemptionIDKey = "dailyRoutine.earnedAccess.allowanceRedemptionID.v2"
    static let allowanceLabelKey = "dailyRoutine.earnedAccess.allowanceLabel.v1"
    static let lastConsumedRedemptionIDKey = "dailyRoutine.earnedAccess.lastConsumedRedemptionID.v2"
    static let essentialSelectionKey = "dailyRoutine.morningFoundation.essentialSelection.v1"
    static let morningGateEnabledKey = "dailyRoutine.morningFoundation.enabled.v1"
    static let morningFoundationCompleteDateKey = "dailyRoutine.morningFoundation.completeDate.v1"
    static let truthReminderGateEnabledKey = "dailyRoutine.truthReminderGate.enabled.v1"
    static let truthReminderGateActiveKey = "dailyRoutine.truthReminderGate.active.v1"
    static let truthReminderGateMinuteKey = "dailyRoutine.truthReminderGate.minute.v1"
    static let truthReminderGateNextMinuteKey = "dailyRoutine.truthReminderGate.nextMinute.v1"
    static let truthReminderGateNextDateKey = "dailyRoutine.truthReminderGate.nextDate.v1"
    static let truthReminderGateDailyStartMinuteKey = "dailyRoutine.truthReminderGate.dailyStartMinute.v1"
    static let truthReminderGateEntryIDKey = "dailyRoutine.truthReminderGate.entryID.v2"
    static let truthReminderGateNextEntryIDKey = "dailyRoutine.truthReminderGate.nextEntryID.v2"
    static let truthReminderGateActivatedAtKey = "dailyRoutine.truthReminderGate.activatedAt.v2"
    static let truthReminderGateExpiresAtKey = "dailyRoutine.truthReminderGate.expiresAt.v2"
    static let truthReminderGateDateKey = "dailyRoutine.truthReminderGate.dateKey.v2"
    static let truthReminderGateNextExpiresAtKey = "dailyRoutine.truthReminderGate.nextExpiresAt.v2"
    static let truthReminderSafetyUnlockUntilKey = "dailyRoutine.truthReminderGate.safetyUnlockUntil.v1"
    static let truthReminderSafetyUnlockDayKey = "dailyRoutine.truthReminderGate.safetyUnlockDay.v1"
    static let truthReminderSafetyUnlockCountKey = "dailyRoutine.truthReminderGate.safetyUnlockCount.v1"
    static let truthReminderSafetyUnlockLastAtKey = "dailyRoutine.truthReminderGate.safetyUnlockLastAt.v1"
    static let essentialSelectionNeedsRepairKey = "dailyRoutine.screenTime.essentialSelectionNeedsRepair.v1"
    static let dayBoundaryIDKey = "dailyRoutine.dayBoundary.id.v1"
    static let dayBoundaryCheckedAtKey = "dailyRoutine.dayBoundary.checkedAt.v1"
    static let dayBoundaryResultKey = "dailyRoutine.dayBoundary.result.v1"
    static let storeName = ManagedSettingsStore.Name("dailyRoutine.earnedAccess")
    static let foundationStoreName = ManagedSettingsStore.Name("dailyRoutine.morningFoundation")
    static let truthReminderStoreName = ManagedSettingsStore.Name("dailyRoutine.truthReminder")
    static let activityName = DeviceActivityName("dailyRoutine.earnedAccess.usage")
    static let eventName = DeviceActivityEvent.Name("dailyRoutine.earnedAccess.budget")
    static let eventPrefix = "dailyRoutine.earnedAccess.minute."
    static let dailyResetActivityName = DeviceActivityName("dailyRoutine.earnedAccess.dailyReset")
    static let foundationActivityName = DeviceActivityName("dailyRoutine.morningFoundation.daily")
    static let truthReminderActivityName = DeviceActivityName("dailyRoutine.truthReminder.next")
    static let balanceNotificationIdentifier = "dailyRoutine.earnedAccess.balance.current"
    static let balanceNotificationIdentifierPrefix = "dailyRoutine.earnedAccess.balance."
    static let balanceNotificationThreadIdentifier = "earned-access-usage"
    static let balanceNotificationGenerationKey = "dailyRoutine.earnedAccess.balance.notificationGeneration.v2"
    static let walkingNotificationIdentifier = "dailyRoutine.walking.progress.current"
    static let walkingNotificationIdentifierPrefix = "dailyRoutine.walking.progress."
    static let walkingNotificationThreadIdentifier = "earned-access-walking"
    static let walkingNotificationGenerationKey = "dailyRoutine.walking.notificationGeneration.v2"
    static let notificationGenerationUserInfoKey = "dailyRoutineNotificationGeneration"
    static let legacyOpenedNotificationPrefix = "dailyRoutine.earnedAccess.opened."
    static let legacyUsageNotificationPrefix = "dailyRoutine.earnedAccess.usage."
    static let legacyWalkingNotificationPrefix = "dailyRoutine.walking."

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

    @discardableResult
    static func applyFoundationShield(exceptions: FamilyActivitySelection, to store: ManagedSettingsStore) -> Bool {
        guard canApplyFoundationShield(
            applicationCount: exceptions.applicationTokens.count,
            websiteCount: exceptions.webDomainTokens.count
        ) else {
            clearFoundationShield(from: store)
            defaults.set(true, forKey: essentialSelectionNeedsRepairKey)
            return false
        }
        store.shield.applicationCategories = .all(except: exceptions.applicationTokens)
        store.shield.webDomainCategories = .all(except: exceptions.webDomainTokens)
        defaults.set(false, forKey: essentialSelectionNeedsRepairKey)
        return true
    }

    static func canApplyFoundationShield(applicationCount: Int, websiteCount: Int) -> Bool {
        applicationCount > 0 || websiteCount > 0
    }

    static func clearFoundationShield(from store: ManagedSettingsStore) {
        store.clearAllSettings()
    }

    static func clearTruthReminderGate(from store: ManagedSettingsStore) {
        clearFoundationShield(from: store)
        defaults.set(false, forKey: truthReminderGateActiveKey)
        defaults.removeObject(forKey: truthReminderGateMinuteKey)
        defaults.removeObject(forKey: truthReminderGateEntryIDKey)
        defaults.removeObject(forKey: truthReminderGateActivatedAtKey)
        defaults.removeObject(forKey: truthReminderGateExpiresAtKey)
        defaults.removeObject(forKey: truthReminderGateDateKey)
    }

    static func clearTruthReminderSafetyUnlock() {
        defaults.removeObject(forKey: truthReminderSafetyUnlockUntilKey)
    }

    static func clearAllowance(completed: Bool = false) {
        if completed, let redemptionID = defaults.string(forKey: allowanceRedemptionIDKey), !redemptionID.isEmpty {
            defaults.set(redemptionID, forKey: lastConsumedRedemptionIDKey)
        }
        defaults.set(false, forKey: allowanceActiveKey)
        defaults.removeObject(forKey: allowanceMinutesKey)
        defaults.removeObject(forKey: allowanceRemainingMinutesKey)
        defaults.removeObject(forKey: allowanceExpiresAtKey)
        defaults.removeObject(forKey: allowanceDateKey)
        defaults.removeObject(forKey: allowanceRedemptionIDKey)
        defaults.removeObject(forKey: allowanceLabelKey)
        defaults.removeObject(forKey: unlockedUntilKey)
    }

    static func eventName(for minute: Int, redemptionID: String) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("\(eventPrefix)\(minute).\(redemptionID)")
    }

    static func usageCheckpoint(from event: DeviceActivityEvent.Name) -> (minute: Int, redemptionID: String)? {
        guard event.rawValue.hasPrefix(eventPrefix) else { return nil }
        let remainder = event.rawValue.dropFirst(eventPrefix.count)
        let parts = remainder.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let minute = Int(parts[0]), !parts[1].isEmpty else { return nil }
        return (minute, parts[1])
    }

    static func usageCheckpoints(totalMinutes: Int) -> [Int] {
        let safeMinutes = min(120, max(1, totalMinutes))
        var checkpoints = Array(stride(from: 5, through: safeMinutes, by: 5))
        if checkpoints.last != safeMinutes { checkpoints.append(safeMinutes) }
        return checkpoints
    }

    static func isBalanceNotification(identifier: String) -> Bool {
        identifier == balanceNotificationIdentifier
            || identifier.hasPrefix(balanceNotificationIdentifierPrefix)
            || identifier.hasPrefix(legacyOpenedNotificationPrefix)
            || identifier.hasPrefix(legacyUsageNotificationPrefix)
    }

    static func isWalkingNotification(identifier: String) -> Bool {
        identifier == walkingNotificationIdentifier
            || identifier.hasPrefix(walkingNotificationIdentifierPrefix)
            || identifier.hasPrefix(legacyWalkingNotificationPrefix)
    }

    static func balanceNotificationIdentifier(generation: String) -> String {
        balanceNotificationIdentifierPrefix + generation
    }

    static func walkingNotificationIdentifier(generation: String) -> String {
        walkingNotificationIdentifierPrefix + generation
    }

    static func shouldRemoveOwnedNotification(
        identifier: String,
        generation: String?,
        currentBalanceGeneration: String,
        currentWalkingGeneration: String,
        includeWalking: Bool
    ) -> Bool {
        if isBalanceNotification(identifier: identifier) {
            return generation != currentBalanceGeneration
        }
        if includeWalking, isWalkingNotification(identifier: identifier) {
            return generation != currentWalkingGeneration
        }
        return false
    }

    static func availableNotificationTitle(minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        return "\(safeMinutes) earned-app minute\(safeMinutes == 1 ? "" : "s") available now"
    }

    static func availableNotificationBody(label: String?) -> String {
        let name = String((label ?? "Your selected earned apps").prefix(80))
        return "\(name) share this current balance. Only foreground use counts."
    }

    static func remainingNotificationTitle(minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        return safeMinutes == 1
            ? "About 1 earned-app minute remains"
            : "About \(safeMinutes) earned-app minutes remain"
    }

    static var balanceNotificationGeneration: String {
        defaults.string(forKey: balanceNotificationGenerationKey) ?? ""
    }

    @discardableResult
    static func advanceBalanceNotificationGeneration() -> String {
        advanceNotificationGeneration(forKey: balanceNotificationGenerationKey)
    }

    static var walkingNotificationGeneration: String {
        defaults.string(forKey: walkingNotificationGenerationKey) ?? ""
    }

    @discardableResult
    static func advanceWalkingNotificationGeneration() -> String {
        advanceNotificationGeneration(forKey: walkingNotificationGenerationKey)
    }

    private static func advanceNotificationGeneration(forKey key: String) -> String {
        let next = UUID().uuidString.lowercased()
        defaults.set(next, forKey: key)
        return next
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
