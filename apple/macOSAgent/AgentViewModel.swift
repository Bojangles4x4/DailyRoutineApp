import AppKit
import EventKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AgentViewModel: ObservableObject {
    enum Pane: String, CaseIterable, Identifiable {
        case inbox
        case diagnostics
        case privacy
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .inbox: "tray.full"
            case .diagnostics: "waveform.path.ecg"
            case .privacy: "hand.raised"
            }
        }
    }

    @Published private(set) var recommendations: [Recommendation] = []
    @Published private(set) var diagnostics: [SourceDiagnostic] = []
    @Published private(set) var jobs: [JobRun] = []
    @Published private(set) var isWorking = false
    @Published var banner: String?
    @Published private(set) var launchAtLoginEnabled = false
    @Published var privateSyncEmail = ""
    @Published var privateSyncPassword = ""
    @Published private(set) var privateSyncConnected = false
    @Published private(set) var privateSyncStatus = "Not connected. The local file bridge remains available as a fallback."
    @Published private(set) var privateSyncLastRead: Date?

    var routineFallbackConnected: Bool {
        defaults.string(forKey: Setting.routineBackupPath) != nil
    }

    let store: SQLiteEventStore
    let databaseURL: URL

    private let defaults: UserDefaults
    private let calendarCollector = CalendarCollector()
    private var backgroundScheduler: NSBackgroundActivityScheduler?
    private var activityMonitor: WorkspaceActivityMonitor?
    private let observationEngine = ObservationEngine()
    private let recommendationEngine = RecommendationEngine()
    private let privateSyncClient: PrivateSyncAgentClient
    private let privateSyncSnapshotStore: PrivateSyncSnapshotFileStore

    private enum Setting {
        static let messagesEnabled = "agent.messages.enabled"
        static let activityEnabled = "agent.activity.enabled"
        static let routineBackupPath = "agent.routine.backup.path"
    }

    static func makeDefault() -> AgentViewModel {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Daily Routine Agent", isDirectory: true)
        let url = base.appendingPathComponent("personal-systems.sqlite")
        do {
            return try AgentViewModel(store: SQLiteEventStore(databaseURL: url))
        } catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("DailyRoutineAgent", isDirectory: true)
                .appendingPathComponent("personal-systems.sqlite")
            let model = try! AgentViewModel(store: SQLiteEventStore(databaseURL: fallback))
            model.banner = "The normal Application Support database was unavailable. This session is using a temporary local database."
            return model
        }
    }

    init(
        store: SQLiteEventStore,
        defaults: UserDefaults = .standard,
        privateSyncClient: PrivateSyncAgentClient = PrivateSyncAgentClient(),
        privateSyncSnapshotStore: PrivateSyncSnapshotFileStore = PrivateSyncSnapshotFileStore()
    ) throws {
        self.store = store
        self.databaseURL = store.databaseURL
        self.defaults = defaults
        self.privateSyncClient = privateSyncClient
        self.privateSyncSnapshotStore = privateSyncSnapshotStore
        self.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        self.privateSyncConnected = privateSyncClient.hasSavedSession
        self.privateSyncEmail = privateSyncClient.savedAccountEmail ?? ""
        if privateSyncConnected {
            self.privateSyncStatus = "Connected securely. Only a reduced routine snapshot will be downloaded."
        }
        self.activityMonitor = WorkspaceActivityMonitor { [weak self] event in
            guard let self else { return }
            do {
                _ = try self.store.insert(events: [event])
                try self.store.recordSource(.appActivity, enabled: true, permission: .connected, successfulAt: Date(), detail: "Records foreground app switches only; no window titles, URLs, keystrokes, or Screen Time data.")
            } catch {
                self.banner = error.localizedDescription
            }
        }
        if defaults.bool(forKey: Setting.activityEnabled) { activityMonitor?.start() }
        try seedSourceRows()
        refresh()
    }

    func start() async {
        backgroundScheduler?.invalidate()
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.bojangles4x4.DailyRoutine.agent.jobs")
        scheduler.interval = 15 * 60
        scheduler.tolerance = 5 * 60
        scheduler.repeats = true
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.runDueJobs()
                completion(.finished)
            }
        }
        backgroundScheduler = scheduler
        await runDueJobs()
    }

    func refresh() {
        do {
            recommendations = try store.fetchRecommendations()
            diagnostics = try store.sourceDiagnostics()
            jobs = try store.fetchJobs()
        } catch {
            banner = error.localizedDescription
        }
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func runDueJobs() async {
        guard !isWorking else { return }
        do {
            let now = Date()
            if isDue(last: try store.latestJob(named: "collection")?.finishedAt, interval: 3 * 60 * 60, now: now) {
                await runCollection()
            }
            let recommendationDue = isDue(last: try store.latestJob(named: "recommendation")?.finishedAt, interval: 72 * 60 * 60, now: now)
            let observationDue = isDue(last: try store.latestJob(named: "observation")?.finishedAt, interval: 3 * 60 * 60, now: now)
            if recommendationDue {
                await runAnalysis(generateRecommendations: true)
            } else if observationDue {
                await runAnalysis(generateRecommendations: false)
            }
        } catch {
            banner = error.localizedDescription
        }
        refresh()
    }

    func runNow() async {
        await runCollection()
        await runAnalysis(generateRecommendations: true)
        banner = "Local collection and analysis finished."
        refresh()
    }

    func loadTestData() async {
        isWorking = true
        defer { isWorking = false; refresh() }
        do {
            let inserted = try store.insert(events: TestDataFactory.events())
            try store.recordSource(.testData, enabled: true, permission: .connected, successfulAt: Date(), detail: "Synthetic local data for exercising the pipeline without granting permissions.")
            await runAnalysis(generateRecommendations: true)
            banner = "Test mode added \(inserted) synthetic events and ran the recommendation pipeline."
        } catch {
            banner = error.localizedDescription
        }
    }

    func clearTestData() {
        do {
            try store.clearSyntheticData()
            try store.recordSource(.testData, enabled: false, permission: .notRequested, successfulAt: nil, detail: "Synthetic events removed. Test mode is ready to run again.")
            banner = "Synthetic events and their recommendations were removed."
            refresh()
        } catch {
            banner = error.localizedDescription
        }
    }

    func setMessagesEnabled(_ enabled: Bool) async {
        defaults.set(enabled, forKey: Setting.messagesEnabled)
        do {
            try store.recordSource(
                .messages,
                enabled: enabled,
                permission: enabled ? .needsMessagesImporter : .notRequested,
                successfulAt: nil,
                detail: enabled
                    ? "Waiting for the privacy-limited snapshot from Daily Routine Messages Importer. The main Agent does not need Full Disk Access."
                    : "Disabled. No Messages importer snapshot will be read."
            )
        } catch { banner = error.localizedDescription }
        if enabled { await collect(MessagesImportCollector()) }
        refresh()
    }

    func setActivityEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Setting.activityEnabled)
        if enabled { activityMonitor?.start() } else { activityMonitor?.stop() }
        do {
            try store.recordSource(.appActivity, enabled: enabled, permission: enabled ? .connected : .notRequested, successfulAt: enabled ? Date() : nil, detail: enabled ? "Records foreground app switches only; no window titles, URLs, keystrokes, or Screen Time data." : "Disabled. No app activity will be recorded.")
        } catch { banner = error.localizedDescription }
        refresh()
    }

    func connectPrivateSyncRoutineBridge() async {
        guard !isWorking else { return }
        let email = privateSyncEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !privateSyncPassword.isEmpty else {
            banner = "Enter the same Private Sync owner email and password used by Daily Routine."
            return
        }
        isWorking = true
        defer { isWorking = false; refresh() }
        do {
            let session = try await privateSyncClient.signIn(email: email, password: privateSyncPassword)
            privateSyncPassword = ""
            privateSyncEmail = session.email
            privateSyncConnected = true
            privateSyncStatus = "Connected. Waiting for the privacy-limited iPhone snapshot."
            _ = await pullPrivateSyncRoutineSnapshot()
        } catch {
            privateSyncPassword = ""
            privateSyncConnected = privateSyncClient.hasSavedSession
            privateSyncStatus = error.localizedDescription
            banner = error.localizedDescription
        }
    }

    func refreshPrivateSyncRoutineBridge() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false; refresh() }
        _ = await pullPrivateSyncRoutineSnapshot()
    }

    func disconnectPrivateSyncRoutineBridge() async {
        guard !isWorking else { return }
        isWorking = true
        await privateSyncClient.signOut()
        privateSyncConnected = false
        privateSyncPassword = ""
        privateSyncLastRead = nil
        privateSyncStatus = "Disconnected. Existing local events remain; the file bridge is still available as a fallback."
        isWorking = false
        refresh()
    }

    func requestCalendarAccess() async {
        do {
            let granted = try await calendarCollector.requestAccess()
            try store.recordSource(.calendar, enabled: granted, permission: granted ? .connected : .denied, successfulAt: nil, detail: granted ? "Read-only event titles and times. The agent never edits calendar events." : "Calendar permission was not granted.")
            if granted { await collect(calendarCollector) }
        } catch {
            try? store.recordSource(.calendar, enabled: false, permission: .denied, successfulAt: nil, detail: error.localizedDescription)
            banner = error.localizedDescription
        }
        refresh()
    }

    func chooseRoutineSnapshot() async {
        let panel = NSOpenPanel()
        panel.title = "Choose the Daily Routine Agent snapshot"
        panel.message = "Choose daily-routine-agent-live.json. The agent reads only this file locally and never uploads it."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaults.set(url.path, forKey: Setting.routineBackupPath)
        _ = await collectRoutineSnapshot(at: url)
        refresh()
    }

    func refreshRoutineSnapshot() async {
        guard let path = defaults.string(forKey: Setting.routineBackupPath) else {
            banner = "Choose the Daily Routine Agent snapshot file first."
            return
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            banner = "The connected snapshot file could not be found. Choose it again in Diagnostics."
            return
        }
        _ = await collectRoutineSnapshot(at: url)
        refresh()
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func openMessagesImporter() {
        let bundleIdentifier = "com.bojangles4x4.DailyRoutine.messages-importer"
        let siblingURL = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Daily Routine Messages Importer.app", isDirectory: true)
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            ?? (FileManager.default.fileExists(atPath: siblingURL.path) ? siblingURL : nil)
        guard let appURL else {
            banner = "Build or install Daily Routine Messages Importer beside the Agent first. Full Disk Access should be granted only to that helper."
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
            if let error {
                Task { @MainActor in self?.banner = "The Messages importer could not be opened: \(error.localizedDescription)" }
            }
        }
    }

    func revealDatabase() {
        NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            banner = "Launch at login could not be changed: \(error.localizedDescription)"
        }
    }

    func perform(_ action: RecommendationAction, on recommendation: Recommendation) {
        let status: RecommendationStatus
        let note: String
        switch action {
        case .ignore:
            status = .ignored
            note = "Ignored locally. No source data was changed."
        case .notUseful:
            status = .notUseful
            note = "Marked not useful. This feedback remains local."
        case .watchLonger:
            status = .watching
            note = "The pattern will remain available for future observation passes."
        case .addToRoutine, .changeReminder, .createProject, .createAutomation:
            status = .staged
            note = "Staged only. This MVP does not make the external change; a future approval flow will apply it."
        }
        do {
            try store.updateRecommendation(id: recommendation.id, status: status, action: action, note: note)
            banner = note
            refresh()
        } catch {
            banner = error.localizedDescription
        }
    }

    private func runCollection() async {
        guard !isWorking else { return }
        isWorking = true
        let started = Date()
        var details: [String] = []
        if defaults.bool(forKey: Setting.messagesEnabled) {
            details.append(await collect(MessagesImportCollector()))
        }
        if calendarCollector.authorizationStatus == .fullAccess {
            details.append(await collect(calendarCollector))
        }
        var collectedRoutineFromCloud = false
        if privateSyncConnected {
            collectedRoutineFromCloud = await pullPrivateSyncRoutineSnapshot()
            details.append(collectedRoutineFromCloud
                ? "Daily Routine: refreshed from the owner-only Private Sync Agent snapshot."
                : "Daily Routine: Private Sync snapshot was unavailable; checking the local fallback.")
        }
        if !collectedRoutineFromCloud,
           let path = defaults.string(forKey: Setting.routineBackupPath),
           FileManager.default.fileExists(atPath: path) {
            details.append((await collectRoutineSnapshot(at: URL(fileURLWithPath: path))).detail)
        }
        if defaults.bool(forKey: Setting.activityEnabled) {
            try? store.recordSource(.appActivity, enabled: true, permission: .connected, successfulAt: Date(), detail: "Foreground app switches are being recorded prospectively.")
        }
        let finished = Date()
        try? store.record(job: JobRun(id: UUID().uuidString, job: "collection", startedAt: started, finishedAt: finished, succeeded: true, detail: details.isEmpty ? "No permissioned pull sources are connected yet." : details.joined(separator: " ")))
        isWorking = false
        refresh()
    }

    @discardableResult
    private func collect(_ collector: some EventCollecting) async -> String {
        do {
            let events = try await collector.collect(since: Date().addingTimeInterval(-14 * 86_400))
            let inserted = try store.insert(events: events)
            let detail = "Read \(events.count) events; \(inserted) were new."
            try store.recordSource(collector.source, enabled: true, permission: .connected, successfulAt: Date(), detail: detail)
            return "\(collector.source.title): \(detail)"
        } catch {
            let permission: PermissionState = collector.source == .messages ? .needsMessagesImporter : .denied
            try? store.recordSource(collector.source, enabled: true, permission: permission, successfulAt: nil, detail: error.localizedDescription)
            return "\(collector.source.title): \(error.localizedDescription)"
        }
    }

    private func collectRoutineSnapshot(at url: URL) async -> (detail: String, succeeded: Bool) {
        do {
            let events = try await DailyRoutineBackupCollector(fileURL: url).collect(since: Date().addingTimeInterval(-14 * 86_400))
            let inserted = try store.insert(events: events)
            let detail = "Read \(events.count) events from \(url.lastPathComponent); \(inserted) were new. This file is reread automatically during collection."
            try store.recordSource(.dailyRoutine, enabled: true, permission: .connected, successfulAt: Date(), detail: detail)
            return ("Daily Routine: \(detail)", true)
        } catch {
            try? store.recordSource(.dailyRoutine, enabled: true, permission: .denied, successfulAt: nil, detail: error.localizedDescription)
            banner = error.localizedDescription
            return ("Daily Routine: \(error.localizedDescription)", false)
        }
    }

    @discardableResult
    private func pullPrivateSyncRoutineSnapshot() async -> Bool {
        do {
            let fetched = try await privateSyncClient.fetchAgentSnapshot()
            try privateSyncSnapshotStore.write(fetched.payload)
            let result = await collectRoutineSnapshot(at: privateSyncSnapshotStore.fileURL)
            guard result.succeeded else {
                privateSyncStatus = "The iPhone snapshot downloaded but could not be imported."
                return false
            }
            privateSyncConnected = true
            privateSyncEmail = privateSyncClient.savedAccountEmail ?? privateSyncEmail
            privateSyncLastRead = Date()
            let published = fetched.updatedAt.map {
                " · iPhone published \($0.formatted(date: .abbreviated, time: .shortened))"
            } ?? ""
            privateSyncStatus = "Connected to the owner-only Agent snapshot · revision \(fetched.revision)\(published). Raw notes, memories, Health values, medication details, and text responses are excluded."
            return true
        } catch {
            privateSyncConnected = privateSyncClient.hasSavedSession
            privateSyncStatus = error.localizedDescription
            return false
        }
    }

    private func runAnalysis(generateRecommendations: Bool) async {
        let started = Date()
        do {
            let events = try store.fetchEvents(since: Date().addingTimeInterval(-14 * 86_400))
            let observations = observationEngine.analyze(events: events)
            try store.save(observations: observations)
            let finished = Date()
            try store.record(job: JobRun(id: UUID().uuidString, job: "observation", startedAt: started, finishedAt: finished, succeeded: true, detail: "Created or refreshed \(observations.count) local observations from \(events.count) events."))
            if generateRecommendations {
                let recommendations = recommendationEngine.generate(from: observations)
                try store.save(recommendations: recommendations)
                try store.record(job: JobRun(id: UUID().uuidString, job: "recommendation", startedAt: started, finishedAt: Date(), succeeded: true, detail: "Generated \(recommendations.count) top recommendations. Raw events stayed local."))
            }
        } catch {
            try? store.record(job: JobRun(id: UUID().uuidString, job: generateRecommendations ? "recommendation" : "observation", startedAt: started, finishedAt: Date(), succeeded: false, detail: error.localizedDescription))
            banner = error.localizedDescription
        }
        refresh()
    }

    private func seedSourceRows() throws {
        let existing = try store.sourceDiagnostics()
        for diagnostic in existing where diagnostic.detail == "Not configured." {
            let enabled: Bool
            let detail: String
            switch diagnostic.source {
            case .messages:
                enabled = defaults.bool(forKey: Setting.messagesEnabled)
                detail = enabled
                    ? "Ready to read the separate Messages importer snapshot. The main Agent does not need Full Disk Access."
                    : "Disabled until you explicitly connect the separate Messages importer."
            case .appActivity:
                enabled = defaults.bool(forKey: Setting.activityEnabled)
                detail = enabled ? "Foreground app switches are being recorded." : "Disabled until you explicitly enable it."
            case .calendar:
                enabled = calendarCollector.authorizationStatus == .fullAccess
                detail = enabled ? "Calendar access is connected." : "Disabled until you explicitly connect it."
            case .dailyRoutine:
                enabled = privateSyncConnected || routineFallbackConnected
                if privateSyncConnected {
                    detail = "The owner-only iPhone Private Sync bridge is connected; a local snapshot file can remain as fallback."
                } else if routineFallbackConnected {
                    detail = "A local fallback snapshot file is connected and will be reread automatically."
                } else {
                    detail = "Connect the iPhone Private Sync bridge or choose a local fallback snapshot."
                }
            case .testData:
                enabled = false
                detail = "Optional synthetic data for exercising the pipeline."
            }
            try store.recordSource(diagnostic.source, enabled: enabled, permission: enabled ? .connected : .notRequested, successfulAt: nil, detail: detail)
        }
    }

    private func isDue(last: Date?, interval: TimeInterval, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }
}
