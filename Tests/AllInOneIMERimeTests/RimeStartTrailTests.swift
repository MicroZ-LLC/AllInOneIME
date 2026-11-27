import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// Where librime's start got to (`RimeStartTrail`): each step written down before it runs, and the step a crash or a
/// kill stopped in said in the next start's log. In a folder of the test's own; librime isn't started.
struct RimeStartTrailTests {
    let root = TestScratch.temporary("rime-start-trail-\(UUID().uuidString)")

    @Test func aTrailEndedInAStepNamesItAndOneThatGotThroughNamesNone() {
        let line = { (step: String) in "2026-11-27T09:00:00.000Z pid 42 \(step)" }
        #expect(RimeStartTrail.unfinished([line("setup"), line("initialize")].joined(separator: "\n") + "\n") == "initialize")
        #expect(RimeStartTrail.unfinished([line("started"), line("deploy start")].joined(separator: "\n")) == "deploy start")
        #expect(RimeStartTrail.unfinished(line("exit: join deployment, finalize")) == "exit: join deployment, finalize")
        for done in ["started", "deploy success", "deploy failure", "ended at exit"] {
            #expect(RimeStartTrail.unfinished(line("deploy start") + "\n" + line(done) + "\n") == nil, "\(done)")
        }
        #expect(RimeStartTrail.unfinished("") == nil)
        #expect(RimeStartTrail.unfinished("not a trail line") == nil)
    }

    @Test func eachStepIsWrittenAtOnceAndTheNextStartLogsWhereTheLastStopped() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(RimeStartTrail.fileName)
        let first = RimeStartTrail()
        first.begin(in: root)
        first.step("setup")
        first.step("initialize")
        // Written already, as a crash right now would leave it: no close, no flush.
        let written = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        #expect(written.count == 2)
        #expect(written.last?.hasSuffix(" pid \(ProcessInfo.processInfo.processIdentifier) initialize") == true)

        let heard = Locked<[String]>(initialState: [])
        let stop = CoreLog.listen { message in heard.withLock { $0.append(message) } }
        defer { stop() }
        let next = RimeStartTrail()
        next.begin(in: root)
        #expect(heard.withLock { $0 }.contains { $0.contains("the last start of librime ended during \"initialize\"") })
        #expect(try String(contentsOf: file, encoding: .utf8).isEmpty, "a new trail")

        next.step("started")
        let again = RimeStartTrail()
        heard.withLock { $0.removeAll() }
        again.begin(in: root)
        #expect(!heard.withLock { $0 }.contains { $0.contains("the last start of librime ended during") })
    }
}
