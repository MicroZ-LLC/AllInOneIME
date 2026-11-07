import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The keys that waited for the selection read after the "@" key reach the app in the order typed (`KeysOnTheWay`,
/// `PlatformAction.passKey`, `.replayKey`): one not taken then is given to the app, and every key typed after it, until
/// the app has it, goes behind it, never ahead. No key lost, none twice.
struct KeyOrderTests {
    /// The system's stream of keys as a shell sees it (the Mac's: what is posted goes in behind what is typed already),
    /// with the shell's part (`KeysOnTheWay`) and the app's: a key the input method doesn't take, or one given to it,
    /// acts in the app (→ marked "→" where the caret moved on, a character typed at the caret). `field` tells, in order,
    /// what reached the field: the app's keys ("→", "x") and what the session put there ("@" committed, "[ab]" marked).
    final class Stream {
        let host: FakeHost
        var order = KeysOnTheWay()
        /// What is posted and not handed to the input method yet, in order.
        var posted: [(key: KeyEvent, mark: KeysOnTheWay.Mark)] = []
        var now: TimeInterval = 100
        private(set) var field: [String] = []
        private var seen = 0, seenOutputs = 0

        init(_ host: FakeHost) {
            self.host = host
            seenOutputs = host.outputs.count
        }

        /// What the session put in the field since the last look, then the keys it asked to post, posted now (behind
        /// what is posted already).
        func post() {
            for output in host.outputs.dropFirst(seenOutputs) {
                switch output {
                case let .commit(text), let .replace(text, _): if !text.isEmpty { field.append(text) }
                case let .marked(text, _, _): if !text.isEmpty { field.append("[\(text)]") }
                default: break
                }
            }
            seenOutputs = host.outputs.count
            let actions = host.platformActions.dropFirst(seen)
            seen = host.platformActions.count
            for action in actions {
                switch action {
                case let .passKey(key): posted.append((key, order.post(passed: true, now: now)))
                case let .replayKey(key): posted.append((key, order.post(passed: false, now: now)))
                default: break
                }
            }
        }

        /// A key reaches the input method, typed (`mark` nil) or posted: what the shell does with it.
        func arrives(_ key: KeyEvent, mark: KeysOnTheWay.Mark? = nil) {
            switch order.arrived(mark, now: now) {
            case .toApp:
                app(key)
            case .behind:
                posted.append((key, order.post(passed: false, now: now)))
            case .handle:
                if !host.press(key) { app(key) }
                post()
            }
        }

        /// The user types `key`.
        func type(_ key: KeyEvent) { arrives(key) }

        /// The selection read lands: what waited for it is done, the keys to post posted.
        func selectionLands() {
            host.answerFieldReads()
            post()
        }

        /// The next key posted reaches the input method; all of them, in order.
        func deliverNext() {
            guard !posted.isEmpty else { return }
            let (key, mark) = posted.removeFirst()
            arrives(key, mark: mark)
        }

        func deliverAll() { while !posted.isEmpty { deliverNext() } }

        private func app(_ key: KeyEvent) {
            let text = key == FakeHost.right ? "→" : key.printableText ?? ""
            host.document += text
            field.append(text)
        }
    }

    static func letter(_ text: String) -> KeyEvent { KeyEvent(keyCode: 0, characters: text) }

    /// A field in English (else Chinese, letters composed as pinyin), its text read after the "@" key (a Chromium page's:
    /// `selectionFollows`), the read held until the test lands it; "@" typed, the read on its way.
    func field(english: Bool = true) -> Stream {
        var services = SessionServices(loadSettings: { .default })
        services.levelOne = { .engine(FakeEngine()) }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(english ? .english : .chinese)
        host.document = "hello there"
        host.selectionReadsWait = true
        var told = host.context
        told.selection = nil
        told.selectionFollows = true
        host.press(FakeHost.at, with: told)
        #expect(host.composer.selectionPending)
        return Stream(host)
    }

    /// "@" then → while the read is in flight, then a letter typed as it lands, ahead of the → posted: the → reaches the
    /// app first, the letter behind it, once each.
    @Test func aLetterTypedAsTheReadLandsGoesBehindTheKeyGivenBack() async {
        await withInterfaceLanguage("en") {
            let stream = field()
            stream.type(FakeHost.right)
            #expect(stream.host.document == "hello there", "→ waits for the read")
            stream.selectionLands()
            #expect(stream.host.document == "hello there@" && stream.posted.map(\.key) == [FakeHost.right])
            stream.type(Self.letter("x"))
            #expect(stream.host.document == "hello there@", "the letter waits behind the →")
            stream.deliverAll()
            #expect(stream.host.document == "hello there@→x", "\(stream.host.document)")
            #expect(stream.field == ["@", "→", "x"], "\(stream.field)")
            #expect(!stream.order.isWaiting(now: stream.now))
            // Once the app has it, keys are answered at once again.
            stream.type(Self.letter("y"))
            #expect(stream.posted.isEmpty && stream.host.document == "hello there@→xy", "\(stream.host.document)")
        }
    }

    /// Several keys typed fast: → and two letters while the read is in flight, a third as it lands, a fourth while the
    /// first posted are on their way: each once, in the order typed. In English the letters go to the app; in Chinese
    /// they are composed, after the → is the app's.
    @Test func keysTypedFastReachTheAppInTheOrderTyped() async {
        await withInterfaceLanguage("en") {
            for english in [true, false] {
                let stream = field(english: english)
                for key in [FakeHost.right, Self.letter("a"), Self.letter("b")] { stream.type(key) }
                #expect(stream.host.document == "hello there" && stream.host.marked.isEmpty)
                stream.selectionLands()
                #expect(stream.field == ["@"], "nothing of the letters behind the → ahead of it: \(stream.field)")
                #expect(stream.posted.map(\.key) == [FakeHost.right, Self.letter("a"), Self.letter("b")])
                if case .passed? = stream.posted.first?.mark {} else { Issue.record("the → is given to the app: \(stream.posted)") }
                stream.type(Self.letter("c"))
                stream.deliverNext()  // →
                stream.type(Self.letter("d"))
                #expect(stream.field == ["@", "→"], "\(stream.field)")
                stream.deliverAll()
                let expected = english ? ["@", "→", "a", "b", "c", "d"] : ["@", "→", "[a]", "[ab]", "[abc]", "[abcd]"]
                #expect(stream.field == expected, "\(stream.field)")
                #expect(stream.host.document == (english ? "hello there@→abcd" : "hello there@→"), "\(stream.host.document)")
                #expect(stream.posted.isEmpty && !stream.order.isWaiting(now: stream.now))
            }
        }
    }

    /// With a selection, → gives the keys back as it is, and the letter after it goes behind it as well.
    @Test func behindTheKeyGivenBackOverASelection() async {
        await withInterfaceLanguage("en") {
            var services = SessionServices(loadSettings: { .default })
            services.levelOne = { .engine(FakeEngine()) }
            let host = FakeHost(services: services)
            host.focus()
            host.composer.setInputMode(.english)
            host.document = "hello there"
            host.selection = 0..<11
            host.selectionReadsWait = true
            var told = host.context
            told.selection = nil
            told.selectionFollows = true
            host.press(FakeHost.at, with: told)
            let stream = Stream(host)
            stream.type(FakeHost.right)
            stream.type(Self.letter("x"))
            stream.selectionLands()
            #expect(host.document == "hello there" && host.selection == 0..<11, "\(host.document)")
            #expect(stream.posted.map(\.key) == [FakeHost.right, Self.letter("x")])
            stream.deliverNext()
            host.selection = nil  // → in the app: the caret after the selection
            stream.deliverAll()
            #expect(host.document == "hello there→x", "\(host.document)")
        }
    }

    // MARK: - The record

    /// A mark goes in the event and comes back the same; an event of no mark of these (typed, a paste of ours) has none.
    @Test func marksGoInTheEventAndComeBack() {
        for mark in [KeysOnTheWay.Mark.passed(1), .replayed(2), .passed(.max), .replayed(0)] {
            #expect(KeysOnTheWay.Mark(userData: mark.userData) == mark, "\(mark)")
        }
        #expect(KeysOnTheWay.Mark(userData: 0) == nil && KeysOnTheWay.Mark(userData: 0x4149_4F49) == nil)
    }

    /// A key typed while one posted is on its way goes behind it; once that one is back, at once again. One back stops
    /// the wait for those posted before it (they came first, or never will); one that never comes back is given up after
    /// `timeout`.
    @Test func whatIsWaitedFor() {
        var order = KeysOnTheWay()
        #expect(order.arrived(nil, now: 0) == .handle)
        let passed = order.post(passed: true, now: 0)
        #expect(order.arrived(nil, now: 0.01) == .behind)
        let behind = order.post(passed: false, now: 0.01)
        #expect(order.arrived(passed, now: 0.02) == .toApp)
        #expect(order.arrived(nil, now: 0.02) == .behind, "the key behind it is still on its way")
        let last = order.post(passed: false, now: 0.02)
        #expect(order.arrived(behind, now: 0.03) == .handle && order.arrived(last, now: 0.03) == .handle)
        #expect(order.arrived(nil, now: 0.03) == .handle)
        // Lost: posted, never back.
        let lost = order.post(passed: true, now: 1)
        let after = order.post(passed: false, now: 1)
        #expect(order.arrived(after, now: 1.01) == .handle && !order.isWaiting(now: 1.01), "the one before it never comes now")
        #expect(order.arrived(lost, now: 1.02) == .toApp, "late, still the app's")
        _ = order.post(passed: true, now: 2)
        #expect(order.arrived(nil, now: 2 + KeysOnTheWay.timeout / 2) == .behind)
        #expect(order.arrived(nil, now: 2 + KeysOnTheWay.timeout + 0.01) == .handle, "given up")
    }
}
