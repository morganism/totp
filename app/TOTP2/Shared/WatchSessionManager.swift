import Foundation
import WatchConnectivity

// MARK: - Watch Connectivity Session Handler
// Syncs the account list between iPhone companion and Watch app

class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = WatchSessionManager()
    private let session: WCSession = .default

    @Published var isReachable: Bool = false
    var onAccountsReceived: (([TOTPAccount]) -> Void)?

    override private init() {
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Send from iPhone → Watch

    func sendAccounts(_ accounts: [TOTPAccount]) {
        guard session.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(accounts) else { return }

        let payload: [String: Any] = ["accounts": data.base64EncodedString()]

        // Use updateApplicationContext so Watch gets latest even when not reachable
        try? session.updateApplicationContext(payload)

        // Also send as message if Watch is reachable
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    // Receive on Watch
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handlePayload(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handlePayload(applicationContext)
    }

    private func handlePayload(_ payload: [String: Any]) {
        guard let b64 = payload["accounts"] as? String,
              let data = Data(base64Encoded: b64),
              let accounts = try? JSONDecoder().decode([TOTPAccount].self, from: data) else { return }
        DispatchQueue.main.async {
            self.onAccountsReceived?(accounts)
        }
    }

    // Required on iOS only
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
