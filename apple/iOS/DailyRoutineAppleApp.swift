import SwiftUI

@main
struct DailyRoutineAppleApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            DailyRoutineRootView(model: model)
        }
    }
}

private struct DailyRoutineRootView: View {
    let model: AppModel
    @ObservedObject private var reminders: TruthReminderStore
    @Environment(\.scenePhase) private var scenePhase

    init(model: AppModel) {
        self.model = model
        reminders = model.reminders
    }

    var body: some View {
        WebAppView(model: model)
            .ignoresSafeArea(.container, edges: .bottom)
            .task {
                await reminders.refreshForNewDay()
                reminders.restorePendingGatePresentation()
            }
            .fullScreenCover(item: $reminders.pendingPresentation) { entry in
                TruthReminderReviewView(store: reminders, entry: entry, blocking: reminders.gateIsActive)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.earnedAccess.refresh()
                    Task {
                        await reminders.refreshForNewDay()
                        reminders.restorePendingGatePresentation()
                    }
                }
            }
    }
}
