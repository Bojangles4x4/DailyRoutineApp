import Foundation

@MainActor
final class AppModel: ObservableObject {
    let health = HealthKitService()
    let watch = PhoneWatchSessionManager()
    let reminders = TruthReminderStore()
    let earnedAccess = EarnedAccessControlStore()
    let routineSharedState = RoutineSharedStateStore()

    init() {
        health.restoreStepRewardAutomation()
    }
}
