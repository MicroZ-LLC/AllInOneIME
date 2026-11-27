import Carbon
import Foundation

// The look at this input method's own input source, asked for from the main thread. A source Text Input Sources doesn't
// list is registered again first, and the registration waited for, up to 2 seconds: on the main thread that froze the
// About page, and typing in every app with it. So the main thread only asks (`isEnabled(completion:)`): the look, its
// seams (`state`, `register`) with it, runs on the check's own serial queue, and the answer comes back on the main
// actor. The Mac's seams (`system`) go to the main thread only for each call to Text Input Sources, whose thread it is,
// and wait on the queue's.

extension InputSourceCheck {
    /// `isEnabled()` without the wait, for the main thread: returns at once; the look (and the registration it may need)
    /// runs on this check's serial queue, and `completion` gets its answer on the main actor. Asked while a look runs,
    /// the answer is the next look's, begun when that one ends and shared by everyone who asked meanwhile: never that of
    /// a look begun before the question (the user may have just added the source), and never a look per question.
    @MainActor
    public func isEnabled(completion: @escaping @MainActor (Bool) -> Void) {
        looks.ask(self, completion)
    }

    /// The Mac's: Text Input Sources and the user's input sources; `bundle` registered again when needed (nil: never).
    /// Its seams go to the main thread for each call to Text Input Sources, and wait for the registration on the thread
    /// that runs them: the check's queue (`isEnabled(completion:)`) or the identity cleanup's, never the main thread.
    public static func system(id: String, bundle: URL?) -> InputSourceCheck {
        InputSourceCheck(id: id, state: { state(of: id) }, register: {
            guard let bundle, onMain({ TISRegisterInputSource(bundle as CFURL) == noErr }) else { return }
            // Registration is asynchronous inside the text input server.
            let deadline = Date().addingTimeInterval(2)
            // The check's queue or the identity cleanup's (above).
            // swiftlint:disable:next blocking_call
            while onMain({ source(id) == nil }), Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        })
    }

    /// `body` on the main thread, where this input method calls Text Input Sources (the identity cleanup always went
    /// there for it), from any thread: one call to it, nothing that waits.
    static func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        // Another thread (the check's queue, the identity cleanup's), for one call to Text Input Sources; the main thread
        // never waits for those.
        // swiftlint:disable:next blocking_call
        return DispatchQueue.main.sync(execute: body)
    }
}

/// The looks one check (and its copies) was asked for from the main thread: one at a time, on its own serial queue,
/// and at most one more waiting, for everyone who asked while one ran.
@MainActor
final class InputSourceLooks {
    typealias Completion = @MainActor (Bool) -> Void

    private let queue = DispatchQueue(label: "com.allinoneime.input-source-check", qos: .userInitiated)
    /// Who the running look answers; nil: none runs.
    private var running: [Completion]?
    /// Asked while a look runs: the check the next look runs (the last asker's copy) and who it answers.
    private var next: (check: InputSourceCheck, completions: [Completion])?

    nonisolated init() {}

    func ask(_ check: InputSourceCheck, _ completion: @escaping Completion) {
        guard running != nil else { return start(check, [completion]) }
        next = (check, (next?.completions ?? []) + [completion])
    }

    private func start(_ check: InputSourceCheck, _ completions: [Completion]) {
        running = completions
        // The seams aren't Sendable; from here only this queue runs them, one look at a time.
        let look = Look(check: check)
        queue.async {
            let enabled = look.check.isEnabled()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.answered(enabled) }
            }
        }
    }

    private func answered(_ enabled: Bool) {
        let completions = running ?? []
        running = nil
        // The next look first, so that a completion that asks again waits for the one after it, begun after its question.
        if let next {
            self.next = nil
            start(next.check, next.completions)
        }
        for completion in completions { completion(enabled) }
    }
}

/// A check on its way to its looks' queue.
private struct Look: @unchecked Sendable {
    let check: InputSourceCheck
}
