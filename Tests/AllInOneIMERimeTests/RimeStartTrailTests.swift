import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// Where librime's start got to (`RimeStartTrail`): each step written down before it runs, in a file of the process's
/// own, and the step a crash or a kill stopped in said in the next start's log, once the process is gone. In a folder
/// of the test's own; librime isn't started. Several processes are played by trails given a process number each (and
/// told which of them run): what is logged names the file, so each test hears its own only.
struct RimeStartTrailTests {
    let root = TestScratch.temporary("rime-start-trail-\(UUID().uuidString)")

    static func line(_ step: String) -> String { "2026-11-27T09:00:00.000Z pid 42 \(step)" }
    static func trail(_ steps: String...) -> String { steps.map(line).joined(separator: "\n") + "\n" }

    @Test func aTrailEndedInAStepNamesItAndOneThatGotThroughNamesNone() {
        #expect(RimeStartTrail.unfinished(Self.trail("setup", "initialize")) == "initialize")
        #expect(RimeStartTrail.unfinished(Self.trail("started", "deploy start")) == "deploy start")
        #expect(RimeStartTrail.unfinished(Self.line("exit: join deployment, finalize")) == "exit: join deployment, finalize")
        for done in ["deploy success", "deploy failure"] {
            #expect(RimeStartTrail.unfinished(Self.trail("started", "deploy start", done)) == nil, "\(done)")
        }
        #expect(RimeStartTrail.unfinished(Self.trail("started", "deploy start", "deploy success", "exit: join deployment, finalize",
                                                   "ended at exit")) == nil)
        #expect(RimeStartTrail.unfinished(Self.trail("start maintenance", "started")) == nil, "nothing to deploy")
        #expect(RimeStartTrail.unfinished("") == nil)
        #expect(RimeStartTrail.unfinished("not a trail line") == nil)
    }

    /// librime's deployment thread writes "deploy start" as `start_maintenance` starts it, before or after the start's
    /// own "started": a deployment that crashed is found either way, and one that ended is not taken for a crash.
    @Test func theDeploymentThreadsStepsAreReadApartFromTheStartsInWhateverOrderTheyCame() {
        #expect(RimeStartTrail.unfinished(Self.trail("start maintenance", "deploy start", "started")) == "deploy start")
        #expect(RimeStartTrail.unfinished(Self.trail("start maintenance", "started", "deploy start")) == "deploy start")
        #expect(RimeStartTrail.unfinished(Self.trail("start maintenance", "deploy start", "started", "deploy success")) == nil)
        #expect(RimeStartTrail.unfinished(Self.trail("start maintenance", "deploy start", "deploy success")) == "start maintenance")
        // A redeploy's, later.
        #expect(RimeStartTrail.unfinished(Self.trail("deploy start", "started", "deploy success", "deploy start")) == "deploy start")
    }

    @Test func eachStepIsWrittenAtOnceAndTheNextStartLogsWhereTheLastStopped() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pid: Int32 = 910_001
        let file = root.appendingPathComponent(RimeStartTrail.fileName(pid: pid))
        let first = RimeStartTrail(pid: pid, isRunning: { _ in false })
        first.begin(in: root)
        first.step("setup")
        first.step("initialize")
        // Written already, as a crash right now would leave it: no close, no flush (not the main thread).
        let written = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        #expect(written.count == 2)
        #expect(written.last?.hasSuffix(" pid \(pid) initialize") == true)

        let heard = Locked<[String]>(initialState: [])
        let stop = CoreLog.listen { message in heard.withLock { $0.append(message) } }
        defer { stop() }
        let errors = { heard.withLock { $0 }.filter { $0.contains("(\(RimeStartTrail.fileName(pid: pid)))") } }
        // That process gone, the next one (here of the same number) finds its trail.
        let next = RimeStartTrail(pid: pid, isRunning: { _ in false })
        next.begin(in: root)
        #expect(errors().contains { $0.contains("the last start of librime ended during \"initialize\"") }, "\(errors())")
        #expect(try String(contentsOf: file, encoding: .utf8).isEmpty, "a new trail")

        next.step("started")
        heard.withLock { $0.removeAll() }
        RimeStartTrail(pid: 910_002, isRunning: { _ in false }).begin(in: root)
        #expect(errors().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path), "the trail of a process gone is removed once read")
    }

    /// Two processes starting librime at once (`--register` and the input method macOS starts for it) on one logs
    /// folder: before, the second emptied the file the first was writing (whose next lines then landed after a run of
    /// NULs, or over the second's), and took the first's start under way for a crash.
    @Test func aTrailOfAProcessStillRunningIsNeitherEmptiedNorTakenForACrash() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (firstPid, secondPid): (Int32, Int32) = (910_011, 910_012)
        let heard = Locked<[String]>(initialState: [])
        let stop = CoreLog.listen { message in heard.withLock { $0.append(message) } }
        defer { stop() }
        let errors = {
            heard.withLock { $0 }.filter { message in
                [firstPid, secondPid].contains { message.contains("(\(RimeStartTrail.fileName(pid: $0)))") }
            }
        }

        let first = RimeStartTrail(pid: firstPid, isRunning: { _ in true })
        first.begin(in: root)
        first.step("setup")
        first.step("initialize")
        let second = RimeStartTrail(pid: secondPid, isRunning: { $0 == firstPid })
        second.begin(in: root)
        second.step("setup")
        first.step("start maintenance")
        first.step("started")
        second.step("initialize")
        #expect(errors().isEmpty, "the first is still running: \(errors())")

        let firstFile = try String(contentsOf: root.appendingPathComponent(RimeStartTrail.fileName(pid: firstPid)), encoding: .utf8)
        #expect(!firstFile.contains("\0"))
        #expect(firstFile.split(separator: "\n").map { $0.split(separator: " ", maxSplits: 3).last ?? "" }
                == ["setup", "initialize", "start maintenance", "started"])
        let secondFile = try String(contentsOf: root.appendingPathComponent(RimeStartTrail.fileName(pid: secondPid)), encoding: .utf8)
        #expect(secondFile.split(separator: "\n").count == 2)

        // Both gone: the second's crash is found, and the first's, which got through, isn't taken for one.
        RimeStartTrail(pid: 910_013, isRunning: { _ in false }).begin(in: root)
        #expect(errors().count == 1)
        #expect(errors().first?.contains("ended during \"initialize\" (\(RimeStartTrail.fileName(pid: secondPid)))") == true)
    }

    /// Written from the main thread without waiting (InputMethodKit's: never a wait there), by the trail's queue, in the
    /// order of the steps; the deployment thread's meanwhile written in between, before its `step` returns.
    @Test @MainActor func stepsFromTheMainThreadAreWrittenInTheirOrderByTheTrailsQueue() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pid: Int32 = 910_021
        let trail = RimeStartTrail(pid: pid, isRunning: { _ in false })
        trail.begin(in: root)
        let other = Thread {
            for index in 0..<50 { trail.step("deploy \(index)") }
        }
        other.start()
        for index in 0..<200 { trail.step("step \(index)") }
        while !other.isFinished { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        trail.flush()
        let steps = try String(contentsOf: root.appendingPathComponent(RimeStartTrail.fileName(pid: pid)), encoding: .utf8)
            .split(separator: "\n").map { String($0.split(separator: " ", maxSplits: 3).last ?? "") }
        #expect(steps.filter { $0.hasPrefix("step ") } == (0..<200).map { "step \($0)" })
        #expect(steps.filter { $0.hasPrefix("deploy ") } == (0..<50).map { "deploy \($0)" })
    }

    @Test func aProcessThatEndedIsNotRunning() throws {
        #expect(RimeStartTrail.isRunning(ProcessInfo.processInfo.processIdentifier))
        #expect(RimeStartTrail.isRunning(1), "launchd: one the system won't let us signal still runs")
        let ended = Process()
        ended.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try ended.run()
        ended.waitUntilExit()
        #expect(!RimeStartTrail.isRunning(ended.processIdentifier))
        #expect(RimeStartTrail.pid(ofFileName: RimeStartTrail.fileName(pid: 4321)) == 4321)
        #expect(RimeStartTrail.pid(ofFileName: "rime.allinoneime.INFO") == nil)
        #expect(RimeStartTrail.pid(ofFileName: "rime-start-x.txt") == nil)
    }
}
