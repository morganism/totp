import SwiftUI
import AVFoundation

// MARK: - Add Account View (iPhone)
// Mirrors the PWA's Add Account modal with Manual / QR / Import tabs

struct iPhoneAddAccountView: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab: Tab = .manual

    enum Tab: String, CaseIterable {
        case manual = "Manual"
        case qr     = "Scan QR"
        case uri    = "Import URI"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker (matches PWA nav-tabs)
                Picker("Method", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case .manual: ManualEntryTab().environmentObject(store)
                case .qr:     QRScanTab().environmentObject(store)
                case .uri:    URIImportTab().environmentObject(store)
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Manual Entry Tab

struct ManualEntryTab: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    @State private var account: String = ""
    @State private var issuer: String = ""
    @State private var secret: String = ""
    @State private var digits: Int = 6
    @State private var period: Int = 30
    @State private var error: String? = nil

    var body: some View {
        Form {
            Section("Account") {
                TextField("Account / Email *", text: $account)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Issuer / Service", text: $issuer)
                    .autocorrectionDisabled()
            }

            Section("Secret Key (Base32)") {
                SecureField("JBSWY3DPEHPK3PXP", text: $secret)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                Text("Enter the secret key shown by your service")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Options") {
                Picker("Digits", selection: $digits) {
                    Text("6 digits").tag(6)
                    Text("8 digits").tag(8)
                }
                Picker("Interval", selection: $period) {
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                }
            }

            if let err = error {
                Section {
                    Text(err).foregroundStyle(.red)
                }
            }

            Section {
                Button("Add Account", action: save)
                    .frame(maxWidth: .infinity)
                    .disabled(account.isEmpty || secret.isEmpty)
            }
        }
    }

    private func save() {
        error = nil
        let clean = secret.uppercased().replacingOccurrences(of: " ", with: "")
        guard (try? TOTPEngine.base32Decode(clean)) != nil else {
            error = "Invalid Base32 secret key. Check for typos."
            return
        }
        store.add(TOTPAccount(
            issuer: issuer.trimmingCharacters(in: .whitespaces),
            accountName: account.trimmingCharacters(in: .whitespaces),
            secret: clean, digits: digits, period: period
        ))
        dismiss()
    }
}

// MARK: - QR Scan Tab

struct QRScanTab: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    @State private var scanned: String? = nil
    @State private var error: String? = nil
    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 16) {
            switch cameraPermission {
            case .authorized:
                QRCameraView { code in
                    handleScan(code)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxHeight: 300)
                .padding(.horizontal)

                Text("Point at a TOTP QR code")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .denied, .restricted:
                ContentUnavailableView(
                    "Camera Access Required",
                    systemImage: "camera.slash",
                    description: Text("Enable camera access in Settings to scan QR codes")
                )
                Button("Open Settings") {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
                .buttonStyle(.borderedProminent)

            default:
                Button("Enable Camera") {
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.main.async {
                            cameraPermission = granted ? .authorized : .denied
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            if let err = error {
                Label(err, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top)
        .onAppear {
            cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
            if cameraPermission == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        cameraPermission = granted ? .authorized : .denied
                    }
                }
            }
        }
    }

    private func handleScan(_ code: String) {
        guard scanned == nil else { return }
        scanned = code
        do {
            let account = try TOTPEngine.parseOtpauthURI(code)
            store.add(account)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            self.error = "Not a valid TOTP QR code"
            scanned = nil
        }
    }
}

// MARK: - Camera View (AVFoundation wrapper)

struct QRCameraView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QRCameraVC {
        let vc = QRCameraVC()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ uiViewController: QRCameraVC, context: Context) {}
}

class QRCameraVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupSession() {
        let session = AVCaptureSession()
        self.session = session

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        self.previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let string = obj.stringValue else { return }
        onScan?(string)
    }
}

// MARK: - URI Import Tab

struct URIImportTab: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    @State private var format: ImportFormat = .uri
    @State private var text: String = ""
    @State private var error: String? = nil
    @State private var success: String? = nil

    enum ImportFormat: String, CaseIterable {
        case uri    = "otpauth:// URI"
        case json   = "JSON"
        case base64 = "Base64"
    }

    var body: some View {
        Form {
            Section("Import Format") {
                Picker("Format", selection: $format) {
                    ForEach(ImportFormat.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Data") {
                TextEditor(text: $text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(placeholder)
                                .foregroundStyle(.secondary.opacity(0.5))
                                .font(.caption)
                                .padding(6)
                                .allowsHitTesting(false)
                        }
                    }
            }

            if let err = error {
                Section { Text(err).foregroundStyle(.red) }
            }
            if let suc = success {
                Section { Text(suc).foregroundStyle(.green) }
            }

            Section {
                Button("Import", action: doImport)
                    .frame(maxWidth: .infinity)
                    .disabled(text.isEmpty)
            }
        }
    }

    private var placeholder: String {
        switch format {
        case .uri:    return "otpauth://totp/Issuer:user@example.com?secret=BASE32&issuer=Issuer"
        case .json:   return #"{"version":"1.0","accounts":[...]}"#
        case .base64: return "eyJ2ZXJzaW9uIjoiMS4w..."
        }
    }

    private func doImport() {
        error = nil
        success = nil
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            switch format {
            case .uri:
                let lines = raw.components(separatedBy: .newlines)
                    .filter { $0.hasPrefix("otpauth://") }
                if lines.isEmpty { throw AccountStore.ImportError.invalidData }
                for line in lines { try store.importOtpauthURI(line) }
                success = "Imported \(lines.count) account(s)"

            case .json:
                let count = try store.importJSON(raw)
                success = "Imported \(count) account(s)"

            case .base64:
                let count = try store.importBase64(raw)
                success = "Imported \(count) account(s)"
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
        } catch {
            self.error = "Import failed: \(error.localizedDescription)"
        }
    }
}
