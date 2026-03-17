import SwiftUI

@main
struct TOTPiPhoneApp: App {
    @StateObject private var store = AccountStore()
    @StateObject private var session = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            iPhoneContentView()
                .environmentObject(store)
                .environmentObject(session)
                .onChange(of: store.accounts) { _, accounts in
                    // Auto-sync to Watch whenever accounts change
                    session.sendAccounts(accounts)
                }
        }
    }
}
