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
                await reminders.appDidBecomeActive()
            }
            .fullScreenCover(item: $reminders.pendingPresentation) { presentation in
                TruthReminderReviewView(
                    store: reminders,
                    entry: presentation.entry,
                    blocking: presentation.blocking
                )
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.earnedAccess.refresh()
                    Task {
                        await reminders.appDidBecomeActive()
                    }
                } else {
                    reminders.appDidResignActive()
                }
            }
    }
}
