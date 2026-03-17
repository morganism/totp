import SwiftUI

// MARK: - Export View
// Mirrors the PWA's Export Modal (JSON / Base64 / otpauth URI)

struct iPhoneExportView: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    @State private var format: ExportFormat = .json
    @State private var exportText: String = ""
    @State private var copied = false
    @State private var error: String? = nil

    enum ExportFormat: String, CaseIterable {
        case json   = "JSON (Full)"
        case base64 = "Base64 (Compact)"
        case uri    = "otpauth:// URIs"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Export Format", selection: $format) {
                        ForEach(ExportFormat.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: format) { _, _ in generate() }
                }

                Section("Export Data") {
                    TextEditor(text: .constant(exportText))
                        .font(.system(.caption2, design: .monospaced))
                        .frame(minHeight: 160)
                        .disabled(true)
                }

                if let err = error {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = exportText
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Label(copied ? "Copied!" : "Copy to Clipboard",
                              systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    ShareLink(item: exportText) {
                        Label("Share / Save File", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .navigationTitle("Export Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { generate() }
        }
    }

    private func generate() {
        error = nil
        do {
            switch format {
            case .json:
                exportText = try store.exportJSON()
            case .base64:
                exportText = try store.exportBase64()
            case .uri:
                exportText = store.accounts
                    .map { TOTPEngine.generateOtpauthURI(for: $0) }
                    .joined(separator: "\n")
            }
        } catch {
            self.error = "Export failed: \(error.localizedDescription)"
            exportText = ""
        }
    }
}

// MARK: - Settings View

struct iPhoneSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("colorScheme") private var colorSchemeRaw: String = "auto"

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $colorSchemeRaw) {
                        Text("System").tag("auto")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Algorithm", value: "HMAC-SHA1 (RFC 6238)")
                    LabeledContent("Storage", value: "UserDefaults (local)")
                }

                Section("Security") {
                    Label("Secrets stored locally on device", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("No network access required", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
