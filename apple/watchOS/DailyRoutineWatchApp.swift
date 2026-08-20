import SwiftUI

@main
struct DailyRoutineWatchApp: App {
    @StateObject private var session = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView(session: session)
        }
    }
}
