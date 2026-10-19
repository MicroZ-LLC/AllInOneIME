import AllInOneIMECore
import Foundation

/// Level two from a script (a golden's provider fixture, §10 `#! provider`): every request streams the same steps,
/// each `after` ms after the one before it on the engine's clock, into the session's Composer. The goldens' tests and
/// the engine's test mode use it in place of a model.
public final class ScriptedProvider: @unchecked Sendable {
    /// One update of the stream: the versions so far (the last still coming in, unless `final`), or a failure.
    public struct Step: Codable, Equatable, Sendable {
        public var after: Int
        public var versions: [String]
        public var final: Bool
        public var error: String?

        public init(after: Int, versions: [String] = [], final: Bool = false, error: String? = nil) {
            self.after = after
            self.versions = versions
            self.final = final
            self.error = error
        }

        enum CodingKeys: String, CodingKey { case after, versions, final, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            after = try c.decodeIfPresent(Int.self, forKey: .after) ?? 0
            versions = try c.decodeIfPresent([String].self, forKey: .versions) ?? []
            final = try c.decodeIfPresent(Bool.self, forKey: .final) ?? false
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }

        /// What the Composer receives for it.
        public var result: ConversionResult {
            ConversionResult(versions: versions.enumerated().map {
                CandidateLine($0.element, isComplete: final || $0.offset < versions.count - 1)
            })
        }
    }

    public struct Fixture: Codable, Equatable, Sendable {
        public var steps: [Step]
        public init(steps: [Step]) { self.steps = steps }
    }

    /// A request the provider was given: its session, id and text (for the tests to check).
    public struct Request: Equatable, Sendable {
        public var sid: UInt32
        public var id: Int
        public var input: String
    }

    public let fixture: Fixture
    private let clock: WireClock
    private let lock = NSLock()
    private var timers: [ObjectIdentifier: [WireTimer]] = [:]
    private var started: [Request] = []

    public init(fixture: Fixture, clock: WireClock) {
        self.fixture = fixture
        self.clock = clock
    }

    public convenience init(contentsOf url: URL, clock: WireClock) throws {
        self.init(fixture: try WireJSON.decode(Fixture.self, from: Data(contentsOf: url)), clock: clock)
    }

    public var requests: [Request] { lock.guarded { started } }

    /// Whether `effect` starts a request this answers, and if so, starts it: the stream goes into `session`.
    public func start(_ effect: Composer.Effect, in session: ComposerSession) -> Bool {
        let request: (id: Int, input: String)
        switch effect {
        case let .startConversion(input, id), let .startCommand(_, input, id), let .reask(_, input, id),
             let .startRun(_, input, id), let .startTranslateMode(input, _, id):
            request = (id, input)
        case let .startRefine(_, id), let .startPlan(_, _, id):
            request = (id, "")
        default:
            return false
        }
        cancel(in: session)
        lock.guarded { started.append(Request(sid: session.sid, id: request.id, input: request.input)) }
        var delay = 0
        var scheduled: [WireTimer] = []
        for step in fixture.steps {
            delay += step.after
            scheduled.append(clock.after(Double(delay) / 1000) {
                session.feed { composer in
                    if let error = step.error { return composer.fail(error, id: request.id) }
                    return composer.receive(step.result, isFinal: step.final, id: request.id)
                }
            })
        }
        lock.guarded { timers[ObjectIdentifier(session)] = scheduled }
        return true
    }

    /// Stops what streams into `session` (`cancelConversion`, the session closed).
    public func cancel(in session: ComposerSession) {
        let stopped = lock.guarded { timers.removeValue(forKey: ObjectIdentifier(session)) } ?? []
        for timer in stopped { timer.cancel() }
    }

    /// How long the whole stream takes, in ms.
    public var duration: Int { fixture.steps.reduce(0) { $0 + $1.after } }
}
