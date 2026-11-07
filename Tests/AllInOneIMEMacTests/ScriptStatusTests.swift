import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMEMac

/// The script extensions' status lines kept across launches (`ScriptStatus`, `StatusFile`).
@MainActor
struct ScriptStatusTests {
    /// Made, nothing is read (the key that first shows a status line never reads the file); `prepare`, at launch, reads
    /// it off the main thread, and the values show once in, a value this launch already had kept.
    @Test func theValuesKeptAreReadOffTheMainThread() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("script-status-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = StatusFile(url: folder.appendingPathComponent("script-statuses.json"))
        file.write(["weather": StatusSchedule.Kept(text: "21°", at: Date())])
        let reads = Locked<[Bool]>(initialState: [])
        let status = ScriptStatus(read: {
            reads.withLock { $0.append(Thread.isMainThread) }
            return file.read()
        })
        #expect(reads.withLock { $0 }.isEmpty && status.text(forID: "weather") == nil, "nothing read when made")
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in status.prepare { done.resume() } }
        #expect(reads.withLock { $0 } == [false], "read once, off the main thread")
        #expect(status.text(forID: "weather") == "21°")
        var schedule = StatusSchedule()
        schedule.finished("weather", line: "22°")
        schedule.adopt(["weather": StatusSchedule.Kept(text: "21°", at: Date(timeIntervalSinceNow: -60))])
        #expect(schedule.text(for: "weather") == "22°", "this launch's value stays")
    }
}
