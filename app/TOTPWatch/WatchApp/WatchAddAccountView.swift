import SwiftUI

// MARK: - Add Account on Watch
// Manual entry is limited on Watch — recommend using iPhone companion app
// Supports otpauth:// URI paste and manual secret entry via dictation

struct WatchAddAccountView: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    @State private var issuer: String = ""
    @State private var accountName: String = ""
    @State private var secret: String = ""
    @State private var error: String? = nil
    @State private var step: Step = .method

    enum Step { case method, manual, uri }

    var body: some View {
        NavigationStack {
            switch step {
            case .method:
                methodPicker
            case .manual:
                manualEntry
            case .uri:
                uriEntry
            }
        }
    }

    // MARK: - Method Picker

    var methodPicker: some View {
        List {
            Button {
                step = .manual
            } label: {
                Label("Manual Entry", systemImage: "keyboard")
            }

            Button {
                step = .uri
            } label: {
                Label("Paste URI", systemImage: "link")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tip: Add accounts from the iPhone app — easier with camera & QR scan.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Add Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Manual Entry

    var manualEntry: some View {
        Form {
            Section("Service") {
                TextField("Issuer (e.g. GitHub)", text: $issuer)
                TextField("Account / Email", text: $accountName)
            }
            Section("Secret") {
                TextField("Base32 Secret", text: $secret)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            }
            if let err = error {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption2)
            }
            Button("Add Account", action: saveManual)
                .buttonStyle(.borderedProminent)
                .disabled(accountName.isEmpty || secret.isEmpty)
        }
        .navigationTitle("Manual")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - URI Entry

    var uriEntry: some View {
        Form {
            Section("otpauth:// URI") {
                TextField("otpauth://totp/...", text: $secret)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            if let err = error {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption2)
            }
            Button("Import", action: saveURI)
                .buttonStyle(.borderedProminent)
                .disabled(secret.isEmpty)
        }
        .navigationTitle("Paste URI")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions

    private func saveManual() {
        error = nil
        let clean = secret.uppercased().replacingOccurrences(of: " ", with: "")
        guard (try? TOTPEngine.base32Decode(clean)) != nil else {
            error = "Invalid Base32 secret. Check and try again."
            return
        }
        let account = TOTPAccount(
            issuer: issuer.trimmingCharacters(in: .whitespaces),
            accountName: accountName.trimmingCharacters(in: .whitespaces),
            secret: clean
        )
        store.add(account)
        dismiss()
    }

    private func saveURI() {
        error = nil
        do {
            let account = try TOTPEngine.parseOtpauthURI(secret.trimmingCharacters(in: .whitespaces))
            store.add(account)
            dismiss()
        } catch {
            self.error = "Invalid URI. Use otpauth://totp/... format."
        }
    }
}
