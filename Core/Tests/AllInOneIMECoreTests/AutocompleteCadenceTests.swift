import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The session's time, set by the test.
final class CadenceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 2000
    var now: TimeInterval {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// Autocomplete's cadence (AC-12): text typed at a steady rhythm, the pause's timers fired when they would run out (a
/// timer whose pause a later key cut short does nothing, as on the Mac), what was read and asked counted.
@Suite(.serialized)
struct AutocompleteCadenceTests {
    struct Typist {
        let host: FakeHost
        let model: ContinuingModel
        let clock: CadenceClock
        let store: AutocompleteStore
        /// The pauses started and not run out yet: when each runs out.
        private(set) var pending: [(timer: TimerID, at: TimeInterval)] = []
        /// How long the last pause started was to be.
        private(set) var lastPause: TimeInterval?
        private var seen = 0

        init(answer: String = " and more.", store: AutocompleteStore = AutocompleteStore(), _ settings: Config? = nil) {
            var config = settings ?? .default
            if settings == nil {
                config.uiLanguage = "en"
                config.setOrder([Language.english])
                config.setOrder([OutputLanguage.english, .chinese])
                config.autocomplete = true
            }
            let fixed = config
            model = ContinuingModel { _ in answer }
            clock = CadenceClock()
            self.store = store
            var services = SessionServices(converter: Converter(loadConfig: { fixed }, appleModel: model), loadSettings: { fixed })
            let engine = FakeEngine()
            services.levelOne = { .engine(engine) }
            let clock = clock
            services.uptime = { clock.now }
            services.autocomplete = store
            host = FakeHost(services: services)
            host.app = "com.apple.TextEdit"
            host.appTypesKeys = true
            host.focus()
        }

        /// The timers started since last looked at, with when they run out.
        private mutating func note() {
            for timer in host.timers.dropFirst(seen) {
                guard case .autocomplete = timer else { continue }
                lastPause = host.timerDelays[timer]
                pending.append((timer, clock.now + (lastPause ?? 0)))
            }
            seen = host.timers.count
        }

        /// The time goes on to `time`: the pauses that run out by then do, in order, and what they ask is answered.
        mutating func wait(until time: TimeInterval) {
            while let next = pending.filter({ $0.at <= time }).min(by: { $0.at < $1.at }) {
                pending.removeAll { $0.timer == next.timer }
                clock.now = max(clock.now, next.at)
                host.fireTimers { $0 == next.timer }
                seen = host.timers.count
                host.settle(timeout: 20) { host.session.autocomplete.asked == nil }
                note()
            }
            clock.now = max(clock.now, time)
        }

        /// `text` typed a key every `interval` seconds; `rest` seconds after its last key.
        mutating func type(_ text: String, every interval: TimeInterval, rest: TimeInterval = 0) {
            for (index, character) in text.enumerated() {
                if index > 0 { wait(until: clock.now + interval) }
                host.type(String(character))
                note()
            }
            wait(until: clock.now + max(rest, interval))
        }

        /// The field's reads, and the requests made (`Autocomplete.Metrics.asked`).
        var reads: Int { host.fieldReads }
        var requests: Int { store.metrics.asked }
    }

    static let sentences = ["Thanks for the update.", " I will send you the report by Friday.", " Let me know if you have any questions."]

    /// Three sentences typed at 5 keys a second (200 ms a key), each followed by a second's thought: the pause is
    /// longer than the time between keys, so nothing is read or asked while the user types, only once they stop.
    /// Before: with nothing to show, 99 reads and 98 requests for 99 keys (with a suggestion shown and typed past each
    /// time, 8 and 7: the pause grew in the app where they were waved away).
    @Test(.bug(id: "AC-12", "the pause is shorter than the time between keys: a read and a request for nearly every key"),
          arguments: [" and more.", ""])
    func typingThreeSentencesAtFiveKeysASecondAsksOnlyAtThePauses(_ answer: String) async {
        await withInterfaceLanguage("en") {
            var typist = Typist(answer: answer)
            for sentence in Self.sentences { typist.type(sentence, every: 0.2, rest: 1) }
            let keys = Self.sentences.joined().count
            print("AC-12 cadence (answer \(answer.debugDescription)): \(keys) keys at 5 a second, 1 s after each sentence: \(typist.reads) reads, \(typist.requests) requests")
            #expect(typist.reads == 3 && typist.requests == 3, "\(keys) keys: \(typist.reads) reads, \(typist.requests) requests")
        }
    }

    /// One who types slowly (a key every 400 ms): once their first keys have told it, the pause grows with their
    /// rhythm, half as long again as the time between their keys, so it doesn't run out between two of them either; it
    /// never grows past `longest`.
    @Test(.bug(id: "AC-12", "the pause doesn't follow the user's typing"))
    func thePauseFollowsTheUsersRhythm() async {
        await withInterfaceLanguage("en") {
            var typist = Typist(answer: "")
            typist.type(Self.sentences[0], every: 0.4, rest: 1)
            let (reads, requests) = (typist.reads, typist.requests)
            typist.type(Self.sentences[1], every: 0.4, rest: 1)
            #expect(typist.reads - reads == 1 && typist.requests - requests == 1, "\(typist.reads - reads) reads, \(typist.requests - requests) requests")
            #expect(typist.lastPause.map { abs($0 - 0.6) < 0.001 } == true, "\(String(describing: typist.lastPause))")
        }
        var rhythm = Autocomplete.Rhythm()
        #expect(rhythm.pause(0.35) == 0.35)
        for n in 0..<4 { rhythm.key(at: Double(n) * 0.1) }
        #expect(rhythm.median == nil && rhythm.pause(0.35) == 0.35)  // too few keys yet to go by
        for n in 4..<10 { rhythm.key(at: Double(n) * 0.1) }
        #expect(rhythm.pause(0.35) == 0.35 && rhythm.pause(0.5) == 0.5)  // fast: the model's
        var slow = Autocomplete.Rhythm()
        for n in 0..<10 { slow.key(at: Double(n) * 0.5) }
        #expect(slow.pause(0.35) == 0.75)
        // A stop isn't the rhythm; the pause never grows past the longest.
        slow.key(at: 100)
        #expect(slow.intervals.count == 9)
        var slowest = Autocomplete.Rhythm()
        for n in 0..<10 { slowest.key(at: Double(n) * 1.4) }
        #expect(slowest.pause(0.35) == Autocomplete.Rhythm.longest)
    }

    /// A request only once the line has a word to go on from: not for one or two letters ("is" asked, the model
    /// answered "a": "isa").
    @Test(.bug(id: "AC-12", "one or two letters in an empty field are asked about"))
    func aWordToGoOnFromFirst() async {
        func asks(_ before: String) -> Bool { Autocomplete.context(FieldText(before: before, after: "")) != nil }
        #expect(!asks("is") && !asks("Hi") && !asks("Long line\nok") && !asks("你"))
        #expect(asks("iss") && asks("Hi ") && asks("Hi,") && asks("I w") && asks("你好") && asks("Hello wor") && asks("Line\nI am"))
        await withInterfaceLanguage("en") {
            var typist = Typist(answer: "a")
            typist.type("is", every: 0.2, rest: 1)
            #expect(typist.reads == 1 && typist.requests == 0 && typist.host.ghost == nil)
        }
    }

    /// The answer has as long as before to come, counted from when it was asked for (the pause over), not from the last
    /// key: a longer pause leaves the model no less time.
    @Test(.bug(id: "AC-12", "a longer pause leaves the model less time"))
    func tooLateCountsFromTheRequest() async {
        await withInterfaceLanguage("en") {
            let typist = Typist(answer: "")
            typist.model.hold = true
            typist.host.type("Hello wor")
            typist.clock.now += 1.2
            typist.host.fireTimers { if case .autocomplete = $0 { true } else { false } }
            #expect(typist.host.settle(timeout: 20, until: typist.model.isWaiting))
            typist.clock.now += 1.5  // 2.7 s from the last key, 1.5 s from the request
            typist.model.release("ld, how are you?")
            #expect(typist.host.settle(timeout: 20) { typist.host.ghost != nil })
            #expect(typist.host.ghost == "ld, how are you?" && typist.store.metrics.late == 0)
        }
    }
}
