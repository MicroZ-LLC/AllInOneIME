import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// librime started by several threads at once, and by two processes at once on one new user folder
/// (`RimeService.start`): it starts once, and every caller finds it started. Before, the threads crashed in librime's
/// setup and first deployment in about half of the runs (SIGSEGV in `RimeStartMaintenance` and `WorkspaceUpdate::Run`,
/// SIGTRAP on a double free in `SetupDeployer`, SIGABRT), or one of them threw copying `default.custom.yaml` ("File
/// exists"); so did one of the two processes, about one start in two. In processes of their own (`RimeWorker`): librime
/// starts once per process.
struct ConcurrentStartRimeTests {
    static var runs: Bool { RimeWorker.scenario == nil && (RimeWorker.dataAvailable || RimeWorker.required) }

    @Test(.enabled(if: runs))
    func startCalledFromSeveralThreadsAtOnceStartsLibrimeOnce() throws {
        // A crash came in about half of the runs: six of them.
        for _ in 1...6 {
            let root = TestScratch.temporary("rime-concurrent-start-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            try RimeWorker.run("start-from-threads", root: root)
        }
    }

    @Test(.enabled(if: runs))
    func twoProcessesStartingOnOneNewUserFolderBothStart() throws {
        for _ in 1...6 {
            let root = TestScratch.temporary("rime-two-processes-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            // Each worker's own folder (its output) in `root`; the user folder they share is root's (`sharedUserFolder`).
            let first = try RimeWorker.launch("start-on-shared-folder", root: root.appendingPathComponent("first"))
            let second = try RimeWorker.launch("start-on-shared-folder", root: root.appendingPathComponent("second"))
            let results = [Result { try RimeWorker.finish(first) }, Result { try RimeWorker.finish(second) }]
            for result in results { try result.get() }
        }
    }

    /// `exit()` called on another thread while librime starts, its deployment thread started by then but the start not
    /// over yet: the exit used to find librime not started and leave it, deploying, to its static destructors.
    @Test(.enabled(if: runs))
    func anExitWhileLibrimeStartsOnAnotherThreadWaitsForItAndEndsIt() throws {
        for _ in 1...6 {
            let root = TestScratch.temporary("rime-exit-while-starting-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            try RimeWorker.run("exit-while-starting", root: root)
        }
    }

    /// The user folder the workers of one `root` share: beside their own folders.
    static func sharedUserFolder(_ root: URL) -> URL {
        root.deletingLastPathComponent().appendingPathComponent("Rime", isDirectory: true)
    }

    /// Errors thrown on several threads.
    final class Thrown: @unchecked Sendable {
        private let lock = NSLock()
        private var errors: [String] = []
        var all: [String] { lock.withLock { errors } }
        func add(_ error: Error) { lock.withLock { errors.append(String(describing: error)) } }
    }

    /// librime started and typed with: "nihao" is 你好.
    static func expectTyping() throws {
        try #require(RimeService.shared.waitUntilReady(timeout: 120), "librime ready")
        let session = try #require(RimeService.shared.makeSession())
        type("nihao", into: session)
        #expect(session.snapshot().candidates.first?.text == "你好")
    }

    static let scenarios: [String: @Sendable (URL) throws -> Void] = [
        "start-from-threads": { root in
            let user = root.appendingPathComponent("Rime", isDirectory: true)
            let thrown = Thrown()
            DispatchQueue.concurrentPerform(iterations: 8) { _ in
                do {
                    try RimeService.shared.start(sharedDataDir: RimeFixture.sharedData, userDataDir: user, logDir: nil)
                } catch {
                    thrown.add(error)
                }
            }
            #expect(thrown.all.isEmpty, "every start returned: \(thrown.all)")
            #expect(RimeService.shared.isStarted)
            try expectTyping()
            // Set up once: one start's steps (`RimeStartTrail`, in the user folder without a logs folder).
            let name = RimeStartTrail.fileName(pid: ProcessInfo.processInfo.processIdentifier)
            let trail = try String(contentsOf: user.appendingPathComponent(name), encoding: .utf8)
            #expect(trail.components(separatedBy: "\n").filter { $0.hasSuffix(" setup") }.count == 1, "\(trail)")
            #expect(trail.components(separatedBy: "\n").filter { $0.hasSuffix(" started") }.count == 1, "\(trail)")
        },
        "start-on-shared-folder": { root in
            let heard = Locked<[String]>(initialState: [])
            let stop = CoreLog.listen { message in heard.withLock { $0.append(message) } }
            defer { stop() }
            let user = sharedUserFolder(root)
            try RimeService.shared.start(sharedDataDir: RimeFixture.sharedData, userDataDir: user, logDir: nil)
            try expectTyping()
            // The other process's start, under way or over, is not taken for a crash; each one's trail is its own.
            #expect(!heard.withLock { $0 }.contains { $0.contains("the last start of librime ended during") }, "\(heard.withLock { $0 })")
            RimeService.trail.flush()
            let name = RimeStartTrail.fileName(pid: ProcessInfo.processInfo.processIdentifier)
            let trail = try String(contentsOf: user.appendingPathComponent(name), encoding: .utf8)
            #expect(!trail.contains("\0"), "\(trail)")
            #expect(trail.components(separatedBy: "\n").filter { $0.hasSuffix(" setup") }.count == 1, "\(trail)")
        },
        "exit-while-starting": { root in
            let user = root.appendingPathComponent("Rime", isDirectory: true)
            let trail = user.appendingPathComponent(RimeStartTrail.fileName(pid: ProcessInfo.processInfo.processIdentifier))
            Thread.detachNewThread {
                try? RimeService.shared.start(sharedDataDir: RimeFixture.sharedData, userDataDir: user, logDir: nil, fullCheck: true)
            }
            // Written on the starting thread before librime's maintenance starts its deployment thread.
            let deadline = Date().addingTimeInterval(60)
            var maintenance: Bool { (try? String(contentsOf: trail, encoding: .utf8))?.contains(" start maintenance\n") ?? false }
            while Date() < deadline, !maintenance { usleep(100) }
            try #require(maintenance, "the start got to its maintenance")
            print("RIME_WORKER_FINISHED:exit-while-starting")
            fflush(stdout)
            exit(0)
        },
    ]
}
