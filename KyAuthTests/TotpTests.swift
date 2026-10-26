import Foundation
import Testing
@testable import KyAuth

@MainActor
struct TotpGeneratorTests {
    // RFC 6238 Appendix B vectors.
    @Test func rfc6238() throws {
        let sha1 = try TotpEntry(title: "t", secretBase32: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", digits: 8)
        #expect(try TotpGenerator.code(sha1, at: 59) == "94287082")
        #expect(try TotpGenerator.code(sha1, at: 1_111_111_109) == "07081804")
        let sha256 = try TotpEntry(
            title: "t", secretBase32: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA", digits: 8, algorithm: .sha256
        )
        #expect(try TotpGenerator.code(sha256, at: 59) == "46119246")
        let sha512 = try TotpEntry(
            title: "t",
            secretBase32: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA",
            digits: 8, algorithm: .sha512
        )
        #expect(try TotpGenerator.code(sha512, at: 59) == "90693936")
    }

    @Test func formattingAndCountdown() throws {
        #expect(TotpGenerator.formatted("123456") == "123 456")
        #expect(TotpGenerator.formatted("12345678") == "12345678")
        let entry = try TotpEntry(title: "t", secretBase32: "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP")
        #expect(TotpGenerator.secondsRemaining(entry, at: 59) == 1)
        #expect(TotpGenerator.secondsRemaining(entry, at: 60) == 30)
    }

    @Test func refusesUnusableSecrets() {
        #expect(!TotpGenerator.isUsableSecret("A"))
        #expect(!TotpGenerator.isUsableSecret("01"))
        #expect(!TotpGenerator.isUsableSecret(""))
        #expect(TotpGenerator.isUsableSecret("jbsw y3dp ehpk 3pxp jbsw y3dp ehpk 3pxp ===="))
        #expect(throws: TotpError.self) { try TotpEntry(title: "t", secretBase32: "A") }
        #expect(throws: TotpError.self) { try TotpEntry(title: " ", secretBase32: "JBSWY3DP") }
        #expect(throws: TotpError.self) { try TotpEntry(title: "t", secretBase32: "JBSWY3DP", digits: 9) }
    }
}

@MainActor
struct TotpUriParserTests {
    @Test func parsesIssuerLabelAndParameters() throws {
        let entry = try TotpUriParser.parse(
            "otpauth://totp/ACME%20Co:ada@example.com?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=ACME%20Co&algorithm=SHA512&digits=8&period=60"
        )
        #expect(entry.title == "ACME Co (ada@example.com)")
        #expect(entry.issuer == "ACME Co")
        #expect(entry.algorithm == .sha512)
        #expect(entry.digits == 8)
        #expect(entry.periodSeconds == 60)
    }

    @Test func labelWithoutColon() throws {
        #expect(try TotpUriParser.parse("otpauth://totp/ada?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=ACME").title == "ACME (ada)")
        #expect(try TotpUriParser.parse("otpauth://totp/ACME?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=acme").title == "ACME")
        #expect(try TotpUriParser.parse("otpauth://totp/?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP").title == "Account")
    }

    @Test func suppliedParametersMustBeSupported() throws {
        let base = "otpauth://totp/a?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"
        for bad in ["&algorithm=SHA3", "&algorithm=MD5", "&digits=abc", "&digits=9", "&digits=0", "&period=abc", "&period=-30", "&period=0", "&digits", "&period", "&algorithm", "&digits=", "&algorithm="] {
            #expect(throws: TotpError.self) { try TotpUriParser.parse(base + bad) }
        }
        let defaults = try TotpUriParser.parse(base)
        #expect(defaults.algorithm == .sha1 && defaults.digits == 6 && defaults.periodSeconds == 30)
        #expect(try TotpUriParser.parse(base + "&algorithm=sha256").algorithm == .sha256)
    }

    @Test func refusesOtherSchemesHotpAndMissingSecret() {
        #expect(throws: TotpError.self) { try TotpUriParser.parse("https://example.com") }
        #expect(throws: TotpError.self) { try TotpUriParser.parse("otpauth://hotp/a?secret=JBSWY3DP&counter=1") }
        #expect(throws: TotpError.self) { try TotpUriParser.parse("otpauth://totp/a?issuer=x") }
    }
}

@MainActor
struct TotpKeyStrengthTests {
    @Test func importsEnforceDecodedBytesForEveryAlgorithm() throws {
        for algorithm in TotpEntry.Algorithm.allCases {
            // 24 Base32 characters carry 15 bytes; 26 carry 16 bytes.
            for secret in ["", "A", "MY", String(repeating: "A", count: 24)] {
                #expect(throws: TotpError.self) {
                    try TotpEntry(title: "Account", secretBase32: secret, algorithm: algorithm)
                }
                #expect(throws: TotpError.self) {
                    try TotpUriParser.parse("otpauth://totp/Account?secret=\(secret)&algorithm=\(algorithm.rawValue)")
                }
            }
            let floor = String(repeating: "A", count: 26)
            #expect(try TotpGenerator.base32Decode(floor).count == 16)
            let entry = try TotpEntry(title: "Account", secretBase32: floor, algorithm: algorithm)
            #expect(try TotpGenerator.code(entry, at: 59).count == 6)
            #expect(try TotpUriParser.parse("otpauth://totp/Account?secret=\(floor)&algorithm=\(algorithm.rawValue)").algorithm == algorithm)
        }
    }

    @Test func generationRefusesWeakMutableOrDecodedEntries() throws {
        for algorithm in TotpEntry.Algorithm.allCases {
            var entry = try TotpEntry(title: "Account", secretBase32: String(repeating: "A", count: 26), algorithm: algorithm)
            for secret in ["MY", String(repeating: "A", count: 24)] {
                entry.secretBase32 = secret
                #expect(throws: TotpError.self) { try TotpGenerator.code(entry, at: 59) }
                let decoded = try JSONDecoder().decode(TotpEntry.self, from: JSONEncoder().encode(entry))
                #expect(decoded == entry)
                #expect(throws: TotpError.self) { try TotpGenerator.code(decoded, at: 59) }
            }
        }
    }

    @Test func legacyRecordsStayReadableBesideStrongRecords() throws {
        let legacy = Data(#"{"id":"legacy","title":"Old Account","secretBase32":"MY","digits":6,"periodSeconds":30,"algorithm":"SHA1","issuer":"Example","url":"https://example.invalid","notes":"Keep recovery codes"}"#.utf8)
        let old = try JSONDecoder().decode(TotpEntry.self, from: legacy)
        let strong = try TotpEntry(title: "Strong", secretBase32: String(repeating: "A", count: 26))
        var records = try JSONDecoder().decode([TotpEntry].self, from: JSONEncoder().encode([old, strong]))
        #expect(records == [old, strong])
        records[0].title = "Renamed"
        records[0].notes = "Updated notes"
        let saved = try JSONDecoder().decode([TotpEntry].self, from: JSONEncoder().encode(records))
        #expect(saved[0].secretBase32 == old.secretBase32 && saved[0].id == old.id)
        #expect(saved[0].issuer == old.issuer && saved[0].url == old.url)
        #expect(saved[0].title == "Renamed" && saved[0].notes == "Updated notes")
        #expect(throws: TotpError.self) { try TotpGenerator.code(saved[0], at: 59) }
        #expect(try TotpGenerator.code(saved[1], at: 59).count == 6)
    }
}
