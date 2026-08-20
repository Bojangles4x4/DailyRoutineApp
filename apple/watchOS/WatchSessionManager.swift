import Foundation
import WatchConnectivity

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    @Published private(set) var context: WatchRoutineContext?
    @Published private(set) var isReachable = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ event: WatchEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        let payload: [String: Any] = ["watchEvent": data]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(payload)
            }
        } else {
            WCSession.default.transferUserInfo(payload)
        }
    }

    private func receive(_ applicationContext: [String: Any]) {
        guard
            let data = applicationContext["routineContext"] as? Data,
            let nextContext = try? JSONDecoder().decode(WatchRoutineContext.self, from: data)
        else { return }

        context = nextContext
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
