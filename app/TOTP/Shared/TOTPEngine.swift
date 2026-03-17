import Foundation
import CryptoKit

// MARK: - RFC 6238 TOTP Engine
// Faithful port of the PWA's TOTP implementation (index.html lines ~120-220)

enum TOTPError: Error {
    case invalidBase32Character(Character)
    case invalidSecret
    case invalidURI
}

struct TOTPEngine {

    // MARK: - Public API

    /// Generate a TOTP code (RFC 6238)
    static func totp(secret: String, digits: Int = 6, period: Int = 30) async throws -> String {
        let counter = UInt64(Date().timeIntervalSince1970) / UInt64(period)
        return try await hotp(secret: secret, counter: counter, digits: digits)
    }

    /// Remaining seconds in the current window
    static func secondsRemaining(period: Int = 30) -> Int {
        let t = Int(Date().timeIntervalSince1970)
        return period - (t % period)
    }

    /// Progress fraction 0→1 within the current window (0 = fresh, 1 = expiring)
    static func progress(period: Int = 30) -> Double {
        let t = Date().timeIntervalSince1970
        let elapsed = t.truncatingRemainder(dividingBy: Double(period))
        return elapsed / Double(period)
    }

    /// Validate a TOTP code with ±1 window drift
    static func validate(secret: String, code: String, digits: Int = 6, period: Int = 30) async -> Bool {
        let counter = UInt64(Date().timeIntervalSince1970) / UInt64(period)
        for offset in [-1, 0, 1] {
            let c = counter &+ UInt64(bitPattern: Int64(offset))
            if let generated = try? await hotp(secret: secret, counter: c, digits: digits),
               generated == code.trimmingCharacters(in: .whitespaces) {
                return true
            }
        }
        return false
    }

    /// Parse otpauth:// URI (matches PWA parseOtpauthURI)
    static func parseOtpauthURI(_ uri: String) throws -> TOTPAccount {
        guard uri.hasPrefix("otpauth://totp/"),
              let url = URL(string: uri) else { throw TOTPError.invalidURI }

        let rawLabel = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let label = rawLabel.removingPercentEncoding ?? rawLabel
        let params = url.queryParameters

        var issuer = params["issuer"] ?? ""
        var account = label

        if label.contains(":") {
            let parts = label.split(separator: ":", maxSplits: 1)
            if issuer.isEmpty { issuer = String(parts[0]) }
            account = parts.count > 1 ? String(parts[1]) : label
        }

        guard let secret = params["secret"], !secret.isEmpty else { throw TOTPError.invalidSecret }

        return TOTPAccount(
            issuer: issuer,
            accountName: account,
            secret: secret.uppercased(),
            digits: Int(params["digits"] ?? "6") ?? 6,
            period: Int(params["period"] ?? "30") ?? 30
        )
    }

    /// Generate otpauth:// URI from account
    static func generateOtpauthURI(for account: TOTPAccount) -> String {
        let label: String
        if account.issuer.isEmpty {
            label = account.accountName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? account.accountName
        } else {
            let iss = account.issuer.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? account.issuer
            let acc = account.accountName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? account.accountName
            label = "\(iss):\(acc)"
        }
        var query = "secret=\(account.secret)&algorithm=SHA1&digits=\(account.digits)&period=\(account.period)"
        if !account.issuer.isEmpty {
            let iss = account.issuer.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? account.issuer
            query += "&issuer=\(iss)"
        }
        return "otpauth://totp/\(label)?\(query)"
    }

    /// Generate a random Base32 secret (20 bytes = 160-bit)
    static func generateSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 20)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base32Encode(Data(bytes))
    }

    // MARK: - HOTP (RFC 4226)
    // Mirrors PWA hotp() at index.html ~line 170

    static func hotp(secret: String, counter: UInt64, digits: Int = 6) async throws -> String {
        let keyData = try base32Decode(secret)

        // 8-byte big-endian counter (matches JS DataView setUint32 big-endian)
        var bigEndian = counter.bigEndian
        let counterData = withUnsafeBytes(of: &bigEndian) { Data($0) }

        // HMAC-SHA1
        let symKey = SymmetricKey(data: keyData)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: symKey)
        let hmac = Array(mac)

        // Dynamic truncation (matches PWA lines ~183-188)
        let offset = Int(hmac[19] & 0x0f)
        let code = (Int(hmac[offset]     & 0x7f) << 24) |
                   (Int(hmac[offset + 1] & 0xff) << 16) |
                   (Int(hmac[offset + 2] & 0xff) << 8)  |
                   (Int(hmac[offset + 3] & 0xff))

        let otp = code % Int(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)d", otp)
    }

    // MARK: - Base32 (RFC 4648)
    // Mirrors PWA decodeBase32 / encodeBase32

    static func base32Decode(_ input: String) throws -> Data {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let clean = input.uppercased()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: " ", with: "")

        var buffer = 0
        var bitsLeft = 0
        var result = Data()

        for ch in clean {
            guard let idx = alphabet.firstIndex(of: ch) else {
                throw TOTPError.invalidBase32Character(ch)
            }
            let val = alphabet.distance(from: alphabet.startIndex, to: idx)
            buffer = (buffer << 5) | val
            bitsLeft += 5
            if bitsLeft >= 8 {
                bitsLeft -= 8
                result.append(UInt8((buffer >> bitsLeft) & 0xff))
            }
        }

        guard !result.isEmpty else { throw TOTPError.invalidSecret }
        return result
    }

    static func base32Encode(_ data: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var output = ""
        var buf = 0
        var bits = 0

        for byte in data {
            buf = (buf << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(buf >> bits) & 0x1f])
            }
        }
        if bits > 0 {
            output.append(alphabet[(buf << (5 - bits)) & 0x1f])
        }
        return output
    }
}

// MARK: - URL Query Helpers
extension URL {
    var queryParameters: [String: String] {
        var params: [String: String] = [:]
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .forEach { params[$0.name] = $0.value }
        return params
    }
}
