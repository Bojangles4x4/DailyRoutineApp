import AppKit
import Foundation
import ServiceManagement

@MainActor
final class MessagesImporterViewModel: ObservableObject {
    @Published private(set) var status = "Waiting for the first local import."
    @Published private(set) var lastSuccessfulImport: Date?
    @Published private(set) var eventCount = 0
    @Published private(set) var isWorking = false
    @Published private(set) var launchAtLoginEnabled = false

    private let importer: MessagesReadOnlyImporter
    private var scheduler: NSBackgroundActivityScheduler?

    init(importer: MessagesReadOnlyImporter = MessagesReadOnlyImporter()) {
        self.importer = importer
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func start() async {
        scheduler?.invalidate()
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.bojangles4x4.DailyRoutine.messages-importer.refresh")
        scheduler.interval = 3 * 60 * 60
        scheduler.tolerance = 30 * 60
        scheduler.repeats = true
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.runImport()
                completion(.finished)
            }
        }
        self.scheduler = scheduler
        await runImport()
    }

    func runImport() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let envelope = try importer.importSnapshot()
            eventCount = envelope.events.count
            lastSuccessfulImport = envelope.exportedAt
            status = "Updated one owner-only snapshot. The Messages database was opened read-only."
        } catch {
            status = error.localizedDescription
        }
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealSnapshot() {
        let url = MessagesImportLocation.snapshotURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([MessagesImportLocation.directoryURL])
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            status = "Launch at login could not be changed: \(error.localizedDescription)"
        }
    }
}
