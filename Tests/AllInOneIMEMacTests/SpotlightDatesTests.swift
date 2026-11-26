import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMEMac

/// Spotlight's dates for the apps (`SpotlightDates`), waited for a moment at most: a Spotlight that never answers
/// (`MDItemCreateWithURL` stuck, seen on the Mac mini) once held `InstantFiles.make`, and with it @'s apps, for good.
struct SpotlightDatesTests {
    /// A lookup that waits until the test lets it go, counting how often it was asked.
    final class Stuck: @unchecked Sendable {
        let gate = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var asked = 0
        var count: Int { lock.withLock { asked } }
        func lookup(_ path: String) -> SpotlightDates.Dates? {
            lock.withLock { asked += 1 }
            gate.wait()
            return nil
        }
        func release() { for _ in 0..<100 { gate.signal() } }
    }

    func found(_ paths: [String]) -> [FileSearchRanking.Found] { paths.map { FileSearchRanking.Found(path: $0) } }

    @Test func aLookupThatNeverAnswersHoldsMakeForTheBudgetOnly() throws {
        let root = TestScratch.temporary("SpotlightDatesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Calculator.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": "Calculator"], format: .binary, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let stuck = Stuck()
        defer { stuck.release() }
        let files = InstantFiles(index: AppIndex(folders: [root.path], apps: [], home: nil, recheckInterval: 0),
                                 dates: SpotlightDates(budget: 0.3, lookup: stuck.lookup))
        // Made on a thread of its own: on the shared pool, the waits of the tests running alongside held it back 15 s
        // before it started. Made again until Spotlight was asked: a lookup whose queue gets to it only once the budget
        // is over (a loaded machine) isn't started at all. Each make returns, whatever Spotlight does; the bound is a
        // hang's (a make that waits for the lookup never returns: it is let go only as the test ends).
        for _ in 0..<20 where stuck.count == 0 {
            let made = DispatchSemaphore(value: 0)
            Thread {
                files.make(history: OpenHistory())
                made.signal()
            }.start()
            #expect(made.wait(timeout: .now() + 60) == .success, "make waited on Spotlight for good")
        }
        #expect(files.results("calc", history: OpenHistory()).map(\.name) == ["Calculator"], "listed, undated")
        #expect(stuck.count == 1)
    }

    @Test func datesThatComeInTimeAreKept() {
        let used = Date(timeIntervalSince1970: 1_700_000_000), changed = Date(timeIntervalSince1970: 1_600_000_000)
        // Answered at once: the budget only bounds how long a loaded machine may take to get to them.
        let dates = SpotlightDates(budget: 60) { $0 == "/a" ? (used, changed) : nil }
        let dated = dates.dated(found(["/a", "/b"]))
        #expect(dated[0].lastUsed == used && dated[0].modified == changed)
        #expect(dated[1].lastUsed == nil && dated[1].modified == nil)
    }

    @Test func whileOneIsStuckNoneIsStartedAndTheyComeBackOnceItReturns() {
        let stuck = Stuck()
        let budget: TimeInterval = 1
        let dates = SpotlightDates(budget: budget, lookup: stuck.lookup)
        // Asked until a lookup is stuck (one its queue got to only after the budget wasn't started), each back once the
        // budget is over.
        let until = Date().addingTimeInterval(60)
        while stuck.count == 0, Date() < until { _ = dates.dated(found(["/a", "/b"])) }
        #expect(stuck.count == 1)
        // While it is stuck, none is started, so none is waited for: back before the budget, which a call that started
        // one would wait out whatever the machine's load.
        let again = Date()
        #expect(dates.dated(found(["/c"])).first?.lastUsed == nil)
        #expect(Date().timeIntervalSince(again) < budget && stuck.count == 1, "no lookup while the first is stuck")
        stuck.release()
        // The stuck one returns, the next is asked (and, let go, answers at once).
        while stuck.count < 2, Date() < until { _ = dates.dated(found(["/d"])) }
        #expect(stuck.count > 1)
    }
}
