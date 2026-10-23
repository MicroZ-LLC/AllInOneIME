import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// A redeploy asked for while another thread is starting one (`RimeService.redeploy`, from any thread: Settings'
/// personal dictionaries, fuzzy pinyin, a language pack): it runs once that one's maintenance is over. Lost, `isReady`
/// stayed false for good, with nothing to start it but a thread waiting in `waitUntilReady`. In a process of its own
/// (`RimeWorker`): librime starts once per process.
struct RedeployTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rime-redeploy-\(UUID().uuidString)")

    @Test(.enabled(if: RimeWorker.scenario == nil && (RimeWorker.dataAvailable || RimeWorker.required)))
    func aRedeployAskedForWhileOneStartsRunsAfterIt() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("redeploy-while-starting", root: root)
    }

    /// How many redeploys reached librime's maintenance.
    final class Starts: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func add() -> Int { lock.withLock { count += 1; return count } }
    }

    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "redeploy-while-starting": { root in
            let service = RimeService.shared
            try service.start(sharedDataDir: RimeFixture.sharedData, userDataDir: root.appendingPathComponent("Rime"), logDir: nil)
            try #require(service.waitUntilReady(timeout: 120))
            let starts = Starts()
            service.beforeMaintenance = {
                guard starts.add() == 1 else { return }
                // Another thread asks for one right then: it finds this one starting.
                let asked = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    RimeService.shared.redeploy()
                    asked.signal()
                }
                asked.wait()
            }
            service.redeploy()
            // Nobody waits in `waitUntilReady` (which would start it itself): the second has to run by itself.
            let deadline = Date().addingTimeInterval(60)
            while !(starts.value == 2 && service.isReady), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            service.beforeMaintenance = nil
            #expect(starts.value == 2, "the redeploy asked for while one was starting ran (\(starts.value) started)")
            #expect(service.isReady && service.deploymentStatus == .succeeded)
        },
    ]
}
