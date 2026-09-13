import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

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
    }

    private func restoreEarnedAccessShield(completed: Bool) {
        let selection = EarnedAccessShared.loadSelection()
        EarnedAccessShared.applyShield(selection: selection, to: store)
        EarnedAccessShared.clearAllowance(completed: completed)
    }
}
