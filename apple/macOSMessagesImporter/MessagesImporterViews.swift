import SwiftUI

struct MessagesImporterView: View {
    @EnvironmentObject private var model: MessagesImporterViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Messages importer").font(.largeTitle.bold())
                    Text("A narrow, local bridge for Apple Messages")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Current status") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.status)
                        if let date = model.lastSuccessfulImport {
                            Text("Last import: \(date.formatted(date: .abbreviated, time: .shortened)) · \(model.eventCount) events")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Button(model.isWorking ? "Importing…" : "Import now") {
                                Task { await model.runImport() }
                            }
                            .disabled(model.isWorking)
                            Button("Full Disk Access…") { model.openFullDiskAccessSettings() }
                            Button("Reveal snapshot") { model.revealSnapshot() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox("Privacy boundary") {
                    VStack(alignment: .leading, spacing: 10) {
                        boundary("Separate identity", "Only Daily Routine Messages Importer should receive Full Disk Access. The main Agent remains unprivileged.")
                        boundary("Read-only source", "The helper opens only ~/Library/Messages/chat.db with SQLite read-only mode.")
                        boundary("One narrow output", "It atomically replaces one owner-only JSON snapshot containing up to 14 days of text-message events.")
                        boundary("No network layer", "This target contains no network client and does not send, edit, or delete Messages.")
                        boundary("Limited content", "Attachments are excluded. Contact labels are capped at 200 characters and message text at 500 characters per event.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                Toggle("Launch this importer at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(28)
        }
        .frame(minWidth: 760, minHeight: 600)
    }

    private func boundary(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary)
        }
    }
}
