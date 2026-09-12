import SwiftUI

@main
struct DailyRoutineAppleApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WebAppView(model: model)
                .ignoresSafeArea(.container, edges: .bottom)
                .task { await model.reminders.refreshForNewDay() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.earnedAccess.refresh()
                        Task { await model.reminders.refreshForNewDay() }
                    }
                }
        }
    }
}
