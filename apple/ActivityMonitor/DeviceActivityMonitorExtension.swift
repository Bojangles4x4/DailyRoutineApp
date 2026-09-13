import DeviceActivity
import FamilyControls
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
        if activity == EarnedAccessShared.activityName,
           EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.protectionKey) {
            restoreEarnedAccessShield()
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard activity == EarnedAccessShared.activityName,
              EarnedAccessShared.defaults.bool(forKey: EarnedAccessShared.protectionKey)
        else { return }

        if event == EarnedAccessShared.eventName {
            restoreEarnedAccessShield()
            return
        }

        guard let usedMinutes = EarnedAccessShared.usageMinute(from: event) else { return }
        let totalMinutes = EarnedAccessShared.defaults.integer(forKey: EarnedAccessShared.allowanceMinutesKey)
        guard totalMinutes > 0 else { return }
        if usedMinutes >= totalMinutes {
            restoreEarnedAccessShield()
            return
        }

        let nextRemaining = max(0, totalMinutes - usedMinutes)
        let currentRemaining = EarnedAccessShared.defaults.object(forKey: EarnedAccessShared.allowanceRemainingMinutesKey) == nil
            ? totalMinutes
            : EarnedAccessShared.defaults.integer(forKey: EarnedAccessShared.allowanceRemainingMinutesKey)
        EarnedAccessShared.defaults.set(
            min(currentRemaining, nextRemaining),
            forKey: EarnedAccessShared.allowanceRemainingMinutesKey
        )
    }

    private func restoreEarnedAccessShield() {
        let selection = EarnedAccessShared.loadSelection()
        EarnedAccessShared.applyShield(selection: selection, to: store)
        EarnedAccessShared.clearAllowance(completed: true)
    }
}
