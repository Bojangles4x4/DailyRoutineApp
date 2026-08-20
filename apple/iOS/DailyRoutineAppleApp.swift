import SwiftUI

@main
struct DailyRoutineAppleApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            WebAppView(model: model)
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}
