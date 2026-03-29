import SwiftUI

// MARK: - iPhone Content View
// Mirrors the PWA's accounts grid with search, add, export, theme toggle

struct iPhoneContentView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var session: WatchSessionManager

    @State private var searchText = ""
    @State private var showAdd = false
    @State private var showExport = false
    @State private var showSettings = false
    @AppStorage("colorScheme") private var colorSchemeRaw: String = "auto"

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
                    iPhoneEmptyState()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(filtered) { account in
                                iPhoneAccountCard(account: account)
                                    .contextMenu {
                                        accountContextMenu(account)
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("🔐 TOTP Authenticator")
            .searchable(text: $searchText, prompt: "Search accounts…")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Watch sync indicator
                    if session.isReachable {
                        Image(systemName: "applewatch")
                            .foregroundStyle(.blue)
                            .help("Apple Watch connected")
                    }
                    Button { showExport = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                iPhoneAddAccountView().environmentObject(store)
            }
            .sheet(isPresented: $showExport) {
                iPhoneExportView().environmentObject(store)
            }
            .sheet(isPresented: $showSettings) {
                iPhoneSettingsView()
            }
        }
    }

    @ViewBuilder
    private func accountContextMenu(_ account: TOTPAccount) -> some View {
        Button {
            // Edit — navigated inline
        } label: { Label("Edit", systemImage: "pencil") }

        Button(role: .destructive) {
            store.delete(id: account.id)
        } label: { Label("Delete", systemImage: "trash") }
    }
}

// MARK: - Account Card (matches PWA .totp-card)

struct iPhoneAccountCard: View {
    let account: TOTPAccount

    @State private var code: String = "------"
    @State private var secondsLeft: Int = 30
    @State private var progress: Double = 0.0
    @State private var copied: Bool = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header — matches PWA .card-header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if !account.subtitle.isEmpty {
                        Text(account.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                ZStack {
                    Circle().fill(accentColor.gradient).frame(width: 32, height: 32)
                    Text(account.initial)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().opacity(0.4)

            // Code — matches PWA .totp-code, click to copy
            Button(action: copyCode) {
                Text(formattedCode)
                    .font(.system(size: 34, weight: .light, design: .monospaced))
                    .foregroundStyle(isExpiring ? .red : Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .padding(.vertical, 16)
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)

            Divider().opacity(0.4)

            // Footer — matches PWA .card-footer with countdown-progress
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isExpiring
                                  ? LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
                                  : LinearGradient(colors: [Color.accentColor, .purple], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(1.0 - progress), height: 4)
                            .animation(.linear(duration: 1), value: progress)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(copied ? "✓ Copied!" : "\(secondsLeft)s")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copied ? .green : .secondary)
                        .animation(.easeInOut, value: copied)
                    Spacer()
                    Text("\(account.digits) digits")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        .onAppear { refresh() }
        .onReceive(timer) { _ in tick() }
    }

    // MARK: - Helpers

    private var formattedCode: String {
        code.count == 6 ? String(code.prefix(3)) + " " + String(code.suffix(3)) : code
    }

    private var isExpiring: Bool { secondsLeft <= 5 }

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

    private func tick() {
        secondsLeft = TOTPEngine.secondsRemaining(period: account.period)
        progress = TOTPEngine.progress(period: account.period)
        if secondsLeft == account.period { refresh() }
    }

    private func refresh() {
        Task {
            if let c = try? await TOTPEngine.totp(secret: account.secret, digits: account.digits, period: account.period) {
                await MainActor.run {
                    withAnimation { code = c }
                }
            }
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = code.replacingOccurrences(of: " ", with: "")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }
}

// MARK: - Empty State

struct iPhoneEmptyState: View {
    @EnvironmentObject var store: AccountStore
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 16) {
            Text("🔑").font(.system(size: 64))
            Text("No Accounts Yet")
                .font(.title2).bold()
            Text("Add your first TOTP account to get started")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Account") { showAdd = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
        .sheet(isPresented: $showAdd) {
            iPhoneAddAccountView().environmentObject(store)
        }
    }
}
