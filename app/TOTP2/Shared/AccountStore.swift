import Foundation
import Combine

// MARK: - Account Model
// Mirrors PWA account schema (StorageManager fields)

struct TOTPAccount: Identifiable, Codable, Hashable, Equatable {
    var id: UUID = UUID()
    var issuer: String          // e.g. "GitHub"
    var accountName: String     // e.g. "user@example.com"
    var secret: String          // Base32-encoded
    var digits: Int = 6
    var period: Int = 30
    var algorithm: String = "SHA1"
    var order: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: Display helpers
    var displayName: String { issuer.isEmpty ? accountName : issuer }
    var subtitle: String { issuer.isEmpty ? "" : accountName }
    var initial: String { String(displayName.prefix(1)).uppercased() }

    /// Stable accent colour derived from the name (no random, always consistent)
    var accentColor: AccentColor {
        let colours: [AccentColor] = [.blue, .purple, .pink, .red, .orange, .green, .teal, .indigo]
        let hash = abs(displayName.hash)
        return colours[hash % colours.count]
    }

    enum AccentColor: String, Codable {
        case blue, purple, pink, red, orange, green, teal, indigo
    }
}

// MARK: - Export/Import types (matching PWA JSON format)

struct TOTPExport: Codable {
    var version: String = "1.0"
    var exported: Date = Date()
    var accounts: [TOTPAccount]
}

// MARK: - Account Store

@MainActor
class AccountStore: ObservableObject {
    @Published var accounts: [TOTPAccount] = []

    private let saveKey = "totp_accounts_v1"

    init() { load() }

    // MARK: - CRUD

    func add(_ account: TOTPAccount) {
        var a = account
        a.order = accounts.count
        a.createdAt = Date()
        a.updatedAt = Date()
        accounts.append(a)
        save()
    }

    func update(_ account: TOTPAccount) {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        var a = account
        a.updatedAt = Date()
        accounts[idx] = a
        save()
    }

    func delete(at offsets: IndexSet) {
        accounts.remove(atOffsets: offsets)
        reorder()
        save()
    }

    func delete(id: UUID) {
        accounts.removeAll { $0.id == id }
        reorder()
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        reorder()
        save()
    }

    // MARK: - Import / Export (matches PWA formats)

    func exportJSON() throws -> String {
        let export = TOTPExport(accounts: accounts)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(export)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func importJSON(_ json: String) throws -> Int {
        guard let data = json.data(using: .utf8) else { throw ImportError.invalidData }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(TOTPExport.self, from: data)
        let before = accounts.count
        for var acc in export.accounts {
            acc.id = UUID()   // Fresh ID to avoid collisions
            acc.order = accounts.count
            accounts.append(acc)
        }
        save()
        return accounts.count - before
    }

    func importOtpauthURI(_ uri: String) throws {
        let account = try TOTPEngine.parseOtpauthURI(uri)
        add(account)
    }

    func importBase64(_ b64: String) throws -> Int {
        guard let data = Data(base64Encoded: b64),
              let json = String(data: data, encoding: .utf8) else { throw ImportError.invalidData }
        return try importJSON(json)
    }

    func exportBase64() throws -> String {
        let json = try exportJSON()
        guard let data = json.data(using: .utf8) else { throw ImportError.invalidData }
        return data.base64EncodedString()
    }

    enum ImportError: LocalizedError {
        case invalidData
        var errorDescription: String? { "Invalid import data" }
    }

    // MARK: - Persistence (UserDefaults — upgrade to Keychain in production)

    private func save() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([TOTPAccount].self, from: data) {
            accounts = decoded.sorted { $0.order < $1.order }
        } else {
            // Sample accounts on first launch — matches PWA demo data
            accounts = [
                TOTPAccount(issuer: "GitHub", accountName: "you@example.com",
                            secret: "JBSWY3DPEHPK3PXP", digits: 6, period: 30),
                TOTPAccount(issuer: "Google", accountName: "you@gmail.com",
                            secret: "JBSWY3DPEHPK3PXP", digits: 6, period: 30),
            ]
        }
    }

    private func reorder() {
        for i in accounts.indices { accounts[i].order = i }
    }
}
