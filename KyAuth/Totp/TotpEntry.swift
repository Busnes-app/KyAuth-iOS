import CryptoKit
import Foundation

struct TotpEntry: Codable, Equatable, Identifiable {
    enum Algorithm: String, Codable, CaseIterable {
        case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512"
    }

    var id: String
    var title: String
    var secretBase32: String
    var digits: Int
    var periodSeconds: Int64
    var algorithm: Algorithm
    var issuer: String?
    var url: String?
    var notes: String?

    init(
        title: String, secretBase32: String, digits: Int = 6, periodSeconds: Int64 = 30,
        algorithm: Algorithm = .sha1, issuer: String? = nil, url: String? = nil, notes: String? = nil,
        id: String = UUID().uuidString
    ) throws {
        guard !title.isBlank else { throw TotpError.invalid("Enter a name") }
        guard (6...8).contains(digits) else { throw TotpError.invalid("Codes must have 6 to 8 digits") }
        guard periodSeconds > 0 else { throw TotpError.invalid("The period must be positive") }
        guard TotpGenerator.isUsableSecret(secretBase32) else { throw TotpError.invalid("TOTP secret is not usable Base32") }
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secretBase32 = secretBase32
        self.digits = digits
        self.periodSeconds = periodSeconds
        self.algorithm = algorithm
        self.issuer = issuer
        self.url = url?.trimmedNonBlank
        self.notes = notes?.trimmedNonBlank
    }
}

enum TotpError: LocalizedError, Equatable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

enum TotpGenerator {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private static let pow10: [UInt32] = [1, 10, 100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000]

    static func code(_ entry: TotpEntry, at epochSeconds: Int64) throws -> String {
        let counter = UInt64(epochSeconds / entry.periodSeconds).bigEndian
        let message = withUnsafeBytes(of: counter) { Data($0) }
        let key = SymmetricKey(data: try base32Decode(entry.secretBase32))
        let digest: [UInt8] = switch entry.algorithm {
        case .sha1: Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        let offset = Int(digest[digest.count - 1] & 0x0f)
        let value = (UInt32(digest[offset] & 0x7f) << 24)
            | (UInt32(digest[offset + 1]) << 16)
            | (UInt32(digest[offset + 2]) << 8)
            | UInt32(digest[offset + 3])
        let code = String(value % pow10[entry.digits])
        return String(repeating: "0", count: entry.digits - code.count) + code
    }

    static func secondsRemaining(_ entry: TotpEntry, at epochSeconds: Int64) -> Int64 {
        entry.periodSeconds - (epochSeconds % entry.periodSeconds)
    }

    /// "123 456" for six digits; other lengths unchanged.
    static func formatted(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    /// True when the secret decodes to at least one byte: one Base32 character decodes to nothing,
    /// and an empty HMAC key would make every code meaningless.
    static func isUsableSecret(_ secret: String) -> Bool {
        (try? base32Decode(secret).isEmpty == false) ?? false
    }

    static func base32Decode(_ input: String) throws -> Data {
        let normalized = input.uppercased().filter { $0 != "=" && !$0.isWhitespace }
        guard !normalized.isEmpty else { throw TotpError.invalid("TOTP secret is empty") }
        var bits = 0
        var value = 0
        var output = Data()
        for character in normalized {
            guard let digit = alphabet.firstIndex(of: character) else { throw TotpError.invalid("TOTP secret is not Base32") }
            value = ((value << 5) | digit) & 0xffff
            bits += 5
            if bits >= 8 {
                output.append(UInt8((value >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return output
    }
}

enum TotpUriParser {
    static func parse(_ raw: String) throws -> TotpEntry {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw TotpError.invalid("URI is empty") }
        guard let uri = URLComponents(string: value), uri.scheme?.lowercased() == "otpauth" else {
            throw TotpError.invalid("This is not an authenticator QR code")
        }
        guard uri.host?.lowercased() == "totp" else {
            throw TotpError.invalid("Only TOTP is supported (got \(uri.host ?? "nothing"))")
        }
        var params: [String: String] = [:]
        for item in uri.queryItems ?? [] where params[item.name] == nil {
            params[item.name] = item.value
        }
        guard let secret = params["secret"]?.trimmedNonBlank else { throw TotpError.invalid("Missing OTP secret parameter") }

        let path = uri.path.hasPrefix("/") ? String(uri.path.dropFirst()) : uri.path
        let label = path.isBlank ? "Account" : path
        let issuer = params["issuer"]?.trimmedNonBlank
        let algorithm: TotpEntry.Algorithm = switch params["algorithm"]?.uppercased() {
        case "SHA256": .sha256
        case "SHA512": .sha512
        default: .sha1
        }

        let title: String
        if let colon = label.firstIndex(of: ":") {
            let prefix = label[..<colon].trimmingCharacters(in: .whitespaces)
            let suffix = label[label.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            title = suffix.isEmpty ? prefix : "\(prefix) (\(suffix))"
        } else if let issuer, issuer.caseInsensitiveCompare(label) != .orderedSame {
            title = "\(issuer) (\(label))"
        } else {
            title = label
        }

        return try TotpEntry(
            title: title,
            secretBase32: secret,
            digits: params["digits"].flatMap { Int($0) } ?? 6,
            periodSeconds: params["period"].flatMap { Int64($0) } ?? 30,
            algorithm: algorithm,
            issuer: issuer
        )
    }
}
