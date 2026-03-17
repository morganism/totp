import SwiftUI

@main
struct TOTPiPhoneApp: App {
    @StateObject private var store = AccountStore()
    @StateObject private var session = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
          if #available(iOS 17.0, *) {
            iPhoneContentView()
              .environmentObject(store)
              .environmentObject(session)
              .onChange(of: store.accounts) { _, accounts in
                // Auto-sync to Watch whenever accounts change
                session.sendAccounts(accounts)
              }
          } else {
            // Fallback on earlier versions
          }
        }
    }
}
