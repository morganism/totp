import SwiftUI
import WatchKit  // WKInterfaceDevice.current().play(_:)

// MARK: - Full-screen TOTP code view for Apple Watch
// Tap anywhere for haptic feedback · Digital Crown to scroll between accounts
// Note: watchOS has no public pasteboard API; code is displayed for visual reading only.

struct WatchCodeView: View {
    let account: TOTPAccount

    @State private var code: String = "------"
    @State private var secondsLeft: Int = 30
    @State private var progress: Double = 0.0
    @State private var tapped: Bool = false
    @State private var codeOpacity: Double = 1.0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Background gradient — dark and focused
            LinearGradient(
                colors: [Color.black, Color(white: 0.07)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 4) {

                // Service name
                Text(account.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)

                // Account subtitle
                if !account.subtitle.isEmpty {
                    Text(account.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                // Countdown ring + code stacked
                ZStack {
                    // Outer track
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 7)

                    // Progress arc (matches PWA countdown-bar)
                    Circle()
                        .trim(from: 0, to: CGFloat(1.0 - progress))
                        .stroke(
                            AngularGradient(
                                colors: isExpiring ? [.red, .orange] : [.blue, .cyan],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)

                    // Code inside ring
                    VStack(spacing: 2) {
                        Text(formattedCode)
                            .font(.system(size: 24, weight: .thin, design: .monospaced))
                            .foregroundStyle(isExpiring ? Color.red : Color.white)
                            .opacity(codeOpacity)
                            .animation(.easeInOut(duration: 0.3), value: codeOpacity)
                            .contentTransition(.numericText())

                        Text("\(secondsLeft)s")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(isExpiring ? .red : .white.opacity(0.5))
                    }
                }
                .frame(width: 120, height: 120)

                Spacer(minLength: 2)

                // Tap hint / confirmation
                if tapped {
                    Label("OK!", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("Tap for haptic")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.vertical, 6)
        }
        .onTapGesture { handleTap() }
        .onAppear {
            tick()
            refreshCode()
        }
        .onReceive(timer) { _ in tick() }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Computed

    private var formattedCode: String {
        code.count == 6
            ? String(code.prefix(3)) + " " + String(code.suffix(3))
            : code
    }

    private var isExpiring: Bool { secondsLeft <= 5 }

    // MARK: - Actions

    private func tick() {
        secondsLeft = TOTPEngine.secondsRemaining(period: account.period)
        progress    = TOTPEngine.progress(period: account.period)
        if secondsLeft == account.period { refreshCode() }
    }

    private func refreshCode() {
        Task {
            do {
                let c = try await TOTPEngine.totp(
                    secret: account.secret,
                    digits: account.digits,
                    period: account.period
                )
                await MainActor.run {
                    withAnimation { codeOpacity = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        code = c
                        withAnimation { codeOpacity = 1 }
                    }
                }
            } catch {
                await MainActor.run { code = "ERROR" }
            }
        }
    }

    private func handleTap() {
        // watchOS has no public pasteboard API — provide haptic feedback only.
        // Users read the code from the screen.
        WKInterfaceDevice.current().play(.success)

        withAnimation(.spring(duration: 0.3)) { tapped = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { tapped = false }
        }
    }
}
