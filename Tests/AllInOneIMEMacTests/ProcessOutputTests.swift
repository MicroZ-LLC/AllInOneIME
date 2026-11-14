import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import Testing

/// `ProcessOutput`, what `@tasks` runs `claude agents` through: each program's end is seen (its termination handler, not
/// `waitUntilExit` on a dispatch thread, which missed about one exit in ten), with what it printed on both pipes and its
/// status; one past its time is ended, and the call fails saying it timed out.
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
}
