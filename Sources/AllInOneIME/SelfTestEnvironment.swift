import AllInOneIMECore
import AppKit

/// What the self-test runs against, and what it does when this Mac can't give a section what it needs at the moment.
///
/// Its config is a file of its own in its own folder (`Config.selfTestURL`), never the user's: Amazon Bedrock with the
/// AWS profile and region from the user's config if set there (else the app's defaults), and nothing else of theirs, so
/// the provider, model, languages or styles they picked change no check. Without Bedrock credentials for that profile
/// the live Bedrock checks are skipped, not failed.
///
/// Secure input held by another process (the lock screen, a password field) stops composing in the fake field when its
/// owner can't be told, and refuses every request: before a section that composes, the self-test waits a while for it
/// to go, then skips that section's checks. The summary counts passed, failed and skipped checks; only failures fail
/// the run, and a run that checked nothing that composes or asks the AI says so, never that it passed.
extension SelfTest {
    /// What a section needs from this Mac.
    struct Needs: OptionSet {
        let rawValue: Int
        /// Keys composed in the fake field and requests sent: secure input held elsewhere stops both.
        static let composing = Needs(rawValue: 1 << 0)
        /// Live Amazon Bedrock requests: credentials for the self-test config's AWS profile.
        static let bedrock = Needs(rawValue: 1 << 1)
    }

    static let noCredentials = "no Bedrock credentials"
    static let secureInputOn = "secure input (screen locked?)"
    /// How long a section waits for secure input held elsewhere to go before its checks are skipped.
    static let secureInputWait: TimeInterval = 30

    /// Whether the self-test config's AWS profile has credentials (`useOwnConfig`).
    static var bedrockReady = false
    /// What the checks from here on need (`section`, `needing`), and why they are skipped (nil: they count).
    static var needs: Needs = []
    static var skipping: String?
    static var passed = 0
    /// Skipped checks by reason.
    static var skipped: [String: Int] = [:]
    /// Checks counted (passed or failed) that needed something: none while some were skipped means nothing that
    /// matters ran.
    static var checkedWithNeeds = 0
    /// Secure input was still on when a section stopped waiting for it: the next ones don't wait again while it stays.
    static var secureInputStayed = false
    /// Gives up what a skipped part left composing (a request refused, or failed for want of credentials) before checks
    /// that count again (`run` sets it: Esc until nothing is composing).
    static var giveUp: () -> Void = {}

    /// Writes the self-test's config into `directory` and points `Config.defaultURL` at it for the rest of the run:
    /// Bedrock, with `awsProfile` and `region` from the user's config if set (the only keys read from it), else the
    /// app's defaults; the jargon list in `directory` too (there is none), never the user's. Says whether the profile
    /// has credentials.
    static func useOwnConfig(in directory: URL) {
        let user = (try? Data(contentsOf: Config.userURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        func value(_ key: String) -> String? {
            (user[key] as? String).map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        var config = Config.default
        config.provider = .bedrock
        config.awsProfile = value("awsProfile") ?? Config.default.awsProfile
        config.region = value("region") ?? Config.default.region
        config.jargonFile = directory.appendingPathComponent("selftest-jargon.txt").path
        let url = directory.appendingPathComponent("selftest-config.json")
        let written = (try? config.write(to: url)) != nil
        Config.selfTestURL = url
        bedrockReady = (try? AWSSharedConfig.load(profile: config.awsProfile)) != nil
        check(written, "the self-test's own config: \(url.path) (Bedrock, profile \(config.awsProfile), region "
              + "\(config.region ?? "the profile's"); \(bedrockReady ? "credentials found" : "no credentials: live Bedrock checks skipped"))")
    }

    /// Starts a section: its title, and what its checks need (`needing`).
    static func section(_ title: String, needs: Needs = []) {
        print("— \(title)")
        needing(needs, announce: true)
    }

    /// What the checks from here on need; the checks are skipped when this Mac can't give it now. Returns what they
    /// needed before, to go back to after a part of a section that needs more.
    @discardableResult
    static func needing(_ new: Needs, announce: Bool = false) -> Needs {
        let before = needs
        needs = new
        let reason: String? = if new.contains(.bedrock), !bedrockReady {
            noCredentials
        } else if new.contains(.composing), !secureInputGoes() {
            secureInputOn
        } else {
            nil
        }
        if let reason, announce || reason != skipping { print("  skipped: \(reason)") }
        if skipping != nil, reason == nil { giveUp() }
        skipping = reason
        return before
    }

    /// Whether secure input is off, or goes within `secureInputWait` seconds; while it stays on after a wait, the next
    /// sections don't wait again (a locked screen stays locked).
    static func secureInputGoes() -> Bool {
        guard SecureInput.isOn else {
            secureInputStayed = false
            return true
        }
        guard !secureInputStayed else { return false }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = (session?["CGSSessionScreenIsLocked"] as? Bool) == true || (session?["CGSSessionScreenIsLocked"] as? Int) == 1
        print("  secure input is on (\(SecureInput.ownerDescription())\(locked ? ", the screen is locked" : "")): "
              + "waiting up to \(Int(secureInputWait)) s for it to go")
        let gone = pump(timeout: secureInputWait) { !SecureInput.isOn }
        secureInputStayed = !gone
        return gone
    }

    /// The last lines: passed, failed and skipped checks. Only failures fail the run; skipped checks never make it
    /// pass, and a run that checked nothing that composes or asks the AI says so.
    static func summary() -> Int32 {
        let skippedCount = skipped.values.reduce(0, +)
        let counts = "\(passed) passed, \(failures) failed, \(skippedCount) skipped"
        let reasons = skipped.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        if failures > 0 {
            print("SELFTEST FAILED (\(failures)): \(counts)\(reasons.isEmpty ? "" : " (\(reasons))")")
            return 1
        }
        if skippedCount == 0 {
            print("SELFTEST PASSED: \(counts)")
        } else if checkedWithNeeds == 0 {
            print("Everything that composes in the field or asks the AI was skipped (\(reasons)): this run doesn't show the input method works.")
            print("SELFTEST SKIPPED: \(counts) (\(reasons))")
        } else {
            print("SELFTEST INCOMPLETE: \(counts) (\(reasons))")
        }
        return 0
    }
}
