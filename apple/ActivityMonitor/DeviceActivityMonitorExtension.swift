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
        let minute = EarnedAccessShared.defaults.integer(forKey: EarnedAccessShared.truthReminderGateNextMinuteKey)
        let scheduledExpiry = EarnedAccessShared.defaults.double(forKey: EarnedAccessShared.truthReminderGateNextExpiresAtKey)
        EarnedAccessShared.defaults.set(true, forKey: EarnedAccessShared.truthReminderGateActiveKey)
        EarnedAccessShared.defaults.set(minute, forKey: EarnedAccessShared.truthReminderGateMinuteKey)
        EarnedAccessShared.defaults.set(now.timeIntervalSince1970, forKey: EarnedAccessShared.truthReminderGateActivatedAtKey)
        EarnedAccessShared.defaults.set(max(scheduledExpiry, now.addingTimeInterval(15 * 60).timeIntervalSince1970), forKey: EarnedAccessShared.truthReminderGateExpiresAtKey)
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
