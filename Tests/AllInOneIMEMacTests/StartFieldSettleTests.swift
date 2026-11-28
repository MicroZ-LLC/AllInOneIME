import AllInOneIMETestSupport
import Foundation
import Testing

/// Step 3's wait for an example's two Escapes (#198, PR #206's review): what tells it they are through is the input
/// method's own state (a draft, a panel, a result typed out), an Escape's key up in the app, or the field's text changed,
/// then the field quiet for a moment; else its limit. Nothing of a draft is marked in the field, and the key tap may take
/// both of an Escape's events, so neither "no marked text" nor "both key ups seen" may be waited for. Then a wait stopped
/// (a newer ask, the window closed) never runs. `StartFieldSettle` is in the app's executable, which this target can't
/// import: its source is compiled here with the core into a small program (a real NSTextView, no window), as
/// CandidatePanelPresenceTests does.
@Suite(.serialized)
struct StartFieldSettleTests {
    @Test func anEscapeSeenThenTheFieldQuietSettles() throws {
        try SettleChild.run("escape")
    }

    @Test func noEscapeSeenAndTheFieldUnchangedWaitsUntilTheLimit() throws {
        try SettleChild.run("nothing")
    }

    @Test func theFieldChangedThenQuietSettles() throws {
        try SettleChild.run("changed")
    }

    /// The input method's draft open: waited for while it is, settled once it ends and the field is quiet.
    @Test func aDraftStillOpenIsWaitedForAndOneEndedSettles() throws {
        try SettleChild.run("draft")
    }

    /// A newer ask's `cancel` (or a newer watch): the old wait's `then` never runs.
    @Test func aWaitCancelledOrReplacedNeverRuns() throws {
        try SettleChild.run("cancel")
    }
}

private enum SettleChild {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static func run(_ scenario: String) throws {
        let result = try command(try compiled.get(), [scenario], timeout: 60)
        #expect(result.status == 0 && result.output.contains("SETTLE PASS \(scenario)"), "\(result.output)")
    }

    /// StartFieldSettle.swift and `program`, against the core as `swift build` built it (.build/debug).
    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = TestScratch.temporary("start-field-settle-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let main = scratch.appendingPathComponent("Main.swift")
        try program.write(to: main, atomically: true, encoding: .utf8)
        let sources = [repository.appendingPathComponent("Sources/AllInOneIME/StartFieldSettle.swift").path]
        let executable = scratch.appendingPathComponent("settle")
        let swiftc = try SourceCompiler.compile(repository: repository, sources: sources + [main.path], executable: executable,
                                                parseAsLibrary: true, timeout: 300)
        guard swiftc.status == 0 else { throw ChildError(swiftc.output) }
        return executable
    }

    struct ChildError: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    static func command(_ executable: URL, _ arguments: [String], timeout: TimeInterval) throws -> (status: Int32, output: String) {
        // A file, not a pipe: the output can fill a pipe's buffer.
        let log = TestScratch.temporary("start-field-settle-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: log) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw ChildError("\(executable.lastPathComponent) timed out after \(Int(timeout))s")
        }
        try handle.synchronize()
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }

    static let program = #"""
    import AllInOneIMECore
    import AppKit
    import Foundation

    @MainActor enum Check {
        static var checks = 0
        static var failures = 0
        static func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
            checks += 1
            if !condition {
                failures += 1
                print("FAIL: \(message())")
            }
        }
    }

    typealias Settle = StartFieldSettle

    /// `settled` with the field unchanged ("" throughout) unless `now` is given, nothing open, no sign: each case says
    /// what it changes.
    @MainActor func settled(now: String = "", draftOpen: Bool = false, sinceChange: TimeInterval, sinceEscape: TimeInterval? = nil,
                            sinceDraftEnded: TimeInterval? = nil, elapsed: TimeInterval) -> Bool {
        Settle.settled(start: "", now: now, draftOpen: draftOpen, sinceChange: sinceChange, sinceEscape: sinceEscape,
                       sinceDraftEnded: sinceDraftEnded, elapsed: elapsed)
    }

    /// A watch on a real field, its `then` timed from the watch: nil, never run within `seconds`. `during` is done once,
    /// `after` seconds in.
    @MainActor final class Live {
        let editor = NSTextView()
        var open = false
        private(set) var ranAt: TimeInterval?
        private let began = ProcessInfo.processInfo.systemUptime

        func watch() {
            Settle.watch(editor, draftOpen: { [weak self] in self?.open ?? false }) { [weak self] in
                guard let self else { return }
                ranAt = ProcessInfo.processInfo.systemUptime - began
            }
        }

        /// The app's events and main queue served for `seconds`, `during` done `after` seconds in; the time it was done.
        @discardableResult
        func spin(_ seconds: TimeInterval, after: TimeInterval = 0, during: () -> Void = {}) -> TimeInterval {
            var doneAt: TimeInterval = -1
            while ProcessInfo.processInfo.systemUptime - began < seconds {
                let now = ProcessInfo.processInfo.systemUptime - began
                if doneAt < 0, now >= after {
                    during()
                    doneAt = now
                }
                if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.005), inMode: .default,
                                               dequeue: true) {
                    NSApp.sendEvent(event)
                }
            }
            return doneAt
        }
    }

    @MainActor func escapeKeyUp() {
        let event = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                     isARepeat: false, keyCode: 0x35)
        if let event { NSApp.postEvent(event, atStart: false) } else { Check.expect(false, "no Escape key up made") }
    }

    /// The wait ran `quiet` after `from`, not sooner, and well before the limit.
    @MainActor func ranQuietAfter(_ live: Live, _ from: TimeInterval, _ what: String) {
        guard let ran = live.ranAt else { return Check.expect(false, "\(what): never settled") }
        Check.expect(ran >= from + Settle.quiet - 0.001, "\(what): settled \(ran)s in, before \(from)s + quiet")
        Check.expect(ran < Settle.limit - 0.2, "\(what): settled only at \(ran)s, the limit")
    }

    /// The wait ran at the limit, not sooner.
    @MainActor func ranAtLimit(_ live: Live, _ what: String) {
        guard let ran = live.ranAt else { return Check.expect(false, "\(what): never settled, the limit past") }
        Check.expect(ran >= Settle.limit, "\(what): settled \(ran)s in, before the limit")
    }

    @MainActor enum Scenario {
        static var quiet: TimeInterval { Settle.quiet }
        static var limit: TimeInterval { Settle.limit }

        /// One Escape's key up is enough (the key tap may have taken the other's), once the field is quiet.
        static func escape() {
            Check.expect(settled(sinceChange: 0.4, sinceEscape: quiet, elapsed: 0.4), "an Escape seen, then quiet")
            Check.expect(!settled(sinceChange: 0.4, sinceEscape: quiet - 0.01, elapsed: 0.4), "settled before quiet after the Escape")
            // Quiet from the later of the Escape and the field's last change.
            Check.expect(!settled(now: "@", sinceChange: 0.05, sinceEscape: 0.5, elapsed: 0.6), "settled right after the field changed")
            let live = Live()
            live.watch()
            let at = live.spin(limit + 0.3, after: 0.1) { escapeKeyUp() }
            ranQuietAfter(live, at, "an Escape's key up")
        }

        /// No sign at all: only the limit (an Escape the key tap took, the input method's state not telling).
        static func nothing() {
            Check.expect(!settled(sinceChange: limit - 0.01, elapsed: limit - 0.01), "settled before the limit with no sign")
            Check.expect(settled(sinceChange: limit, elapsed: limit), "not settled at the limit")
            let live = Live()
            live.watch()
            live.spin(limit + 0.3)
            ranAtLimit(live, "no sign")
        }

        /// The text an Escape put in as typed came back: settled once it has stayed for `quiet`.
        static func changed() {
            Check.expect(settled(now: "@abc", sinceChange: quiet, elapsed: 0.3), "the field changed, then quiet")
            Check.expect(!settled(now: "@abc", sinceChange: quiet - 0.01, elapsed: 0.3), "settled before quiet after the change")
            let live = Live()
            live.watch()
            let at = live.spin(limit + 0.3, after: 0.1) { live.editor.string = "@abc" }
            ranQuietAfter(live, at, "the field changed")
        }

        /// The input method's draft (or panel) open: never settled while it is, whatever else came; once it ends, quiet.
        static func draft() {
            Check.expect(!settled(draftOpen: true, sinceChange: 1, sinceEscape: 1, elapsed: 1), "settled with the draft open")
            Check.expect(!settled(now: "@", draftOpen: true, sinceChange: 1, elapsed: 1), "settled with the draft open")
            Check.expect(settled(draftOpen: true, sinceChange: limit, elapsed: limit), "a draft left open held it past the limit")
            Check.expect(settled(sinceChange: 0.5, sinceDraftEnded: quiet, elapsed: 0.5), "the draft ended, then quiet")
            Check.expect(!settled(sinceChange: 0.5, sinceDraftEnded: quiet - 0.01, elapsed: 0.5), "settled before quiet after the draft")
            let open = Live()
            open.open = true
            open.watch()
            open.spin(limit + 0.3, after: 0.1) { escapeKeyUp() }
            ranAtLimit(open, "the draft open, an Escape seen")
            let ending = Live()
            ending.open = true
            ending.watch()
            let at = ending.spin(limit + 0.3, after: 0.1) { ending.open = false }
            ranQuietAfter(ending, at, "the draft ended")
        }

        /// Cancelled, or replaced by a newer watch: its `then` never runs, though the field changed (it would have settled).
        static func cancel() {
            let cancelled = Live()
            cancelled.watch()
            cancelled.editor.string = "@abc"
            Settle.cancel()
            cancelled.spin(limit + 0.3)
            Check.expect(cancelled.ranAt == nil, "a cancelled wait ran")
            let old = Live(), new = Live()
            old.watch()
            old.editor.string = "@abc"
            new.watch()
            new.spin(limit + 0.3, after: 0.05) { new.editor.string = "@x" }
            Check.expect(old.ranAt == nil, "a replaced wait ran")
            Check.expect(new.ranAt != nil, "the newer wait never ran")
        }
    }

    @main struct SettleMain {
        @MainActor static func main() {
            let scenario = CommandLine.arguments.dropFirst().first ?? ""
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            switch scenario {
            case "escape": Scenario.escape()
            case "nothing": Scenario.nothing()
            case "changed": Scenario.changed()
            case "draft": Scenario.draft()
            case "cancel": Scenario.cancel()
            default:
                print("unknown scenario \(scenario)")
                exit(2)
            }
            print("\(Check.failures == 0 ? "SETTLE PASS" : "SETTLE FAIL") \(scenario): \(Check.checks) checks, \(Check.failures) failures")
            exit(Check.failures == 0 ? 0 : 1)
        }
    }
    """#
}
