import SwiftUI

@main
struct TOTPWatchApp: App {
    @StateObject private var store = AccountStore()
    @StateObject private var session = WatchSessionManager.shared

    init() {
        // Wire up account sync from iPhone
        let s = WatchSessionManager.shared
        // Will be connected once store is available — done in ContentView onAppear
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(store)
                .environmentObject(session)
                .onAppear {
                    // When iPhone pushes new accounts, update the store
                    session.onAccountsReceived = { [weak store] accounts in
                        Task { @MainActor in
                            store?.accounts = accounts
                        }
                    }
                }
        }
    }
}
