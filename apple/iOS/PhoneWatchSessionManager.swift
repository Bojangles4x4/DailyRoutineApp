import Foundation
import WatchConnectivity

@MainActor
final class PhoneWatchSessionManager: NSObject, ObservableObject {
    @Published private(set) var isReachable = false
    var onEvent: ((WatchEvent) -> Void)?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func update(context: WatchRoutineContext) throws {
        let data = try JSONEncoder().encode(context)
        try WCSession.default.updateApplicationContext(["routineContext": data])
    }
}

extension PhoneWatchSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }

    nonisolated private func receive(_ payload: [String: Any]) {
        guard
            let data = payload["watchEvent"] as? Data,
            let event = try? JSONDecoder().decode(WatchEvent.self, from: data)
        else { return }

        Task { @MainActor in
            onEvent?(event)
        }
    }
}
