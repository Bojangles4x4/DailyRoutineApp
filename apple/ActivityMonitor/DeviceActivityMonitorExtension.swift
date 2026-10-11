import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UserNotifications

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: EarnedAccessShared.storeName)
    private let foundationStore = ManagedSettingsStore(named: EarnedAccessShared.foundationStoreName)
    private let truthReminderStore = ManagedSettingsStore(named: EarnedAccessShared.truthReminderStoreName)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == EarnedAccessShared.dailyResetActivityName {
            enforceDailyReset()
            return
        }
        if activity == EarnedAccessShared.truthReminderActivityName {
            enforceTruthReminderGate()
            return
        }
        guard activity == EarnedAccessShared.foundationActivityName,
              EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.morningGateEnabledKey)
        else { return }

        enforceDailyReset()

        let today = EarnedAccessShared.localDateKey()
        guard EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.morningFoundationCompleteDateKey) != today else { return }

        EarnedAccessShared.applyFoundationShield(
            exceptions: EarnedAccessShared.loadEssentialSelection(),
            to: foundationStore
        )
    }

    private func enforceTruthReminderGate() {
        guard EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.truthReminderGateEnabledKey) else {
            EarnedAccessShared.clearTruthReminderGate(from: truthReminderStore)
            return
        }
        let now = Date()
        let morningFoundationIsIncomplete = EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.morningGateEnabledKey)
            && EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.morningFoundationCompleteDateKey) != EarnedAccessShared.localDateKey(now)
        guard !morningFoundationIsIncomplete else {
            EarnedAccessShared.clearTruthReminderGate(from: truthReminderStore)
            return
        }
        let safetyUnlockUntil = EarnedAccessShared.defaults.double(forKey: EarnedAccessShared.truthReminderSafetyUnlockUntilKey)
        guard safetyUnlockUntil <= now.timeIntervalSince1970 + 5 else {
            EarnedAccessShared.clearTruthReminderGate(from: truthReminderStore)
            return
        }
        EarnedAccessShared.clearTruthReminderSafetyUnlock()
        let minute = EarnedAccessShared.defaults.integer(forKey: EarnedAccessShared.truthReminderGateNextMinuteKey)
        let scheduledExpiry = EarnedAccessShared.defaults.double(forKey: EarnedAccessShared.truthReminderGateNextExpiresAtKey)
        EarnedAccessShared.defaults.set(true, forKey: EarnedAccessShared.truthReminderGateActiveKey)
        EarnedAccessShared.defaults.set(minute, forKey: EarnedAccessShared.truthReminderGateMinuteKey)
        EarnedAccessShared.defaults.set(now.timeIntervalSince1970, forKey: EarnedAccessShared.truthReminderGateActivatedAtKey)
        EarnedAccessShared.defaults.set(scheduledExpiry, forKey: EarnedAccessShared.truthReminderGateExpiresAtKey)
        EarnedAccessShared.defaults.set(EarnedAccessShared.localDateKey(now), forKey: EarnedAccessShared.truthReminderGateDateKey)
        if let entryID = EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.truthReminderGateNextEntryIDKey), !entryID.isEmpty {
            EarnedAccessShared.defaults.set(entryID, forKey: EarnedAccessShared.truthReminderGateEntryIDKey)
        }
        EarnedAccessShared.applyFoundationShield(
            exceptions: EarnedAccessShared.loadEssentialSelection(),
            to: truthReminderStore
        )
    }

    private func enforceDailyReset(now: Date = Date()) {
        guard EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.protectionKey) else { return }
        let allowanceActive = EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.allowanceActiveKey)
        let allowanceDate = EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.allowanceDateKey)
        let expiresAt = EarnedAccessShared.defaults.object(forKey: EarnedAccessShared.allowanceExpiresAtKey) == nil
            ? nil
            : EarnedAccessShared.defaults.double(forKey: EarnedAccessShared.allowanceExpiresAtKey)
        let allowanceIsCurrent = allowanceActive
            && allowanceDate == EarnedAccessShared.localDateKey(now)
            && (expiresAt ?? 0) > now.timeIntervalSince1970
        guard !allowanceIsCurrent else { return }

        DeviceActivityCenter().stopMonitoring([EarnedAccessShared.activityName])
        EarnedAccessShared.applyShield(selection: EarnedAccessShared.loadSelection(), to: store)
        if allowanceActive { EarnedAccessShared.clearAllowance() }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == EarnedAccessShared.truthReminderActivityName {
            EarnedAccessShared.clearTruthReminderGate(from: truthReminderStore)
            let scheduledEnd = EarnedAccessShared.defaults.double(forKey: EarnedAccessShared.truthReminderGateNextExpiresAtKey)
            let safetyUntil = EarnedAccessShared.defaults.double(forKey: EarnedAccessShared.truthReminderSafetyUnlockUntilKey)
            let now = Date()
            if safetyUntil <= now.timeIntervalSince1970 + 5 {
                EarnedAccessShared.clearTruthReminderSafetyUnlock()
            }
            if scheduledEnd <= now.timeIntervalSince1970 + 5 {
                scheduleNextTruthReminderDay(after: now)
            }
            return
        }
        guard activity == EarnedAccessShared.activityName,
              EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.protectionKey),
              EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.allowanceActiveKey),
              EarnedAccessShared.defaults.object(forKey: EarnedAccessShared.allowanceExpiresAtKey) != nil,
              Date().timeIntervalSince1970 >= EarnedAccessShared.defaults.double(forKey: EarnedAccessShared.allowanceExpiresAtKey) - 5
        else { return }

        restoreEarnedAccessShield(completed: true)
    }

    private func scheduleNextTruthReminderDay(after now: Date) {
        let defaults = EarnedAccessShared.defaults
        guard defaults.bool(forKey: EarnedAccessShared.truthReminderGateEnabledKey) else { return }
        let calendar = Calendar.current
        let nextDay = calendar.startOfDay(for: now.addingTimeInterval(60))
        guard let end = calendar.date(byAdding: .day, value: 1, to: nextDay) else { return }
        let startMinute = defaults.integer(forKey: EarnedAccessShared.truthReminderGateDailyStartMinuteKey)
        guard let start = calendar.date(byAdding: .minute, value: startMinute, to: nextDay), start > now else { return }
        defaults.set(startMinute, forKey: EarnedAccessShared.truthReminderGateNextMinuteKey)
        defaults.set(EarnedAccessShared.localDateKey(start), forKey: EarnedAccessShared.truthReminderGateNextDateKey)
        defaults.removeObject(forKey: EarnedAccessShared.truthReminderGateNextEntryIDKey)
        defaults.set(end.timeIntervalSince1970, forKey: EarnedAccessShared.truthReminderGateNextExpiresAtKey)
        let components: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute, .second]
        try? DeviceActivityCenter().startMonitoring(
            EarnedAccessShared.truthReminderActivityName,
            during: DeviceActivitySchedule(
                intervalStart: calendar.dateComponents(components, from: start),
                intervalEnd: calendar.dateComponents(components, from: end),
                repeats: false
            )
        )
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard activity == EarnedAccessShared.activityName,
              EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.protectionKey)
        else { return }

        if event == EarnedAccessShared.eventName {
            guard EarnedAccessShared.defaults.object(forKey: EarnedAccessShared.allowanceExpiresAtKey) == nil else { return }
            restoreEarnedAccessShield(completed: true)
            return
        }

        guard let checkpoint = EarnedAccessShared.usageCheckpoint(from: event),
              checkpoint.redemptionID == EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.allowanceRedemptionIDKey)
        else { return }
        let totalMinutes = EarnedAccessShared.defaults.integer(forKey: EarnedAccessShared.allowanceMinutesKey)
        guard totalMinutes > 0 else { return }
        if checkpoint.minute >= totalMinutes {
            notifyUsage(remaining: 0, used: totalMinutes, redemptionID: checkpoint.redemptionID)
            restoreEarnedAccessShield(completed: true)
            return
        }

        let nextRemaining = max(0, totalMinutes - checkpoint.minute)
        let currentRemaining = EarnedAccessShared.defaults.object(forKey: EarnedAccessShared.allowanceRemainingMinutesKey) == nil
            ? totalMinutes
            : EarnedAccessShared.defaults.integer(forKey: EarnedAccessShared.allowanceRemainingMinutesKey)
        EarnedAccessShared.defaults.set(
            min(currentRemaining, nextRemaining),
            forKey: EarnedAccessShared.allowanceRemainingMinutesKey
        )
        if checkpoint.minute.isMultiple(of: 5) {
            notifyUsage(remaining: nextRemaining, used: checkpoint.minute, redemptionID: checkpoint.redemptionID)
        }
    }

    private func notifyUsage(remaining: Int, used: Int, redemptionID: String) {
        let content = UNMutableNotificationContent()
        if remaining > 0 {
            content.title = "About \(remaining) earned minutes remain"
            content.body = "This is your shared balance across all selected earned apps. Only foreground use counts, and the estimate updates every five minutes."
        } else {
            content.title = "Earned app balance used"
            content.body = "Your selected earned apps are locked again. Complete more routines or keep walking to earn additional time."
        }
        content.sound = .default
        content.threadIdentifier = "earned-access-usage"
        let safeID = String(redemptionID.suffix(20))
        let request = UNNotificationRequest(
            identifier: "dailyRoutine.earnedAccess.usage.\(safeID).\(used)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func restoreEarnedAccessShield(completed: Bool) {
        let selection = EarnedAccessShared.loadSelection()
        EarnedAccessShared.applyShield(selection: selection, to: store)
        EarnedAccessShared.clearAllowance(completed: completed)
    }
}
