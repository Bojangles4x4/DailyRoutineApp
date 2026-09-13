import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UserNotifications

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: EarnedAccessShared.storeName)
    private let foundationStore = ManagedSettingsStore(named: EarnedAccessShared.foundationStoreName)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == EarnedAccessShared.foundationActivityName,
              EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.morningGateEnabledKey),
              EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.morningFoundationCompleteDateKey) != EarnedAccessShared.localDateKey()
        else { return }

        EarnedAccessShared.applyFoundationShield(
            exceptions: EarnedAccessShared.loadEssentialSelection(),
            to: foundationStore
        )
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
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
        let label = EarnedAccessShared.defaults.string(forKey: EarnedAccessShared.allowanceLabelKey) ?? "Earned apps"
        if remaining > 0 {
            content.title = "\(remaining) earned minutes left"
            content.body = "\(label) has used \(used) minute\(used == 1 ? "" : "s"). Only foreground use counts."
        } else {
            content.title = "Earned app time used"
            content.body = "\(label) is locked again. Complete more routines or keep walking to earn additional time."
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
