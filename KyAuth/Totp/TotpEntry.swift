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
        _ = try TotpGenerator.validatedSecret(secretBase32)
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
    case shortSecret

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .shortSecret: "Setup key is too short (minimum 16 decoded bytes). Set up this account again at its service using a new key. Keep your recovery codes until the new setup works."
        }
    }
}

enum TotpGenerator {
    // RFC 4226 requires at least 128 key bits and recommends 160.
    static let minimumSecretBytes = 16
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private static let pow10: [UInt32] = [1, 10, 100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000]

    static func code(_ entry: TotpEntry, at epochSeconds: Int64) throws -> String {
        // Codable restores legacy records without the validating initializer.
        let secret = try validatedSecret(entry.secretBase32)
        let counter = UInt64(epochSeconds / entry.periodSeconds).bigEndian
        let message = withUnsafeBytes(of: counter) { Data($0) }
        let key = SymmetricKey(data: secret)
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

    /// Import and generation policy; decoding a legacy vault remains lossless.
    static func isUsableSecret(_ secret: String) -> Bool {
        (try? validatedSecret(secret)) != nil
    }

    static func validatedSecret(_ secret: String) throws -> Data {
        let decoded = try base32Decode(secret)
        guard decoded.count >= minimumSecretBytes else { throw TotpError.shortSecret }
        return decoded
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
        // A valueless parameter (`&digits`) is present but empty, so it is refused below rather
        // than mistaken for an omitted one.
        for item in uri.queryItems ?? [] where params[item.name] == nil {
            params[item.name] = item.value ?? ""
        }
        guard let secret = params["secret"]?.trimmedNonBlank else { throw TotpError.invalid("Missing OTP secret parameter") }

        let path = uri.path.hasPrefix("/") ? String(uri.path.dropFirst()) : uri.path
        let label = path.isBlank ? "Account" : path
        let issuer = params["issuer"]?.trimmedNonBlank
        // Defaults cover omitted parameters only: a supplied value KyAuth cannot honour would
        // produce codes the service never accepts, so it is refused rather than replaced.
        let algorithm: TotpEntry.Algorithm
        switch params["algorithm"]?.uppercased() {
        case nil, "SHA1": algorithm = .sha1
        case "SHA256": algorithm = .sha256
        case "SHA512": algorithm = .sha512
        case let other?: throw TotpError.invalid("Unsupported algorithm \(other)")
        }
        let digits = try number(params["digits"], default: 6, name: "digits")
        let period = try number(params["period"], default: 30, name: "period")

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
            digits: Int(digits),
            periodSeconds: period,
            algorithm: algorithm,
            issuer: issuer
        )
    }

    private static func number(_ raw: String?, default value: Int64, name: String) throws -> Int64 {
        guard let raw else { return value }
        guard let parsed = Int64(raw.trimmingCharacters(in: .whitespaces)), parsed > 0 else {
            throw TotpError.invalid("Invalid \(name) \(raw)")
        }
        return parsed
    }
}
