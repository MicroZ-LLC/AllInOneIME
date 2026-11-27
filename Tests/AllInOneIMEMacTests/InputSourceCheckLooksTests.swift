import AllInOneIMEMac
import Foundation
import Testing

/// The main thread's look at the input source (`InputSourceCheck.isEnabled(completion:)`): it returns at once, its
/// seams run on the check's queue, never the main thread, one look at a time, and those asked for while a look runs
/// share one more look, begun after their question. Seams only: nothing here calls Text Input Sources.
@MainActor
struct InputSourceCheckLooksTests {
    /// Seams the test lets go of a look at a time, counting the looks and where they ran.
    final class Seams: @unchecked Sendable {
        private let lock = NSLock()
        private let gate = DispatchSemaphore(value: 0)
        /// Each look's answer in turn; the last one again after that.
        private let answers: [Bool]
        private let registered: Bool
        private var started = 0, running = 0, most = 0, onMain = 0, registrations = 0

        init(_ answers: [Bool], registered: Bool = true) {
            self.answers = answers
            self.registered = registered
        }

        func check(id: String = "com.example.allinoneime.looks") -> InputSourceCheck {
            InputSourceCheck(id: id, state: { self.state() }, register: { self.register() })
        }

        /// A look, held until `release` once the source is registered (`registered` false: the first look finds it not,
        /// at once, and the check registers it and looks again).
        private func state() -> InputSourceState {
            let (isRegistered, answer) = locked { () -> (Bool, Bool) in
                started += 1
                running += 1
                most = max(most, running)
                if Thread.isMainThread { onMain += 1 }
                return (registered || registrations > 0, answers[min(started - 1, answers.count - 1)])
            }
            if isRegistered { gate.wait() }
            locked { running -= 1 }
            return InputSourceState(registered: isRegistered, enabled: answer)
        }

        private func register() {
            locked {
                registrations += 1
                if Thread.isMainThread { onMain += 1 }
            }
        }

        func release() { gate.signal() }

        var looks: Int { locked { started } }
        var mostAtOnce: Int { locked { most } }
        var onMainThread: Int { locked { onMain } }
        var registerCalls: Int { locked { registrations } }

        private func locked<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }
    }

    /// Generous: under a loaded machine's full run the main thread, which answers and resumes the test, can be held up
    /// for seconds by other tests; an answer that comes is never waited for that long.
    private func until(_ condition: () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(30)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }

    @Test func returnsAtOnceAndAnswersOnTheMainThreadOnceTheLookEnds() async throws {
        let seams = Seams([true])
        var answers: [Bool] = []
        var answeredOnMain = true
        let asked = Date()
        seams.check().isEnabled { enabled in
            answeredOnMain = answeredOnMain && Thread.isMainThread
            answers.append(enabled)
        }
        #expect(Date().timeIntervalSince(asked) < 0.1, "the main thread waited for the look")
        #expect(try await until { seams.looks == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(answers.isEmpty, "answered before the look ended")
        seams.release()
        #expect(try await until { answers == [true] })
        #expect(answeredOnMain)
        #expect(seams.onMainThread == 0, "a seam ran on the main thread")
    }

    @Test func questionsWhileALookRunsShareOneMoreLook() async throws {
        let seams = Seams([false, true, false])
        let check = seams.check()
        var answers: [String: Bool] = [:]
        check.isEnabled { answers["first"] = $0 }
        #expect(try await until { seams.looks == 1 })
        for asker in ["second", "third", "fourth"] { check.isEnabled { answers[asker] = $0 } }
        try await Task.sleep(for: .milliseconds(100))
        #expect(seams.looks == 1, "a look began beside the one running")

        seams.release()
        #expect(try await until { seams.looks == 2 })
        #expect(answers == ["first": false], "those asked during the first look got its answer: \(answers)")
        seams.release()
        #expect(try await until { answers.count == 4 })
        #expect(answers == ["first": false, "second": true, "third": true, "fourth": true])
        try await Task.sleep(for: .milliseconds(100))
        #expect(seams.looks == 2, "a look per question")
        #expect(seams.mostAtOnce == 1)
        #expect(seams.onMainThread == 0)
    }

    /// Asked again once the answer came (by the completion itself, or later): a look of its own, never the one before.
    @Test func aQuestionAfterTheAnswerGetsALookOfItsOwn() async throws {
        let seams = Seams([false, true, false])
        let check = seams.check()
        var answers: [Bool] = []
        check.isEnabled { enabled in
            answers.append(enabled)
            check.isEnabled { answers.append($0) }
        }
        seams.release()
        #expect(try await until { seams.looks == 2 })
        #expect(answers == [false])
        seams.release()
        #expect(try await until { answers == [false, true] })

        check.isEnabled { answers.append($0) }
        #expect(try await until { seams.looks == 3 })
        seams.release()
        #expect(try await until { answers == [false, true, false] })
        #expect(seams.mostAtOnce == 1)
    }

    /// A copy of the check (the status keeps one, a caller may take another) shares its looks; another check doesn't wait
    /// for them.
    @Test func copiesShareTheirLooksAndOtherChecksDont() async throws {
        let seams = Seams([false, true])
        let check = seams.check()
        let copy = check
        var answers: [String: Bool] = [:]
        check.isEnabled { answers["check"] = $0 }
        #expect(try await until { seams.looks == 1 })
        copy.isEnabled { answers["copy"] = $0 }

        let other = Seams([true])
        other.release()
        other.check().isEnabled { answers["other"] = $0 }
        #expect(try await until { answers["other"] == true }, "another check waited for this one's look")
        #expect(seams.looks == 1, "the copy's look began beside the check's")

        seams.release()
        seams.release()
        #expect(try await until { answers.count == 3 })
        #expect(answers == ["check": false, "copy": true, "other": true])
        #expect(seams.looks == 2 && seams.mostAtOnce == 1)
    }

    /// Not registered: the registration, and the look after it, run on the check's queue too.
    @Test func theRegistrationRunsOffTheMainThread() async throws {
        let seams = Seams([false, true], registered: false)
        var answers: [Bool] = []
        let asked = Date()
        seams.check().isEnabled { answers.append($0) }
        #expect(Date().timeIntervalSince(asked) < 0.1)
        #expect(try await until { seams.looks == 2 })
        seams.release()
        #expect(try await until { answers == [true] })
        #expect(seams.registerCalls == 1)
        #expect(seams.onMainThread == 0, "the registration or a look ran on the main thread")
    }
}
