import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// ⏎ on `@tasks` lists the tasks as last seen at once (`SessionServices.lastAgents`), while Claude Code is asked again;
/// its answer replaces them, the row picked with the arrows staying picked where it's still listed.
@Suite(.serialized)
struct TasksAtOnceTests {
    /// What `listAgents` answers, when the test lets it.
    final class Run: @unchecked Sendable {
        private let lock = NSLock()
        private var answer: Result<[(session: AgentSession, reply: String?)], Error>?
        func answer(_ result: Result<[(session: AgentSession, reply: String?)], Error>) { lock.withLock { answer = result } }
        func list() async throws -> [(session: AgentSession, reply: String?)] {
            while true {
                if let answer = lock.withLock({ answer }) { return try answer.get() }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }

    struct Failed: Error, LocalizedError {
        var errorDescription: String? { "claude isn't there" }
    }

    static func session(_ id: String, _ state: String, started: Double) -> AgentSession {
        AgentSession(id: id, sessionId: id + "-session", name: "task " + id, state: state, startedAt: started)
    }

    static let last: [(session: AgentSession, reply: String?)] = [
        (session("b", "working", started: 20), nil), (session("a", "done", started: 10), "Fixed it."),
    ]

    func host(run: Run, last: [(session: AgentSession, reply: String?)]? = Self.last) -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.english])
        let fixed = config
        var services = SessionServices(loadSettings: { fixed })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.listAgents = { try await run.list() }
        services.lastAgents = { last }
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    func tasks(_ host: FakeHost) {
        host.press(FakeHost.at)
        host.type("tasks")
        host.press(FakeHost.tab)
        host.press(FakeHost.enter)
    }

    @Test func theLastListShowsAtOnceAndIsReplaced() async {
        await withInterfaceLanguage("en") {
            let run = Run()
            let host = host(run: run)
            tasks(host)
            #expect(host.composer.choices.map(\.text) == ["… task b", "✓ task a"], "at once, before Claude Code answers")
            #expect(host.panel?.rows.map(\.text) == ["task b", "task a"])
            host.press(FakeHost.down)
            #expect(host.composer.highlighted == 1, "task a")
            // The answer: a new task first, the one picked still listed: still picked, one row further down.
            run.answer(.success([(Self.session("c", "working", started: 30), nil), (Self.session("b", "done", started: 20), "Done."),
                                 (Self.session("a", "done", started: 10), "Fixed it.")]))
            #expect(host.settle { host.composer.choices.count == 3 })
            #expect(host.composer.choices.map(\.text) == ["… task c", "✓ task b", "✓ task a"])
            #expect(host.composer.highlighted == 2, "task a, picked with ↓, where it is now")
            host.press(FakeHost.enter)
            #expect(host.openedAgents == ["a"])
        }
    }

    /// The run fails: the list as last seen stays, and why it isn't brought up to date is said.
    @Test func aFailedRunLeavesTheLastList() async {
        await withInterfaceLanguage("en") {
            let run = Run()
            let host = host(run: run)
            tasks(host)
            run.answer(.failure(Failed()))
            #expect(host.settle { host.session.notice == "claude isn't there" })
            #expect(host.composer.choices.map(\.text) == ["… task b", "✓ task a"] && host.composer.phase == .choosing)
        }
    }

    /// None seen yet: the panel waits for the run, as before.
    @Test func noneSeenYetWaits() async {
        await withInterfaceLanguage("en") {
            let run = Run()
            let host = host(run: run, last: nil)
            tasks(host)
            #expect(host.composer.choices.isEmpty && host.composer.phase == .translating(id: 1))
            run.answer(.success(Self.last))
            #expect(host.settle { host.composer.choices.count == 2 })
        }
    }
}
