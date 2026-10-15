import Foundation
import Testing
@testable import AllInOneIMECore

/// The key detector against random secrets made here (a seeded generator: the same strings every run) and against
/// ordinary text that must stay. No real key is written in this file: bodies are generated.
struct RedactionKeyTests {
    let on = RedactionSettings(enabled: true)

    /// SplitMix64.
    struct Seeded {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func string(_ count: Int, from alphabet: String) -> String {
            let chars = Array(alphabet)
            return String((0..<count).map { _ in chars[Int(next() % UInt64(chars.count))] })
        }
    }

    static let lower = "abcdefghijklmnopqrstuvwxyz", upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ", digits = "0123456789"
    static let shapes: [(name: String, length: Int, alphabet: String)] = [
        ("lowercase+digits", 32, lower + digits),
        ("hex", 40, digits + "abcdef"),
        ("mixed-case+digits", 32, lower + upper + digits),
        ("base64url", 43, lower + upper + digits + "-_"),
        ("base64", 40, lower + upper + digits + "+/"),
    ]

    /// Whether the keys found in `text` cover all of `secret` in it.
    func hidden(_ secret: String, in text: String) -> Bool {
        let range = (text as NSString).range(of: secret)
        let keys = Redaction.find(text, settings: on).filter { $0.kind == .key }.map(\.range)
        return (range.location..<NSMaxRange(range)).allSatisfy { i in keys.contains { NSLocationInRange(i, $0) } }
    }

    @Test func randomSecretsNeverLeak() {
        for (index, shape) in Self.shapes.enumerated() {
            var rng = Seeded(state: 0xC0FFEE + UInt64(index) * 7919)
            var leaked: [String] = []
            for _ in 0..<500 {
                let secret = rng.string(shape.length, from: shape.alphabet)
                if !hidden(secret, in: "the token: \(secret) is new") { leaked.append(secret) }
            }
            print("leaks \(shape.name) \(shape.length): \(leaked.count)/500")
            #expect(leaked.isEmpty, "\(shape.name): \(leaked.count)/500 sent, e.g. \(leaked.prefix(3))")
        }
    }

    @Test func knownPrefixesAndBlocks() {
        var rng = Seeded(state: 42)
        let alnum = Self.lower + Self.upper + Self.digits
        let keys = [
            "sk-" + rng.string(48, from: alnum),
            "sk-proj-" + rng.string(40, from: alnum + "_-"),
            "sk-\u{61}nt-api03-" + rng.string(60, from: alnum + "_-"),
            "sk_live_" + rng.string(24, from: Self.lower + Self.upper),  // letters only: no digit needed
            "rk_test_" + rng.string(24, from: alnum),
            "ghp_" + rng.string(36, from: alnum),
            "xoxb-" + rng.string(11, from: Self.digits) + "-" + rng.string(24, from: alnum),
            "AKIA" + rng.string(16, from: Self.upper + Self.digits),
            "AIza" + rng.string(35, from: alnum + "_-"),
            "eyJ" + rng.string(20, from: alnum) + ".eyJ" + rng.string(30, from: alnum) + "." + rng.string(43, from: alnum + "_-"),
        ]
        for key in keys { #expect(hidden(key, in: "use \(key) now"), "\(key.prefix(8))…") }
        // A PEM block, built from random lines.
        let lines = (0..<4).map { _ in rng.string(64, from: alnum + "+/") }
        let pem = "-----B\u{45}GIN RSA PRIVATE KEY-----\n" + lines.joined(separator: "\n") + "\n-----END RSA PRIVATE KEY-----"
        #expect(hidden(pem, in: "key:\n" + pem + "\nthanks"))
    }

    @Test func secretsWithSlashesAndInLinks() {
        var rng = Seeded(state: 7)
        let alnum = Self.lower + Self.upper + Self.digits
        for _ in 0..<50 {
            // An AWS-style secret (40 base64 characters with "/" and "+").
            var chars = Array(rng.string(40, from: alnum))
            chars[Int(rng.next() % 12) + 2] = "/"
            chars[Int(rng.next() % 12) + 20] = "+"
            let secret = String(chars)
            #expect(hidden(secret, in: "aws_secret_access_key = \(secret)"), "\(secret.prefix(6))…")
            // A webhook link: the path's words stay, the secret parts go.
            let hook = rng.string(13, from: Self.lower + Self.upper) + "/" + rng.string(7, from: Self.upper + Self.digits) + "/"
                + rng.string(18, from: Self.lower + Self.upper)
            let link = "https://hooks.slack.com/services/" + hook
            #expect(hidden(hook, in: "post to \(link) please"), "\(hook.prefix(6))…")
            #expect(!Redaction.find(link, settings: on).contains { (link as NSString).substring(with: $0.range).contains("services") })
            // Short random pieces joined by "/".
            let pieces = [10, 10, 10, 11].map { rng.string($0, from: alnum) }.joined(separator: "/")
            #expect(hidden(pieces, in: "secret \(pieces) ok"), "\(pieces.prefix(6))…")
        }
    }

    @Test func ordinaryTextIsNotHidden() {
        let texts = [
            "convertUTF8ToUTF16AndBack42", "getHTTP2ResponseForURLv3Id", "C++/CLI/WinRT/Win32/x64/Release",
            "wo3xiang3ming2tian1qu4kai1hui4", "ni3hao3ma5", "zhong1guo2ren2min2yin2hang2",
            "getUserAccountSettingsForCurrentSession", "AbstractSingletonProxyFactoryBean", "parseJSONResponseFromServer",
            "/Users/imac/workspace/AllInOneIME-custom-commands/Sources/AllInOneIMECore/RedactionWords.swift",
            "~/Library/Application Support/AllInOneIME/settings.json",
            "https://github.com/MicroZ-LLC/AllInOneIME/releases/download/v0.6.3/AllInOneIME-0.6.3.dmg",
            "https://developer.apple.com/documentation/foundation/nsregularexpression/matching-strings",
            "internationalization_and_localization", "pneumonoultramicroscopicsilicovolcanoconiosis",
            "antidisestablishmentarianism", "my-feature-branch-2024-10-14", "very_long_function_name_v2",
            "QuarterlyBusinessReview2024Q3", "use sk-learn-is-a-python-library", "user_profile_v2_settings_cache",
            "AWS_SECRET_ACCESS_KEY_ID_2024", "release-0.6.3/redact-sensitive", "feature/add-privacy-settings-page",
            "on 2024-10-14 at 12:30:45", "version 1.2.3 and v2.0.1", "it costs $1,299.99", "order #12345678",
            "build 20241014.1", "xoxo-hugs-and-kisses",
        ]
        for text in texts { #expect(Redaction.find("see \(text) here", settings: on).isEmpty, "\(text)") }
    }

    @Test func hexIsAlwaysAKey() {
        var rng = Seeded(state: 99)
        for _ in 0..<20 {
            let hex = rng.string(32, from: Self.digits + "abcdef")
            guard hex.contains(where: \.isNumber), hex.contains(where: \.isLetter) else { continue }
            #expect(hidden(hex, in: "sha \(hex)"))
        }
        // All digits or all letters isn't.
        #expect(Redaction.find("n " + String(repeating: "1234567890", count: 4), settings: on).filter { $0.kind == .key }.isEmpty)
    }
}
