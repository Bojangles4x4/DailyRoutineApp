import Foundation
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    @Published private(set) var context: WatchRoutineContext?
    @Published private(set) var isReachable = false
    @Published private(set) var deliveryStatus: String?

    override init() {
        super.init()
#if DEBUG
        if let testContext = Self.uiTestContext() {
            context = testContext
            isReachable = true
            return
        }
#endif
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

#if DEBUG
    private static func uiTestContext() -> WatchRoutineContext? {
        let arguments = ProcessInfo.processInfo.arguments
        let truthComplete: Bool
        if arguments.contains("UI_TESTING_TRUTH_COMPLETE") {
            truthComplete = true
        } else if arguments.contains("UI_TESTING_TRUTH_REQUIRED") {
            truthComplete = false
        } else {
            return nil
        }

        return WatchRoutineContext(
            dateKey: "2026-08-21",
            completed: 4,
            total: 9,
            nextItemName: truthComplete ? "Morning walk" : "Complete Truth Before Tasks on iPhone",
            canCompleteNext: truthComplete,
            truthBeforeTasksComplete: truthComplete,
            lastActionMessage: nil
        )
    }
#endif

    func send(_ event: WatchEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        let payload: [String: Any] = ["watchEvent": data]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(payload)
                Task { @MainActor in
                    self.deliveryStatus = "Queued for iPhone"
                }
            }
            deliveryStatus = "Sent to iPhone"
        } else {
            WCSession.default.transferUserInfo(payload)
            deliveryStatus = "Queued for iPhone"
        }
    }

    private func receive(_ applicationContext: [String: Any]) {
        guard
            let data = applicationContext["routineContext"] as? Data,
            let nextContext = try? JSONDecoder().decode(WatchRoutineContext.self, from: data)
        else { return }

        context = nextContext
        WidgetSnapshotStore.save(context: nextContext)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
    }
}

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isReachable = session.isReachable
            receive(session.receivedApplicationContext)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            receive(applicationContext)
        }
    }
}
