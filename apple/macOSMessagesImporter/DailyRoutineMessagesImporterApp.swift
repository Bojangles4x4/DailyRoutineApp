import AppKit
import SwiftUI

@main
struct DailyRoutineMessagesImporterApp: App {
    @StateObject private var model = MessagesImporterViewModel()

    var body: some Scene {
        WindowGroup(id: "messages-importer-main") {
            MessagesImporterView()
                .environmentObject(model)
                .task {
                    await Task.yield()
                    await model.start()
                }
        }
        .defaultSize(width: 820, height: 640)

        MenuBarExtra("Daily Routine Messages Importer", systemImage: "message.badge.filled.fill") {
            Button("Open Messages Importer") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            Divider()
            Button(model.isWorking ? "Import running…" : "Import Messages now") {
                Task { await model.runImport() }
            }
            .disabled(model.isWorking)
            Divider()
            Button("Quit Messages Importer") { NSApplication.shared.terminate(nil) }
        }
    }
}
