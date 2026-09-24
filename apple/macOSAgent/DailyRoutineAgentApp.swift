import SwiftUI

@main
struct DailyRoutineAgentApp: App {
    @StateObject private var model = AgentViewModel.makeDefault()

    var body: some Scene {
        WindowGroup(id: "agent-main") {
            AgentRootView()
                .environmentObject(model)
                .task {
                    await Task.yield()
                    await model.start()
                }
        }
        .defaultSize(width: 980, height: 720)

        MenuBarExtra("Daily Routine Agent", systemImage: "sparkles") {
            AgentMenuView()
                .environmentObject(model)
        }
    }
}

private struct AgentMenuView: View {
    @EnvironmentObject private var model: AgentViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Daily Routine Agent") {
            openWindow(id: "agent-main")
        }
        Divider()
        Button(model.isWorking ? "Review running…" : "Run local review now") {
            Task { await model.runNow() }
        }
        .disabled(model.isWorking)
        Divider()
        Button("Quit Daily Routine Agent") { NSApplication.shared.terminate(nil) }
    }
}
