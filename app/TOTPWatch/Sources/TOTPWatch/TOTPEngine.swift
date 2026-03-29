import Foundation
import CryptoKit

// MARK: - RFC 6238 TOTP Engine
struct TOTPEngine {

    /// Generate a 6-digit TOTP code from a Base32-encoded secret
    static func generate(secret: String, digits: Int = 6, period: Int = 30) -> String {
        guard let keyData = base32Decode(secret) else { return "------" }
        let counter = UInt64(Date().timeIntervalSince1970) / UInt64(period)
        return hotp(key: keyData, counter: counter, digits: digits)
    }

    /// How many seconds remain in the current 30-second window
    static func secondsRemaining(period: Int = 30) -> Int {
        let t = Int(Date().timeIntervalSince1970)
        return period - (t % period)
    }

    /// 0.0 = window just started, 1.0 = window about to expire
    static func progress(period: Int = 30) -> Double {
        let t = Date().timeIntervalSince1970
        let elapsed = t.truncatingRemainder(dividingBy: Double(period))
        return elapsed / Double(period)
    }

    // MARK: - HMAC-SHA1 OTP (RFC 4226)
    private static func hotp(key: Data, counter: UInt64, digits: Int) -> String {
        var bigEndian = counter.bigEndian
        let counterData = withUnsafeBytes(of: &bigEndian) { Data($0) }
        let symKey = SymmetricKey(data: key)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: symKey)
        var hmac = Data(mac)

        let offset = Int(hmac[hmac.count - 1] & 0x0f)
        let slice = hmac.subdata(in: offset ..< offset + 4)
        var num: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &num) { slice.copyBytes(to: $0) }
        num = UInt32(bigEndian: num) & 0x7fff_ffff

        let otp = num % UInt32(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)u", otp)
    }

    // MARK: - Base32 Decoder (RFC 4648)
    private static func base32Decode(_ input: String) -> Data? {
        let table = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let clean = input.uppercased()
                         .replacingOccurrences(of: " ", with: "")
                         .replacingOccurrences(of: "=", with: "")
        var buffer = 0
        var bitsLeft = 0
        var result = Data()

        for ch in clean {
            guard let idx = table.firstIndex(of: ch) else { continue }
            buffer = (buffer << 5) | table.distance(from: table.startIndex, to: idx)
            bitsLeft += 5
            if bitsLeft >= 8 {
                bitsLeft -= 8
                result.append(UInt8((buffer >> bitsLeft) & 0xff))
            }
        }
        return result.isEmpty ? nil : result
    }
}
