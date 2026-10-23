import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var usesDarkAppearance = UserDefaults.standard.bool(forKey: "routine.native.darkAppearance")

    func updateAppearance(theme: String) {
        guard ["calm", "sunrise", "dusk", "minimal", "midnight"].contains(theme) else { return }
        let dark = theme == "midnight"
        guard usesDarkAppearance != dark else { return }
        usesDarkAppearance = dark
        UserDefaults.standard.set(dark, forKey: "routine.native.darkAppearance")
    }

    let health = HealthKitService()
    let watch = PhoneWatchSessionManager()
    let reminders = TruthReminderStore()
    let earnedAccess = EarnedAccessControlStore()
    let routineSharedState = RoutineSharedStateStore()

    init() {
        health.restoreStepRewardAutomation()
        health.restoreSleepSummaryAutomation()
    }

    var earnedAccessBridgeStatus: [String: String] {
        var value = earnedAccess.bridgeStatus
        reminders.bridgeStatus.forEach { value[$0.key] = $0.value }
        let reason = EarnedAccessProtectionSummary.reason(
            isAuthorized: earnedAccess.isAuthorized,
            essentialSelectionNeedsRepair: earnedAccess.essentialSelectionNeedsRepair,
            morningGateEnabled: earnedAccess.morningGateEnabled,
            morningFoundationCompleteToday: earnedAccess.morningFoundationCompleteToday,
            truthReminderGateActive: earnedAccess.truthReminderGateActive,
            truthReminderSafetyUnlockActive: earnedAccess.truthReminderSafetyUnlockUntil != nil,
            protectionEnabled: earnedAccess.protectionEnabled,
            allowanceActive: earnedAccess.allowanceActive,
            isShielding: earnedAccess.isShielding,
            dailyResetScheduled: earnedAccess.dailyResetScheduled,
            morningGateScheduled: earnedAccess.morningGateScheduled
        )
        value["protectionReason"] = reason.rawValue
        value["protectionTitle"] = EarnedAccessProtectionSummary.title(
            isAuthorized: earnedAccess.isAuthorized,
            essentialSelectionNeedsRepair: earnedAccess.essentialSelectionNeedsRepair,
            morningGateEnabled: earnedAccess.morningGateEnabled,
            morningFoundationCompleteToday: earnedAccess.morningFoundationCompleteToday,
            truthReminderGateActive: earnedAccess.truthReminderGateActive,
            truthReminderSafetyUnlockActive: earnedAccess.truthReminderSafetyUnlockUntil != nil,
            protectionEnabled: earnedAccess.protectionEnabled,
            allowanceActive: earnedAccess.allowanceActive,
            allowanceRemainingMinutes: earnedAccess.allowanceRemainingMinutes,
            isShielding: earnedAccess.isShielding,
            dailyResetScheduled: earnedAccess.dailyResetScheduled,
            morningGateScheduled: earnedAccess.morningGateScheduled
        )
        let waiting = reminders.waitingReminderCount
        switch reason {
        case .permissionNeeded:
            value["protectionDetail"] = "Allow Screen Time, then choose the apps to manage."
            value["protectionAction"] = "Finish Screen Time setup"
        case .essentialSelectionRepair:
            value["protectionDetail"] = "All-app gates are released for safety until essential apps are chosen again."
            value["protectionAction"] = "Choose essential apps"
        case .morningGate:
            value["protectionDetail"] = waiting > 0
                ? "Complete Truth Before Tasks first. \(waiting) Truth Reminder\(waiting == 1 ? " is" : "s are") waiting afterward."
                : "Complete Truth Before Tasks to restore access. Earned minutes remain preserved."
            value["protectionAction"] = "Begin Truth Before Tasks"
        case .truthReminderGate:
            value["protectionDetail"] = waiting > 0
                ? "Review all \(waiting) waiting reminder\(waiting == 1 ? "" : "s") to restore nonessential apps. Earned minutes remain preserved."
                : "Review the waiting reminder to restore nonessential apps. Earned minutes remain preserved."
            value["protectionAction"] = "Review reminders"
        case .safetyUnlock:
            let until = earnedAccess.truthReminderSafetyUnlockUntil?.formatted(date: .omitted, time: .shortened) ?? "soon"
            value["protectionDetail"] = "Truth access is temporarily open until \(until). Earned apps still follow their available balance."
            value["protectionAction"] = "Review waiting reminders"
        case .scheduleRepair:
            value["protectionDetail"] = "Open the controls to restore the daily reset and protection schedules."
            value["protectionAction"] = "Repair schedules"
        case .protectionOff:
            value["protectionDetail"] = "Turn protection on before relying on the earned time bank."
            value["protectionAction"] = "Turn on protection"
        case .allowanceOpen:
            value["protectionDetail"] = "Only foreground use in selected apps reduces the shared balance."
            value["protectionAction"] = "Use earned apps"
        case .earnedAppsLocked:
            value["protectionDetail"] = "Complete a selected routine or keep walking to add time."
            value["protectionAction"] = "Earn time"
        case .ready:
            value["protectionDetail"] = "Selected apps will open automatically when minutes are earned."
            value["protectionAction"] = "Earn time"
        }
        return value
    }
}
