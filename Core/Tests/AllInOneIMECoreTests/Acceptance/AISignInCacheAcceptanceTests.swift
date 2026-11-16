import AllInOneIMECore
import AllInOneIMETestSupport
import Foundation
import Testing

// #121: Settings → AI shows every choice as a card. The acceptance tests of its CLI checks, written from the issue and
// the integrator's contract by an author other than the implementation's (whose changes don't edit them).
//
// "With the cards always shown, every CLI is looked at when the AI page is shown, using the cache that exists today:
// signed-in results kept until quit, the others for a minute. Showing the page again within that time runs nothing."
// The contract: the page looks through `ClaudeSessionManager.checkAvailability()` without `force`: "a signed-in result
// kept until quit, the others for `ClaudeSessionManager.recheckInterval` (60 s)".
//
// Seen here, on one CLI's manager with a launcher of the test's (no program of this Mac's is run) and a clock of the
// test's (`uptime`):
//   1. "Showing the page twice within a minute starts no CLI process the second time", whatever the first look found
//      (signed in, not signed in, not installed, a program that won't launch), and two looks at once run one check.
//   2. A signed-in result is kept beyond the minute ("until quit"): no process, hours later.
//   3. A result that isn't signed in is looked at again once the minute has passed, and only then; what the second look
//      finds is what is told.
// Not seen here: that the AI page asks every CLI's manager as it is shown (`SettingsModel.aiPageShown`: the input
// method's own code), and that nothing is asked at launch or while typing.

@Suite(.serialized)
struct AISignInCacheAcceptanceTests {
    /// The sign-in checks started, each ended by the test: a launcher in place of the Mac's, so that no CLI runs.
    final class Checks: ClaudeSessionLauncher, @unchecked Sendable {
        final class Check: ClaudeSessionProcess, @unchecked Sendable {
            let arguments: [String]
            private let exited: @Sendable (Int32, String) -> Void
            private let lock = NSLock()
            private var ended = false

            init(arguments: [String], exited: @escaping @Sendable (Int32, String) -> Void) {
                self.arguments = arguments
                self.exited = exited
            }

            func send(_ line: Data) throws {}
            var isRunning: Bool { lock.withLock { !ended } }
            func terminate() { exit(143) }

            /// The command ends with `status` (told once).
            func exit(_ status: Int32) {
                let first = lock.withLock { () -> Bool in
                    defer { ended = true }
                    return !ended
                }
                if first { exited(status, "") }
            }
        }

        private let lock = NSLock()
        private var started: [Check] = []
        private var failure: ClaudeSessionError?

        /// The checks started so far, in order.
        var checks: [Check] { lock.withLock { started } }
        var count: Int { checks.count }
        /// What starting the program throws (not installed, can't be launched); nil: it starts.
        var fails: ClaudeSessionError? {
            get { lock.withLock { failure } }
            set { lock.withLock { failure = newValue } }
        }
        /// The starts asked for, whether the program started or not.
        private var asked = 0
        var starts: Int { lock.withLock { asked } }

        func start(_ arguments: [String], in directory: URL, output: @escaping @Sendable (Data) -> Void,
                   exited: @escaping @Sendable (Int32, String) -> Void) throws -> any ClaudeSessionProcess {
            let failure = lock.withLock { () -> ClaudeSessionError? in
                asked += 1
                return self.failure
            }
            if let failure { throw failure }
            let check = Check(arguments: arguments, exited: exited)
            lock.withLock { started.append(check) }
            return check
        }

        func installed() -> Bool { fails != .notInstalled }
        // Nothing of the test runner's environment (a key, a sign-in) tells the check anything.
        func startEnvironment() -> [String: String] { [:] }
    }

    /// The test's clock: seconds since the Mac started, as `uptime` tells the manager.
    final class Uptime: @unchecked Sendable {
        private let lock = NSLock()
        private var seconds: TimeInterval = 1000
        var now: TimeInterval { lock.withLock { seconds } }
        func pass(_ more: TimeInterval) { lock.withLock { seconds += more } }
    }

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ai-sign-in-cache-\(UUID().uuidString)")
    let checks = Checks()
    let uptime = Uptime()

    /// Kiro CLI's manager (its sign-in is its `whoami`'s exit status: 0 signed in), with the test's launcher and clock.
    func manager() -> ClaudeSessionManager {
        let uptime = uptime
        return ClaudeSessionManager(backend: ACPBackend.kiro, launcher: checks, store: ClaudeSessionStore(directory: folder),
                                    userSettings: { nil }, uptime: { uptime.now })
    }

    /// A look as the AI page looks (no `force`), which has to start check number `number`; it ends with `status`.
    func look(_ session: ClaudeSessionManager, starting number: Int, exit status: Int32) async throws -> ClaudeSession.Availability {
        let look = Task { await session.checkAvailability() }
        let started = await Timing.eventually { checks.count == number }
        #expect(started, "check \(number) wasn't started: \(checks.count) started")
        try #require(checks.checks.last).exit(status)
        return await look.value
    }

    /// A look that has to start nothing: answered from what was found before.
    func lookAgain(_ session: ClaudeSessionManager) async -> ClaudeSession.Availability {
        let before = checks.starts
        let found = await session.checkAvailability()
        #expect(checks.starts == before, "a look within the cache's time started a sign-in check")
        return found
    }

    @Test func theIntervalIsAMinute() {
        #expect(ClaudeSessionManager.recheckInterval == 60)
    }

    /// "Showing the page twice within a minute starts no CLI process the second time": the CLI found not signed in.
    @Test func aSecondLookWithinAMinuteStartsNoCheckWhenNotSignedIn() async throws {
        let session = manager()
        #expect(try await look(session, starting: 1, exit: 1) == .signedOut)
        #expect(await lookAgain(session) == .signedOut)
        uptime.pass(30)
        #expect(await lookAgain(session) == .signedOut)
        uptime.pass(29)  // 59 s after the look
        #expect(await lookAgain(session) == .signedOut)
        #expect(checks.count == 1 && checks.starts == 1)
        #expect(session.availability == .signedOut)
    }

    /// The same, the CLI found signed in.
    @Test func aSecondLookWithinAMinuteStartsNoCheckWhenSignedIn() async throws {
        let session = manager()
        #expect(try await look(session, starting: 1, exit: 0) == .ready)
        #expect(await lookAgain(session) == .ready)
        uptime.pass(59)
        #expect(await lookAgain(session) == .ready)
        #expect(checks.count == 1 && checks.starts == 1)
    }

    /// The same, the CLI not on this Mac, or its program there but not launching: starting it isn't tried again either.
    @Test(arguments: [ClaudeSessionError.notInstalled, .cannotLaunch("not executable")])
    func aSecondLookWithinAMinuteTriesNoStartWhenTheProgramDidNotStart(_ failure: ClaudeSessionError) async throws {
        checks.fails = failure
        let session = manager()
        let found = await session.checkAvailability()
        #expect(found == (failure == .notInstalled ? .notInstalled : .cannotStart))
        #expect(checks.starts == 1)
        uptime.pass(59)
        #expect(await lookAgain(session) == found)
        #expect(checks.starts == 1 && checks.count == 0)
    }

    /// The page shown twice at once (two looks before the first check ended): one check, both told what it found.
    @Test func twoLooksAtOnceRunOneCheck() async throws {
        let session = manager()
        let first = Task { await session.checkAvailability() }
        #expect(await Timing.eventually { checks.count == 1 })
        let second = Task { await session.checkAvailability() }
        // The second look has nothing to start; given time to, it still hasn't.
        try await Task.sleep(for: .milliseconds(200))
        #expect(checks.starts == 1)
        try #require(checks.checks.first).exit(1)
        #expect(await first.value == .signedOut)
        #expect(await second.value == .signedOut)
        #expect(checks.starts == 1)
    }

    /// "signed-in results kept until quit": no check a minute later, nor hours later.
    @Test func aSignedInResultIsKeptBeyondAMinute() async throws {
        let session = manager()
        #expect(try await look(session, starting: 1, exit: 0) == .ready)
        uptime.pass(61)
        #expect(await lookAgain(session) == .ready)
        uptime.pass(600)
        #expect(await lookAgain(session) == .ready)
        uptime.pass(8 * 3600)
        #expect(await lookAgain(session) == .ready)
        #expect(checks.count == 1 && checks.starts == 1)
        #expect(session.availability == .ready)
    }

    /// "the others for a minute": not signed in, the CLI is looked at again once the minute has passed, and what that
    /// look finds (signed in meanwhile) is told, then kept.
    @Test func aNotSignedInResultIsLookedAtAgainAfterAMinute() async throws {
        let session = manager()
        #expect(try await look(session, starting: 1, exit: 1) == .signedOut)
        uptime.pass(59)
        #expect(await lookAgain(session) == .signedOut)
        uptime.pass(2)  // 61 s after the look
        #expect(try await look(session, starting: 2, exit: 0) == .ready)
        #expect(checks.count == 2)
        // Signed in now: kept.
        uptime.pass(3600)
        #expect(await lookAgain(session) == .ready)
        #expect(checks.count == 2)
    }

    /// Still not signed in at the second look: that result stands for a minute of its own, then a third look runs.
    @Test func eachNotSignedInResultStandsForItsOwnMinute() async throws {
        let session = manager()
        #expect(try await look(session, starting: 1, exit: 1) == .signedOut)
        uptime.pass(61)
        #expect(try await look(session, starting: 2, exit: 1) == .signedOut)
        uptime.pass(59)  // 120 s after the first look, 59 s after the second
        #expect(await lookAgain(session) == .signedOut)
        uptime.pass(2)
        #expect(try await look(session, starting: 3, exit: 1) == .signedOut)
        #expect(checks.count == 3)
    }

    /// A CLI that wasn't installed is looked for again after the minute (installed meanwhile: its sign-in check runs).
    @Test func aNotInstalledResultIsLookedAtAgainAfterAMinute() async throws {
        checks.fails = .notInstalled
        let session = manager()
        #expect(await session.checkAvailability() == .notInstalled)
        #expect(checks.starts == 1)
        uptime.pass(61)
        checks.fails = nil
        #expect(try await look(session, starting: 1, exit: 0) == .ready)
        #expect(checks.starts == 2)
    }
}
