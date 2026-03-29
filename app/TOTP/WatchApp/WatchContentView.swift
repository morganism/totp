import SwiftUI

// MARK: - Watch Content View
// Faithful watch translation of the PWA's account grid

struct WatchContentView: View {
    @EnvironmentObject var store: AccountStore
    @State private var showAddSheet = false
    @State private var searchText = ""

    var filtered: [TOTPAccount] {
        if searchText.isEmpty { return store.accounts }
        let q = searchText.lowercased()
        return store.accounts.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.accountName.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.accounts.isEmpty {
                    EmptyStateView()
                } else {
                    List {
                        ForEach(filtered) { account in
                            NavigationLink(destination: WatchCodeView(account: account)) {
                                WatchAccountRow(account: account)
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                    .listStyle(.carousel)
                }
            }
            .navigationTitle("🔐 TOTP")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                WatchAddAccountView()
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - Account Row (compact for Watch)

struct WatchAccountRow: View {
    let account: TOTPAccount
    @State private var code: String = "------"
    @State private var secondsLeft: Int = 30
    @State private var progress: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(accentColor.gradient)
                    .frame(width: 36, height: 36)
                Text(account.initial)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(formattedCode)
                    .font(.system(size: 16, weight: .light, design: .monospaced))
                    .foregroundStyle(codeColor)
                    .lineLimit(1)
            }

            Spacer()

            // Countdown ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: 1 - progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                Text("\(secondsLeft)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(ringColor)
            }
            .frame(width: 28, height: 28)
        }
        .onAppear { refresh() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
    }

    private var formattedCode: String {
        // Format as XXX XXX like the PWA does
        let digits = code.count
        if digits == 6 {
            return String(code.prefix(3)) + " " + String(code.suffix(3))
        }
        return code
    }

    private var progress: Double { TOTPEngine.progress(period: account.period) }
    private var secondsLeft: Int { TOTPEngine.secondsRemaining(period: account.period) }
    private var isExpiring: Bool { secondsLeft <= 5 }

    private var codeColor: Color { isExpiring ? .red : .primary }
    private var ringColor: Color { isExpiring ? .red : .blue }

    private var accentColor: Color {
        switch account.accentColor {
        case .blue:   return .blue
        case .purple: return .purple
        case .pink:   return .pink
        case .red:    return .red
        case .orange: return .orange
        case .green:  return .green
        case .teal:   return .teal
        case .indigo: return .indigo
        }
    }

    private func refresh() {
        Task {
            if let c = try? await TOTPEngine.totp(secret: account.secret, digits: account.digits, period: account.period) {
                await MainActor.run { code = c }
            }
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("🔑")
                .font(.system(size: 36))
            Text("No accounts")
                .font(.headline)
            Text("Add from iPhone")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
