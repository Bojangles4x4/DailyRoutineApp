import Foundation
import WatchConnectivity

@MainActor
final class PhoneWatchSessionManager: NSObject, ObservableObject {
    @Published private(set) var isReachable = false
    @Published private(set) var isWatchAppInstalled = false
    var onEvent: ((WatchEvent) -> Void)?
    private var pendingContext: WatchRoutineContext?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @discardableResult
    func update(context: WatchRoutineContext) -> Bool {
        pendingContext = context
        return sendPendingContext()
    }

    @discardableResult
    private func sendPendingContext() -> Bool {
        guard
            let context = pendingContext,
            WCSession.default.activationState == .activated,
            WCSession.default.isPaired,
            WCSession.default.isWatchAppInstalled,
            let data = try? JSONEncoder().encode(context)
        else { return false }

        do {
            try WCSession.default.updateApplicationContext(["routineContext": data])
            pendingContext = nil
            return true
        } catch {
            return false
        }
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
            isWatchAppInstalled = session.isWatchAppInstalled
            sendPendingContext()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            isWatchAppInstalled = session.isWatchAppInstalled
            sendPendingContext()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            isWatchAppInstalled = session.isWatchAppInstalled
            sendPendingContext()
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
