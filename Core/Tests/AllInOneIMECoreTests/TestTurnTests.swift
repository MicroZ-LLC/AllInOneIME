import Foundation
import Testing
import AllInOneIMECore
import AllInOneIMETestSupport

/// The turn tests take at the process's state (`TestTurn`, the interface language's in `withInterfaceLanguage`).
struct TestTurnTests {
    /// Many more tests than the pool has threads wait for the turn while the one whose turn it is blocks its thread on
    /// work that runs on the pool, as `FakeHost.settle` does: that work still gets a thread, since none of them waits
    /// blocked. One holds the turn at a time.
    @Test func waitingForTheTurnHoldsNoThread() async {
        let turn = TestTurn()
        let tests = ProcessInfo.processInfo.activeProcessorCount * 4
        let state = Locked(initialState: (inside: 0, most: 0, done: 0, stuck: false))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<tests {
                group.addTask {
                    await turn.run {
                        let stuck = state.withLock { state in
                            state.inside += 1
                            state.most = max(state.most, state.inside)
                            return state.stuck
                        }
                        defer { state.withLock { $0.inside -= 1; $0.done += 1 } }
                        guard !stuck else { return }  // the others would be too: once is enough
                        let ran = DispatchSemaphore(value: 0)
                        Task { ran.signal() }
                        if ran.wait(timeout: .now() + 20) == .timedOut {
                            state.withLock { $0.stuck = true }
                            Issue.record("the work on the pool got no thread")
                        }
                    }
                }
            }
        }
        #expect(state.withLock { $0.done } == tests)
        #expect(state.withLock { $0.most } == 1)
    }

    @Test func heldInItsBodyOnly() async {
        let turn = TestTurn()
        #expect(!turn.isHeld)
        #expect(await turn.run { turn.isHeld })
        #expect(!turn.isHeld)
        #expect(await TestTurn().run { !turn.isHeld }, "another turn's")
    }
}
