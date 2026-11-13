import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import Testing

/// `ProcessOutput`, what `@tasks` runs `claude agents` through: each program's end is seen (its termination handler, not
/// `waitUntilExit` on a dispatch thread, which missed about one exit in ten), with what it printed on both pipes and its
/// status; one past its time is ended.
struct ProcessOutputTests {
    /// `ProcessOutput.run` on a dispatch thread, as `AgentMonitor` runs it; nil when it hasn't returned within `within`
    /// seconds.
    func run(_ arguments: [String], timeout: TimeInterval = 10, within: TimeInterval = 10) async -> ProcessOutput.Result? {
        let result = Locked<ProcessOutput.Result?>(initialState: nil)
        DispatchQueue.global().async {
            let ran = try? ProcessOutput.run(URL(fileURLWithPath: "/bin/sh"), ["-c"] + arguments, timeout: timeout,
                                             processes: FoundationProcessLauncher())
            result.withLock { $0 = ran }
        }
        let deadline = Date().addingTimeInterval(within)
        while Date() < deadline {
            if let ran = result.withLock({ $0 }) { return ran }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    @Test func everyProgramsEndIsSeenWithWhatItPrinted() async {
        for attempt in 0..<60 {
            let result = await run(["printf out; printf err >&2; exit 3"])
            #expect(result == ProcessOutput.Result(status: 3, output: Data("out".utf8), errors: Data("err".utf8)),
                    "attempt \(attempt): \(String(describing: result))")
            if result == nil { break }
        }
    }

    @Test func aProgramPastItsTimeIsEnded() async {
        let started = Date()
        let result = await run(["sleep 30"], timeout: 0.5, within: 10)
        #expect(result != nil && result?.status != 0)
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func ignoredTermAndOpenPipesStillReturn() async {
        let started = Date()
        let result = await run(["trap '' TERM; while :; do sleep 1; done"], timeout: 0.2, within: 4)
        #expect(result?.status == -1)
        #expect(Date().timeIntervalSince(started) < 4)
    }
}
