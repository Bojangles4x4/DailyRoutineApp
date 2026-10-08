import Foundation
import SwiftUI
import UIKit
import WebKit
import WidgetKit

enum NativeSafetySnapshotStoreError: LocalizedError {
    case unavailable
    case invalidSnapshot
    case snapshotTooLarge
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Protected recovery storage is unavailable."
        case .invalidSnapshot:
            "The recovery copy was not valid."
        case .snapshotTooLarge:
            "The recovery copy was too large to save safely."
        case .verificationFailed:
            "The recovery copy could not be verified after saving."
        }
    }
}

final class NativeSafetySnapshotStore: @unchecked Sendable {
    private let directoryURL: URL?
    private let fileManager: FileManager
    private let processLock = NSLock()
    private let maximumSnapshotBytes = 25 * 1_024 * 1_024
    private let maximumSnapshots = 2

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("DailyRoutineSafetySnapshots", isDirectory: true)
    }

    @discardableResult
    func save(snapshotData: Data, expectedSnapshotID: String) throws -> Int {
        processLock.lock()
        defer { processLock.unlock() }
        guard let directoryURL else { throw NativeSafetySnapshotStoreError.unavailable }
        guard !snapshotData.isEmpty else { throw NativeSafetySnapshotStoreError.invalidSnapshot }
        guard snapshotData.count <= maximumSnapshotBytes else { throw NativeSafetySnapshotStoreError.snapshotTooLarge }
        guard Self.isSafeIdentifier(expectedSnapshotID) else { throw NativeSafetySnapshotStoreError.invalidSnapshot }
        _ = try validate(snapshotData, expectedSnapshotID: expectedSnapshotID)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let snapshotURL = fileURL(snapshotID: expectedSnapshotID, directoryURL: directoryURL)
        try snapshotData.write(to: snapshotURL, options: [.atomic, .completeFileProtection])
        let verified = try Data(contentsOf: snapshotURL)
        guard verified == snapshotData else { throw NativeSafetySnapshotStoreError.verificationFailed }
        _ = try validate(verified, expectedSnapshotID: expectedSnapshotID)
        try pruneVerifiedSnapshots(in: directoryURL)
        return verified.count
    }

    func load(snapshotID: String) throws -> Data? {
        processLock.lock()
        defer { processLock.unlock() }
        guard let directoryURL else { throw NativeSafetySnapshotStoreError.unavailable }
        guard Self.isSafeIdentifier(snapshotID) else { throw NativeSafetySnapshotStoreError.invalidSnapshot }
        let snapshotURL = fileURL(snapshotID: snapshotID, directoryURL: directoryURL)
        guard fileManager.fileExists(atPath: snapshotURL.path) else { return nil }
        let data = try Data(contentsOf: snapshotURL)
        _ = try validate(data, expectedSnapshotID: snapshotID)
        return data
    }

    func metadata() throws -> [NativeSafetySnapshotMetadata] {
        processLock.lock()
        defer { processLock.unlock() }
        return try metadataUnlocked()
    }

    private func metadataUnlocked() throws -> [NativeSafetySnapshotMetadata] {
        guard let directoryURL else { throw NativeSafetySnapshotStoreError.unavailable }
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? validate(data, expectedSnapshotID: nil)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func fileURL(snapshotID: String, directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent("private-sync-safety-\(snapshotID).json", isDirectory: false)
    }

    private func validate(_ data: Data, expectedSnapshotID: String?) throws -> NativeSafetySnapshotMetadata {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            (object["schemaVersion"] as? NSNumber)?.intValue == 1,
            let id = object["id"] as? String,
            Self.isSafeIdentifier(id),
            expectedSnapshotID == nil || id == expectedSnapshotID,
            let createdAt = object["createdAt"] as? String,
            !createdAt.isEmpty,
            object["version"] is String,
            object["build"] is NSNumber,
            let state = object["state"] as? [String: Any],
            let items = state["items"] as? [Any],
            let days = state["days"] as? [String: Any]
        else {
            throw NativeSafetySnapshotStoreError.invalidSnapshot
        }
        return NativeSafetySnapshotMetadata(
            snapshotId: id,
            createdAt: createdAt,
            label: String((object["label"] as? String ?? "Protected recovery copy").prefix(160)),
            dayCount: days.count,
            itemCount: items.count,
            byteCount: data.count
        )
    }

    private func pruneVerifiedSnapshots(in directoryURL: URL) throws {
        let retained = try metadataUnlocked()
        guard retained.count > maximumSnapshots else { return }
        for snapshot in retained.dropFirst(maximumSnapshots) {
            try? fileManager.removeItem(at: fileURL(snapshotID: snapshot.snapshotId, directoryURL: directoryURL))
        }
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9-]{1,160}$"#, options: .regularExpression) != nil
    }
}

struct NativeSafetySnapshotMetadata: Codable, Equatable, Sendable {
    let snapshotId: String
    let createdAt: String
    let label: String
    let dayCount: Int
    let itemCount: Int
    let byteCount: Int
}

struct WebAppView: UIViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator, name: "dailyRoutine")

        let bridgeScript = WKUserScript(
            source: """
            window.DailyRoutineNative = {
              postMessage(message) {
                window.webkit.messageHandlers.dailyRoutine.postMessage(message);
              }
            };
            window.dispatchEvent(new CustomEvent('dailyRoutine:native-ready'));
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(bridgeScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.isDirectionalLockEnabled = true
        context.coordinator.webView = webView
        context.coordinator.connectWatchEvents()
        context.coordinator.connectHealthEvents()
        context.coordinator.connectLifecycleEvents()

        guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
            assertionFailure("The bundled web app is missing index.html")
            return webView
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        private let model: AppModel
        private var isWebAppReady = false
        private var pendingWatchEvents: [WatchEvent] = []
        private var processedWatchEventIDs = Set<UUID>()
        private var didBecomeActiveObserver: NSObjectProtocol?
        private var healthRefreshTask: Task<Void, Never>?
        private let safetySnapshotStore = NativeSafetySnapshotStore()
        weak var webView: WKWebView?

        init(model: AppModel) {
            self.model = model
        }

        deinit {
            if let didBecomeActiveObserver {
                NotificationCenter.default.removeObserver(didBecomeActiveObserver)
            }
            healthRefreshTask?.cancel()
        }

        func connectWatchEvents() {
            model.watch.onEvent = { [weak self] event in
                self?.receiveWatchEvent(event)
            }
        }

        func connectHealthEvents() {
            model.health.onStepRewardUpdate = { [weak self] in
                self?.scheduleHealthRefresh()
            }
        }

        private func scheduleHealthRefresh() {
            guard UIApplication.shared.applicationState == .active else { return }
            healthRefreshTask?.cancel()
            healthRefreshTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, self.isWebAppReady,
                      let summary = try? await self.model.health.fetchSummary()
                else { return }
                self.emit(name: "health.summary", value: summary)
            }
        }

        func connectLifecycleEvents() {
            guard didBecomeActiveObserver == nil else { return }
            didBecomeActiveObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isWebAppReady else { return }
                    self.model.earnedAccess.refresh()
                    self.emit(name: "earned.access.status", value: self.model.earnedAccess.bridgeStatus)
                    self.emitPendingRoutineCommands()
                    if self.model.health.isAvailable,
                       let summary = try? await self.model.health.fetchSummary() {
                        self.emit(name: "health.summary", value: summary)
                    }
                }
            }
        }

        private func receiveWatchEvent(_ event: WatchEvent) {
            guard processedWatchEventIDs.insert(event.id).inserted else { return }
            if isWebAppReady {
                emit(name: "watch.event", value: event)
            } else {
                pendingWatchEvents.append(event)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard
                let payload = message.body as? [String: Any],
                let rawAction = payload["action"] as? String,
                let action = NativeBridgeAction(rawValue: rawAction)
            else {
                emitError("The native request was not recognized.")
                return
            }

            if [.saveSafetySnapshot, .requestSafetySnapshotStatus, .loadSafetySnapshot].contains(action),
               !message.frameInfo.isMainFrame {
                emitError("The recovery request must come from the main app screen.")
                return
            }

            switch action {
            case .publishRoutineSnapshot:
                guard
                    let value = payload["value"],
                    JSONSerialization.isValidJSONObject(value),
                    let data = try? JSONSerialization.data(withJSONObject: value),
                    let snapshot = try? JSONDecoder().decode(RoutineSharedSnapshot.self, from: data)
                else {
                    emitError("The shared routine snapshot was not valid.")
                    return
                }
                do {
                    try model.routineSharedState.save(snapshot: snapshot)
                    WidgetCenter.shared.reloadTimelines(ofKind: RoutineHomeWidgetConstants.kind)
                    emit(
                        name: "routine.snapshot.saved",
                        value: RoutineSnapshotSavedEvent(
                            revision: snapshot.revision,
                            localDateKey: snapshot.localDateKey
                        )
                    )
                } catch {
                    emitError(error.localizedDescription)
                }
            case .requestRoutineCommands:
                emitPendingRoutineCommands()
            case .acknowledgeRoutineCommand:
                guard
                    let value = payload["value"] as? [String: Any],
                    let commandID = value["commandId"] as? String,
                    !commandID.isEmpty,
                    let rawStatus = value["status"] as? String,
                    let status = RoutineSharedCommandStatus(rawValue: rawStatus),
                    status != .pending
                else {
                    emitError("The shared routine command result was not valid.")
                    return
                }
                do {
                    let revision = (value["stateRevision"] as? NSNumber)?.intValue
                    let message = value["message"] as? String
                    _ = try model.routineSharedState.resolve(
                        commandID: commandID,
                        status: status,
                        stateRevision: revision,
                        message: message
                    )
                    emitPendingRoutineCommands()
                } catch {
                    emitError(error.localizedDescription)
                }
            case .requestEarnedAccessStatus:
                model.earnedAccess.refresh()
                emit(name: "earned.access.status", value: model.earnedAccess.bridgeStatus)
            case .lockEarnedAccess:
                model.earnedAccess.lockIfEnabled()
                emit(name: "earned.access.status", value: model.earnedAccess.bridgeStatus)
            case .allowEarnedAccess:
                guard
                    let value = payload["value"] as? [String: Any],
                    let minutes = value["minutes"] as? NSNumber,
                    let redemptionID = value["redemptionId"] as? String,
                    !redemptionID.isEmpty
                else {
                    emitError("The Earned Access usage allowance was not valid.")
                    return
                }
                let label = (value["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                model.earnedAccess.allowAccess(minutes: minutes.intValue, redemptionID: redemptionID, label: label)
                emit(name: "earned.access.status", value: model.earnedAccess.bridgeStatus)
            case .lockMorningFoundation, .completeMorningFoundation:
                guard
                    let value = payload["value"] as? [String: Any],
                    let dateKey = value["dateKey"] as? String,
                    !dateKey.isEmpty
                else {
                    emitError("The Morning Foundation date was not valid.")
                    return
                }
                model.earnedAccess.updateMorningFoundation(
                    dateKey: dateKey,
                    completed: action == .completeMorningFoundation
                )
                emit(name: "earned.access.status", value: model.earnedAccess.bridgeStatus)
            case .openEarnedAccessControls:
                guard let webView else { return }
                let controller = UIHostingController(
                    rootView: EarnedAccessControlView(store: model.earnedAccess) { [weak self] in
                        guard let self else { return }
                        self.model.earnedAccess.refresh()
                        self.emit(name: "earned.access.status", value: self.model.earnedAccess.bridgeStatus)
                    }
                )
                present(controller, from: webView) { }
            case .openTruthReminders:
                guard let webView else { return }
                let controller = UIHostingController(rootView: TruthReminderView(store: model.reminders))
                present(controller, from: webView) { }
            case .requestHealthAuthorization:
                Task {
                    do {
                        try await model.health.requestAuthorization()
                        emit(name: "health.authorization.completed", value: ["requested": true])
                    } catch {
                        emitError(error.localizedDescription)
                    }
                }
            case .requestHealthSummary:
                Task {
                    do {
                        let roundStartedAt = Self.roundStartedAt(from: payload)
                        emit(name: "health.summary", value: try await model.health.fetchSummary(roundStartedAt: roundStartedAt))
                    } catch {
                        emitError(error.localizedDescription)
                    }
                }
            case .configureStepRewards:
                guard let value = payload["value"] as? [String: Any] else { return }
                let enabled = (value["enabled"] as? NSNumber)?.boolValue ?? false
                let goalSteps = (value["goalSteps"] as? NSNumber)?.intValue ?? 8_000
                let maxMinutes = (value["maxMinutes"] as? NSNumber)?.intValue ?? 60
                Task { await model.health.configureStepRewards(enabled: enabled, goalSteps: goalSteps, maxMinutes: maxMinutes) }
            case .updateWatchContext:
                guard
                    let value = payload["value"],
                    JSONSerialization.isValidJSONObject(value),
                    let data = try? JSONSerialization.data(withJSONObject: value),
                    let context = try? JSONDecoder().decode(WatchRoutineContext.self, from: data)
                else {
                    emitError("The Watch context was not valid.")
                    return
                }
                let updated = model.watch.update(context: context)
                emit(name: "watch.context.updated", value: ["updated": updated, "queued": !updated])
            case .shareText:
                guard
                    let value = payload["value"] as? [String: Any],
                    let text = value["text"] as? String,
                    !text.isEmpty
                else {
                    emitError("The report was empty and could not be shared.")
                    return
                }
                presentShareSheet(title: value["title"] as? String, text: text)
            case .shareFile:
                guard
                    let value = payload["value"] as? [String: Any],
                    let filename = value["filename"] as? String,
                    !filename.isEmpty,
                    let content = value["content"] as? String
                else {
                    emitError("The exported file was not valid.")
                    return
                }
                presentShareSheet(filename: filename, content: content)
            case .saveSafetySnapshot:
                let value = payload["value"] as? [String: Any]
                let requestID = value?["requestId"] as? String ?? ""
                let snapshotID = value?["snapshotId"] as? String ?? ""
                guard
                    !requestID.isEmpty,
                    !snapshotID.isEmpty,
                    let content = value?["content"] as? String,
                    let data = content.data(using: .utf8)
                else {
                    if !requestID.isEmpty {
                        emit(
                            name: "safety.snapshot.saved",
                            value: SafetySnapshotSavedEvent(
                                requestId: requestID,
                                snapshotId: snapshotID,
                                success: false,
                                byteCount: 0,
                                message: "The safety snapshot request was not valid."
                            )
                        )
                    } else {
                        emitError("The safety snapshot request was not valid.")
                    }
                    return
                }
                Task.detached(priority: .utility) { [weak self, safetySnapshotStore] in
                    let event: SafetySnapshotSavedEvent
                    do {
                        let byteCount = try safetySnapshotStore.save(snapshotData: data, expectedSnapshotID: snapshotID)
                        event = SafetySnapshotSavedEvent(
                            requestId: requestID,
                            snapshotId: snapshotID,
                            success: true,
                            byteCount: byteCount,
                            message: nil
                        )
                    } catch {
                        event = SafetySnapshotSavedEvent(
                            requestId: requestID,
                            snapshotId: snapshotID,
                            success: false,
                            byteCount: 0,
                            message: "The protected recovery copy could not be saved and verified."
                        )
                    }
                    await MainActor.run { self?.emit(name: "safety.snapshot.saved", value: event) }
                }
            case .requestSafetySnapshotStatus:
                Task.detached(priority: .utility) { [weak self, safetySnapshotStore] in
                    let snapshots = (try? safetySnapshotStore.metadata()) ?? []
                    await MainActor.run { self?.emit(name: "safety.snapshot.status", value: snapshots) }
                }
            case .loadSafetySnapshot:
                let value = payload["value"] as? [String: Any]
                let requestID = value?["requestId"] as? String ?? ""
                let snapshotID = value?["snapshotId"] as? String ?? ""
                guard !requestID.isEmpty, !snapshotID.isEmpty else {
                    emitError("The recovery-copy request was not valid.")
                    return
                }
                Task.detached(priority: .utility) { [weak self, safetySnapshotStore] in
                    let event: SafetySnapshotLoadedEvent
                    do {
                        guard
                            let data = try safetySnapshotStore.load(snapshotID: snapshotID),
                            let content = String(data: data, encoding: .utf8)
                        else { throw NativeSafetySnapshotStoreError.invalidSnapshot }
                        event = SafetySnapshotLoadedEvent(
                            requestId: requestID,
                            snapshotId: snapshotID,
                            success: true,
                            content: content,
                            message: nil
                        )
                    } catch {
                        event = SafetySnapshotLoadedEvent(
                            requestId: requestID,
                            snapshotId: snapshotID,
                            success: false,
                            content: nil,
                            message: "The protected recovery copy could not be read and verified."
                        )
                    }
                    await MainActor.run { self?.emit(name: "safety.snapshot.loaded", value: event) }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isWebAppReady = true
            model.earnedAccess.refresh()
            emit(
                name: "native.ready",
                value: [
                    "healthAvailable": model.health.isAvailable,
                    "earnedAccessAvailable": true,
                    "earnedAccessProtectionEnabled": model.earnedAccess.protectionEnabled,
                    "earnedAccessShielding": model.earnedAccess.isShielding,
                    "watchReachable": model.watch.isReachable,
                    "watchInstalled": model.watch.isWatchAppInstalled
                ]
            )
            pendingWatchEvents.forEach { emit(name: "watch.event", value: $0) }
            pendingWatchEvents.removeAll()
            emit(name: "earned.access.status", value: model.earnedAccess.bridgeStatus)
            emitPendingRoutineCommands()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard
                navigationAction.navigationType == .linkActivated,
                let url = navigationAction.request.url,
                let scheme = url.scheme?.lowercased(),
                scheme == "http" || scheme == "https"
            else {
                decisionHandler(.allow)
                return
            }

            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            let alert = UIAlertController(title: "My Daily Rhythms", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(alert, from: webView, fallback: completionHandler)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            let alert = UIAlertController(title: "Confirm", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in completionHandler(true) })
            present(alert, from: webView) { completionHandler(false) }
        }

        private func emit<T: Encodable>(name: String, value: T) {
            guard
                let data = try? JSONEncoder.bridge.encode(value),
                let json = String(data: data, encoding: .utf8)
            else { return }

            let escapedName = name.replacingOccurrences(of: "'", with: "\\'")
            let script = "window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: '\(escapedName)', value: \(json) } }));"
            webView?.evaluateJavaScript(script)
        }

        private func emitError(_ message: String) {
            emit(name: "native.error", value: ["message": message])
        }

        private func emitPendingRoutineCommands() {
            do {
                emit(name: "routine.commands.pending", value: try model.routineSharedState.pendingCommands())
            } catch {
                emitError(error.localizedDescription)
            }
        }

        private static func roundStartedAt(from payload: [String: Any]) -> Date? {
            guard
                let value = payload["value"] as? [String: Any],
                let rawDate = value["roundStartedAt"] as? String
            else { return nil }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: rawDate) { return date }
            return ISO8601DateFormatter().date(from: rawDate)
        }

        private func present(_ controller: UIViewController, from webView: WKWebView, fallback: () -> Void) {
            guard let presenter = topViewController(from: webView.window?.rootViewController) else {
                fallback()
                return
            }
            presenter.present(controller, animated: true)
        }

        private func presentShareSheet(title: String?, text: String) {
            let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            if let title, !title.isEmpty {
                controller.setValue(title, forKey: "subject")
            }
            if let popover = controller.popoverPresentationController, let webView {
                popover.sourceView = webView
                popover.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.maxY - 1, width: 1, height: 1)
            }
            guard let presenter = topViewController(from: webView?.window?.rootViewController) else {
                emitError("The share options could not be opened.")
                return
            }
            presenter.present(controller, animated: true)
        }

        private func presentShareSheet(filename: String, content: String) {
            let safeFilename = URL(fileURLWithPath: filename).lastPathComponent
            guard !safeFilename.isEmpty else {
                emitError("The exported filename was not valid.")
                return
            }
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(safeFilename)
            do {
                try Data(content.utf8).write(to: fileURL, options: .atomic)
            } catch {
                emitError("The exported file could not be prepared.")
                return
            }

            let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            controller.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: fileURL)
            }
            if let popover = controller.popoverPresentationController, let webView {
                popover.sourceView = webView
                popover.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.maxY - 1, width: 1, height: 1)
            }
            guard let presenter = topViewController(from: webView?.window?.rootViewController) else {
                try? FileManager.default.removeItem(at: fileURL)
                emitError("The share options could not be opened.")
                return
            }
            presenter.present(controller, animated: true)
        }

        private func topViewController(from controller: UIViewController?) -> UIViewController? {
            if let presented = controller?.presentedViewController {
                return topViewController(from: presented)
            }
            if let navigation = controller as? UINavigationController {
                return topViewController(from: navigation.visibleViewController)
            }
            if let tabs = controller as? UITabBarController {
                return topViewController(from: tabs.selectedViewController)
            }
            return controller
        }
    }
}

private struct RoutineSnapshotSavedEvent: Encodable {
    let revision: Int
    let localDateKey: String
}

private struct SafetySnapshotSavedEvent: Encodable {
    let requestId: String
    let snapshotId: String
    let success: Bool
    let byteCount: Int
    let message: String?
}

private struct SafetySnapshotLoadedEvent: Encodable {
    let requestId: String
    let snapshotId: String
    let success: Bool
    let content: String?
    let message: String?
}

private extension JSONEncoder {
    static var bridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
