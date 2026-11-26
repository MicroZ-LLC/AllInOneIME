import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// `ProcessOutput`, what `@tasks` runs `claude agents` through: each program's end is seen (its termination handler, not
/// `waitUntilExit` on a dispatch thread, which missed about one exit in ten), with what it printed on both pipes and its
/// status; one past its time is ended, and the call fails saying it timed out (or, gathered, gives what it printed by
/// then).
struct ProcessOutputTests {
    /// `ProcessOutput.run` on a dispatch thread, as `AgentMonitor` runs it; nil when it hasn't returned within `within`
    /// seconds.
    func run(_ arguments: [String], timeout: TimeInterval = 10,
             within: TimeInterval = 10) async -> Result<ProcessOutput.Result, any Error>? {
        let result = Locked<Result<ProcessOutput.Result, any Error>?>(initialState: nil)
        DispatchQueue.global().async {
            let ran = Result {
                try ProcessOutput.run(URL(fileURLWithPath: "/bin/sh"), ["-c"] + arguments, timeout: timeout,
                                      processes: FoundationProcessLauncher())
            }
            result.withLock { $0 = ran }
        }
        let deadline = Date().addingTimeInterval(within)
        while Date() < deadline {
            if let ran = result.withLock({ $0 }) { return ran }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    /// How `result` failed (nil: it didn't).
    func failure(_ result: Result<ProcessOutput.Result, any Error>?) -> (any Error)? {
        if case let .failure(error) = result { return error }
        return nil
    }

    @Test func everyProgramsEndIsSeenWithWhatItPrinted() async {
        for attempt in 0..<60 {
            let result = await run(["printf out; printf err >&2; exit 3"])
            #expect((try? result?.get()) == ProcessOutput.Result(status: 3, output: Data("out".utf8), errors: Data("err".utf8)),
                    "attempt \(attempt): \(String(describing: result))")
            if result == nil { break }
        }
    }

    /// Past its time, it is ended, and the call fails as timed out (`@tasks` says so), not as a run that printed nothing.
    @Test func aProgramPastItsTimeIsEndedAndTimesOut() async {
        let started = Date()
        let result = await run(["sleep 30"], timeout: 0.5, within: 10)
        #expect(result != nil)
        let error = failure(result)
        #expect(error as? ProcessOutput.TimedOut == ProcessOutput.TimedOut(program: "sh", seconds: 0.5),
                "\(String(describing: result))")
        let said = (error as? LocalizedError)?.errorDescription ?? ""
        #expect(said.contains("sh") && (said.contains("timed out") || said.contains("超时")), "\(said)")
        #expect(Date().timeIntervalSince(started) < 10)
    }

    /// One that ignores SIGTERM (and keeps its pipes open) is killed with what it started, and the call returns (it
    /// took under a second; the bound is `aProgramPastItsTimeIsEndedAndTimesOut`'s, for a loaded test run), timed out.
    @Test func ignoredTermAndOpenPipesStillReturn() async {
        let started = Date()
        let result = await run(["trap '' TERM; while :; do sleep 1; done"], timeout: 0.2, within: 10)
        #expect(failure(result) as? ProcessOutput.TimedOut == ProcessOutput.TimedOut(program: "sh", seconds: 0.2),
                "\(String(describing: result))")
        #expect(Date().timeIntervalSince(started) < 10)
    }

    /// `body` on a thread of its own (it blocks), awaited.
    func inBackground<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            Thread { continuation.resume(returning: body()) }.start()
        }
    }

    /// `input` goes to its standard input, more than a pipe holds too, while what it prints is read.
    @Test func itsInputIsWrittenWhileItsOutputIsRead() async throws {
        let input = Data(repeating: UInt8(ascii: "x"), count: 200_000)
        let result = await inBackground {
            Result { try ProcessOutput.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "cat"], input: input, timeout: 10,
                                           processes: FoundationProcessLauncher()) }
        }
        #expect(try result.get() == ProcessOutput.Result(status: 0, output: input, errors: Data()))
    }

    /// Gathered, one past its time that ignores SIGTERM is killed all the same, and what it printed before is kept.
    @Test func gatheredPastItsTimeKeepsWhatItPrinted() async throws {
        let started = Date()
        let gathered = await inBackground {
            Result { try ProcessOutput.gather(URL(fileURLWithPath: "/bin/sh"),
                                              ["-c", "printf ready; trap '' TERM; while :; do sleep 1; done"], timeout: 0.5,
                                              processes: FoundationProcessLauncher()) }
        }
        let run = try gathered.get()
        #expect(run.timedOut && run.result.output == Data("ready".utf8), "\(run)")
        #expect(Date().timeIntervalSince(started) < 10)
    }

    /// Something it left running in the background holds its pipes open after it ended (a login shell's startup files
    /// can): the run doesn't wait for that, and has what it printed.
    @Test func whatItLeftRunningDoesntHoldTheRunUp() async throws {
        // The job marks its end, 5 s after the program's: however slow a loaded Mac starts the program, the run is over
        // well before that.
        let ended = TestScratch.temporary("process-output-job-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: ended) }
        let result = await inBackground {
            Result { try ProcessOutput.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "printf done; (sleep 5; : > '\(ended.path)') & exit 0"],
                                           timeout: 30, processes: FoundationProcessLauncher()) }
        }
        #expect(try result.get() == ProcessOutput.Result(status: 0, output: Data("done".utf8), errors: Data()))
        #expect(!FileManager.default.fileExists(atPath: ended.path), "waited for the background job")
    }
}
