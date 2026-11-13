import Foundation

// An answer that takes longer than the panel waits (prototype, 0.7.5 cross-app): an `@question` the input method's
// session answers shows in the panel as before when it is done within `LateAnswer.panelWait`; past it, the panel says it
// goes on in the background and gets out of the way (the user goes on typing), and the answer, once done, comes as a
// notification (its title the question, its body the answer's first line) and in clipboard history (⌃V), where the
// history is on; clicking the notification puts it on the clipboard. Esc while it is still in the panel stops it, as
// before. The answer's stream runs in an `AnswerRelay`, which the field's request (`SessionTasks.convert`) reads while it
// waits and which reads on alone once the field lets go (`detach`).

/// What an `@question` takes along to the input method's session, and tells back (`Converter.generate(context:)`): the
/// snapshot of the app it was asked in (`AppSnapshot`, read as it starts, only sent to a session), and whether a session
/// answers (`relay`: an answer that may go on in the background).
public struct QuestionContext: Sendable {
    /// Reads the snapshot (blocking, `AppSnapshot.budget` at most); nil: nothing read.
    public var snapshot: (@Sendable () -> AppSnapshot?)?
    public var relay: AnswerRelay?

    public init(snapshot: (@Sendable () -> AppSnapshot?)?, relay: AnswerRelay?) {
        self.snapshot = snapshot
        self.relay = relay
    }
}

/// An answer that came after the panel stopped waiting for it (`AnswerRelay.detach`), or failed then: what the shell
/// shows and keeps (`SessionServices.lateAnswer`).
public struct LateAnswer: Sendable, Equatable {
    /// How long the panel waits for an answer the session gives before it goes on in the background.
    public static let panelWait: TimeInterval = 3

    public var question: String
    /// The whole answer; nil when it failed.
    public var answer: String?
    /// Why it failed (in the interface language).
    public var failure: String?

    public init(question: String, answer: String?, failure: String? = nil) {
        self.question = question
        self.answer = answer
        self.failure = failure
    }

    /// The notification's title: the question, on one line, short.
    public var title: String { AppSnapshot.clip(AppSnapshot.oneLine(question), 60) }

    /// The notification's body: the answer's first line that isn't blank, else why it failed.
    public var body: String {
        if let answer {
            let first = answer.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
            return AppSnapshot.clip(first ?? answer, 200)
        }
        return failure ?? tr("没有得到回答", "No answer")
    }

    /// What the shell does with it: always a notification; the answer kept in clipboard history when there is one and
    /// the history is on (`historyOn`: `Config.clipboardHistoryOn`) and it isn't too long for it.
    public enum Action: Sendable, Equatable {
        case notify(title: String, body: String, copies: String?)
        case keepInClipboardHistory(String)
    }

    public func actions(historyOn: Bool) -> [Action] {
        var actions: [Action] = [.notify(title: title, body: body, copies: answer)]
        if let answer, historyOn, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           answer.count <= ClipboardHistoryItem.maxLength {
            actions.append(.keepInClipboardHistory(answer))
        }
        return actions
    }
}

/// The stream of an `@question`'s answer, between the converter and the field's request: it reads the converter's
/// stream itself and hands each update to the field while the field waits (`attach`); the field giving it up (Esc, the
/// request stopped) stops the answer, as before. Told that the session answers (`answeredInSession`), it may be let go of
/// (`detach`, the panel's wait over): then the field's stream ends there, the answer goes on being read, and once it is
/// done (or fails) `deliver` gets it (`LateAnswer`), on whatever thread it ran.
public final class AnswerRelay: @unchecked Sendable {
    public let question: String
    private let deliver: @Sendable (LateAnswer) -> Void
    private let state = Locked(initialState: State())

    private struct State {
        /// Whether a session answers (nil: not told yet).
        var inSession: Bool?
        var forward: AsyncThrowingStream<ConversionUpdate, Error>.Continuation?
        var detached = false
        var done = false
        var latest: ConversionUpdate?
        var reading: Task<Void, Never>?
    }

    public init(question: String, deliver: @escaping @Sendable (LateAnswer) -> Void) {
        self.question = question
        self.deliver = deliver
    }

    /// The converter's `stream` as the field reads it: read at once, its updates handed on while the field waits.
    public func attach(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] termination in
                if case .cancelled = termination { self?.fieldGaveUp() }
            }
            state.withLock { $0.forward = continuation }  // before the first update can come
            // It keeps the relay until the answer is done: let go of by the field, it goes on.
            let reading = Task {
                do {
                    for try await update in stream { self.received(update) }
                    self.finished(nil)
                } catch {
                    self.finished(error)
                }
            }
            let gaveUp = state.withLock { state -> Bool in
                state.reading = reading
                return state.forward == nil && !state.detached && !state.done
            }
            if gaveUp { reading.cancel() }  // given up before it started
        }
    }

    /// The converter's word: the session answers (true), or the provider (false: no background, as before).
    public func answeredInSession(_ inSession: Bool) {
        state.withLock { $0.inSession = inSession }
    }

    /// Whether it can go on without the field: a session answers and it isn't done yet.
    public var detachable: Bool { state.withLock { $0.inSession == true && !$0.done && !$0.detached && $0.forward != nil } }

    /// The field lets go of it (the panel stopped waiting): its stream ends, the answer goes on and is delivered when
    /// done. False (nothing changes): it can't (`detachable`).
    @discardableResult
    public func detach() -> Bool {
        let forward = state.withLock { state -> AsyncThrowingStream<ConversionUpdate, Error>.Continuation? in
            guard state.inSession == true, !state.done, !state.detached, let forward = state.forward else { return nil }
            state.detached = true
            state.forward = nil
            return forward
        }
        forward?.finish()  // ends the field's stream (not given up: the answer goes on)
        return forward != nil
    }

    /// The field gave its stream up while it waited (Esc): the answer stops.
    private func fieldGaveUp() {
        let reading = state.withLock { state -> Task<Void, Never>? in
            guard !state.detached else { return nil }
            state.forward = nil
            return state.reading
        }
        reading?.cancel()
    }

    private func received(_ update: ConversionUpdate) {
        let forward = state.withLock { state -> AsyncThrowingStream<ConversionUpdate, Error>.Continuation? in
            state.latest = update
            return state.forward
        }
        forward?.yield(update)
    }

    private func finished(_ error: Error?) {
        let (forward, detached, latest) = state.withLock { state in
            state.done = true
            let forward = state.forward
            state.forward = nil
            return (forward, state.detached, state.latest)
        }
        guard detached else {
            if let error { forward?.finish(throwing: error) } else { forward?.finish() }
            return
        }
        guard !(error is CancellationError) else { return }
        let text = latest?.result.versions.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if error == nil, latest?.isFinal == true, !text.isEmpty {
            deliver(LateAnswer(question: question, answer: text))
        } else {
            deliver(LateAnswer(question: question, answer: nil, failure: error.map(UIText.describe) ?? tr("没有得到回答", "No answer")))
        }
    }
}
