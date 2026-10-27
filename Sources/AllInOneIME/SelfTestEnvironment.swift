import AllInOneIMECore
import AppKit

/// What the self-test runs against, and what it does when this Mac can't give a section what it needs at the moment.
///
/// Its config is a file of its own in its own folder (`Config.selfTestURL`), never the user's: Amazon Bedrock with the
/// AWS profile and region from the user's config if set there (else the app's defaults), and nothing else of theirs, so
/// the provider, model, languages or styles they picked change no check. Without Bedrock credentials for that profile
/// the live Bedrock checks are skipped, not failed.
///
/// Secure input held by another process (a password field) stops composing in the fake field when its owner can't be
/// told, and refuses every request: before a section that composes, the self-test waits a while for it to go, then
/// skips that section's checks. A locked screen ends the run at once (`endIfScreenLocked`). What this Mac can't give a
/// check (credentials, the on-device model, the Electron harness …) skips it, counted and said why (`skip`).
///
/// The summary counts passed, failed and skipped checks, and its exit status (`summary`): 0 when every check ran and
/// passed, 1 when any failed, 2 when none failed but some were skipped or couldn't run. Its last line is for scripts:
/// `SELFTEST-RESULT {"passed":N,"failed":N,"skipped":N,"status":"pass|fail|incomplete"}`.
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
    static let secureInputOn = "secure input (a password field?)"
    static let screenLocked = "the screen is locked"
    static let noOnDeviceModel = "the on-device model isn't available here"
    static let noElectronHarness = "no Electron harness (ALLINONEIME_ELECTRON_HARNESS)"
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
        // As far as the files tell (static keys found, an SSO sign-in still good …): nothing run or fetched to know it.
        bedrockReady = AWSCredentialResolver.shared.status(profile: config.awsProfile).isReady
        check(written, "the self-test's own config: \(url.path) (Bedrock, profile \(config.awsProfile), region "
              + "\(config.region ?? "the profile's"); \(bedrockReady ? "credentials found" : "no credentials: live Bedrock checks skipped"))")
    }

    /// Counts what this Mac can't run now (a check, or a part of a section that can't start) as skipped, saying why:
    /// skipped is never passed (`summary`).
    static func skip(_ what: String, _ reason: String) {
        print("– \(what) — skipped: \(reason)")
        skipped[reason, default: 0] += 1
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
    /// sections don't wait again. A locked screen (or one locked while waiting) ends the run instead.
    static func secureInputGoes() -> Bool {
        guard SecureInput.isOn else {
            secureInputStayed = false
            return true
        }
        endIfScreenLocked()
        guard !secureInputStayed else { return false }
        print("  secure input is on (\(SecureInput.ownerDescription())): waiting up to \(Int(secureInputWait)) s for it to go")
        let gone = pump(timeout: secureInputWait) { !SecureInput.isOn || isScreenLocked }
        endIfScreenLocked()
        secureInputStayed = !gone
        return gone
    }

    /// Whether this login session's screen is locked, as CoreGraphics tells it.
    static var isScreenLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (session?["CGSSessionScreenIsLocked"] as? Bool) == true || (session?["CGSSessionScreenIsLocked"] as? Int) == 1
    }

    /// A locked screen ends the run here (at its start, or as a section that composes finds it locked): nothing that
    /// types can run until it's unlocked, so the run can't be complete, and going on would only wait on secure input
    /// section after section. What wasn't run counts as one skipped check; the summary ends it (2, or 1 after a failure).
    static func endIfScreenLocked() {
        guard isScreenLocked else { return }
        print("  the screen is locked: the run ends here (unlock it and run again)")
        skip("everything from here on", screenLocked)
        exit(summary())
    }

    /// One self-test at a time on this Mac: two at once (from two checkouts, say) share the output folder's files (its
    /// Rime user folder, its config files) and this session's windows, focus and pasteboard, and fail each other's checks
    /// at random. Held until the process exits; a second run waits for the first, saying so.
    static let lockURL = URL(fileURLWithPath: "/tmp/allinoneime-selftest.lock")

    static func waitForOtherSelfTests() {
        let fd = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o666)
        guard fd >= 0 else { return }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            var buffer = [UInt8](repeating: 0, count: 32)
            let count = pread(fd, &buffer, buffer.count, 0)
            let pid = count > 0 ? String(decoding: buffer[..<count], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : "?"
            print("  another self-test is running on this Mac (pid \(pid)): waiting for it to finish")
            fflush(stdout)
            flock(fd, LOCK_EX)
        }
        ftruncate(fd, 0)
        let pid = "\(getpid())\n"
        _ = pid.withCString { pwrite(fd, $0, strlen($0), 0) }
    }

    /// The last lines: passed, failed and skipped checks, each reason for a skip, the outcome, and the same as one line of
    /// JSON for scripts. The exit status: 0 when every check ran and passed, 1 when any failed, 2 when none failed but
    /// some were skipped or couldn't run (never a pass); a run that checked nothing that composes or asks the AI says so.
    static func summary() -> Int32 {
        let skippedCount = skipped.values.reduce(0, +)
        let counts = "\(passed) passed, \(failures) failed, \(skippedCount) skipped"
        let reasons = skipped.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        let status: Int32
        if failures > 0 {
            print("SELFTEST FAILED (\(failures)): \(counts)\(reasons.isEmpty ? "" : " (\(reasons))")")
            status = 1
        } else if skippedCount == 0 {
            print("SELFTEST PASSED: \(counts)")
            status = 0
        } else if checkedWithNeeds == 0 {
            print("Everything that composes in the field or asks the AI was skipped (\(reasons)): this run doesn't show the input method works.")
            print("SELFTEST SKIPPED: \(counts) (\(reasons))")
            status = 2
        } else {
            print("SELFTEST INCOMPLETE: \(counts) (\(reasons))")
            status = 2
        }
        let outcome = status == 0 ? "pass" : status == 1 ? "fail" : "incomplete"
        print(#"SELFTEST-RESULT {"passed":\#(passed),"failed":\#(failures),"skipped":\#(skippedCount),"status":"\#(outcome)"}"#)
        return status
    }
}
