import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A pinyin engine with the shape-code table's lists after "`" (as Issue168ShapeOptionTests has it), and a word of
/// more letters for the page with an English word on it.
private final class Review076ShapeEngine: PinyinEngine {
    let base = FakeEngine()

    init() {
        base.dictionary = [
            "yu": ["与", "于", "鱼"], "yu`": ["与", "于", "鱼"], "yu`d": ["鱼", "浴"],
            "yuzu": ["柚子", "鱼族"], "yuzu`": ["柚子", "鱼族"],
        ]
    }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        guard keycode == 0x60, mask == 0, !base.input.isEmpty else { return base.processKey(keycode, mask: mask) }
        base.keys.append((keycode, mask))
        base.input.append("`")
        base.highlighted = 0
        return true
    }

    func takeCommit() -> String? { base.takeCommit() }
    func snapshot() -> EngineSnapshot { base.snapshot() }
    func selectCandidate(onPage index: Int) -> Bool { base.selectCandidate(onPage: index) }
    func commitComposition() -> String? { base.commitComposition() }
    var rawInput: String { base.rawInput }
    func clearComposition() { base.clearComposition() }
    func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
}

/// The settings a test changes while its field keeps the focus.
private final class Review076Settings: @unchecked Sendable {
    private let lock = NSLock()
    private var config: Config
    init(_ config: Config) { self.config = config }
    var current: Config { lock.withLock { config } }
    func change(_ body: (inout Config) -> Void) { lock.withLock { body(&config) } }
}

/// The 0.7.6 review's findings on the right Option's tap as "`" while pinyin is typed with shape codes on (#168, #171),
/// items 25 to 29: each test is one finding, failing until it is fixed. The taps are told as the Mac tells them: a
/// change of the modifiers with the key that changed, its side and a time (`ModifierChange`, `Composer
/// .handleFlagsChanged`).
@Suite("0.7.6 review: right Option for shape codes", .serialized)
struct Review076OptionTapTests {
    private func host(_ settings: Review076Settings? = nil, engine: PinyinEngine? = nil) -> (FakeHost, Review076ShapeEngine) {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.chinese, .english])
        config.shapeCode = "moqi"
        config.actionKey = .optionSpace
        config.candidateLayout = .vertical  // ↓ moves the highlight
        let fixed = config
        let pinyin = Review076ShapeEngine()
        let levelOne: PinyinEngine = engine ?? pinyin
        var services = SessionServices(loadSettings: { settings?.current ?? fixed })
        services.levelOne = { .engine(levelOne) }
        let host = FakeHost(services: services)
        host.focus()
        return (host, pinyin)
    }

    private static func change(_ side: Key.Side, down: Bool, at time: Double) -> ModifierChange {
        ModifierChange(key: .modifier(.option, side), modifiers: down ? [.option, Modifiers.side(side, of: .option)] : [],
                       timestamp: time)
    }

    /// The right Option down at `time` and up a tenth of a second later, as the session is told.
    private func tap(_ host: FakeHost, at time: Double) {
        host.modifiers(Self.change(.right, down: true, at: time))
        host.modifiers(Self.change(.right, down: false, at: time + 0.1))
    }

    // MARK: Item 25

    /// Item 25 (`EnglishWordsEngine.onPage`, EnglishWordsEngine.swift:314). An English word among pinyin's candidates
    /// is highlighted (↓) and the right Option is tapped: the tap is "`", the shape codes' key, which narrows pinyin's
    /// candidates; it is no punctuation mark that puts the highlighted word in before it. Nothing goes into the field,
    /// and the pinyin typed is still there, "`" after it. (Today the word and "`" go in together, "Yuzu`", and the
    /// pinyin is gone.)
    @Test func aTapWithAnEnglishWordHighlightedKeepsThePinyin() {
        let pinyin = Review076ShapeEngine()
        let mixed = EnglishWordsEngine(base: pinyin, dictionary: EnglishDictionary([]), words: ["Yuzu"])
        let (host, _) = host(engine: mixed)
        host.type("yuzu")
        host.press(FakeHost.down)
        let rows = host.panel?.rows.map(\.text) ?? []
        #expect(rows.contains("Yuzu"), "the English word is on the page: \(rows)")
        let state = host.composer.engineState
        #expect(state.candidates.indices.contains(state.highlighted) && state.candidates[state.highlighted].text == "Yuzu",
                "the English word is highlighted: \(state)")
        tap(host, at: 1)
        #expect(host.document.isEmpty, "the tap put \"\(host.document)\" into the field")
        #expect(pinyin.rawInput == "yuzu`", "the pinyin typed is \"\(pinyin.rawInput)\", not \"yuzu`\"")
        #expect(host.composer.engineState.isComposing, "nothing is composed any more")
    }

    // MARK: Item 26

    /// Item 26 (`Composer.optionTapHeld`, Composer+OptionTap.swift:10). The right Option held for seconds, the system
    /// telling it down again meanwhile (the same key, still down: a repeated change, as Caps Lock's light or another
    /// app's event tap makes one): the hold began when the key first went down, so its release is no tap. (Today the
    /// second "down" forgets the press and the third arms a new one, timed from then: the release a moment later counts
    /// as a tap and types "`".)
    @Test func aLongHoldToldDownAgainIsNoTap() {
        let (host, pinyin) = host()
        host.type("yu")
        host.modifiers(Self.change(.right, down: true, at: 10))
        host.modifiers(Self.change(.right, down: true, at: 12))
        host.modifiers(Self.change(.right, down: true, at: 14))
        host.modifiers(Self.change(.right, down: false, at: 14.1))
        #expect(pinyin.rawInput == "yu", "a hold of 4.1 s typed \"`\": the pinyin is \"\(pinyin.rawInput)\"")
    }

    /// Item 26, the other side of it: a down told twice within the tap's time is still that one press, and its release
    /// is the tap. (Today the second "down" forgets the press: the tap does nothing.)
    @Test func aTapToldDownTwiceIsStillATap() {
        let (host, pinyin) = host()
        host.type("yu")
        host.modifiers(Self.change(.right, down: true, at: 20))
        host.modifiers(Self.change(.right, down: true, at: 20.02))
        host.modifiers(Self.change(.right, down: false, at: 20.1))
        #expect(pinyin.rawInput == "yu`", "the tap typed nothing: the pinyin is \"\(pinyin.rawInput)\"")
    }

    // MARK: Item 27

    /// Item 27 (`InputSession.modifiers`, InputSession.swift:1064). Clipboard history's panel (⌃V) shows over a
    /// command's text with pinyin being typed in it ("@" and pinyin: `Composer.takesPasteAnywhere`): its keys are the
    /// panel's, and what is typed behind it isn't shown. A tap of the right Option changes nothing of the pinyin behind
    /// the panel. (Today it appends "`" to it, unseen.)
    @Test func aTapUnderClipboardHistoryLeavesThePinyinBehindIt() {
        let (host, pinyin) = host()
        host.clipboardNow = Date(timeIntervalSince1970: 1_800_000_000)
        host.clipboardHistory = [ClipboardHistoryItem(text: "copied", copiedAt: host.clipboardNow - 60)]
        host.clipboard = .text("copied")
        host.keepClipboardHistory()
        host.type("@yu")
        host.press(FakeHost.controlV)
        guard host.session.clipboardShown, pinyin.rawInput == "yu" else {
            Issue.record("⌃V with \"@\" and pinyin typed didn't show clipboard history over it (pinyin \"\(pinyin.rawInput)\"): nothing to look at")
            return
        }
        tap(host, at: 30)
        #expect(host.session.clipboardShown, "the tap closed clipboard history")
        #expect(pinyin.rawInput == "yu", "under clipboard history the tap made the pinyin \"\(pinyin.rawInput)\"")
    }

    // MARK: Item 28

    /// Item 28 (`Composer.optionTapHeld`, Composer+OptionTap.swift:18). The right Option goes down while pinyin is
    /// typed and its release never reaches the composer: secure input took the keys meanwhile (a password prompt), and
    /// a change of the modifiers told with secure input on stops at the session (`InputSession.modifiers`). Once it is
    /// off again, the next tap is a tap. (Today the press remembered from before makes the next "down" count as not
    /// alone: that tap does nothing, and only the one after it works.)
    @Test func aTapAfterAReleaseLostToSecureInputIsATap() {
        let (host, pinyin) = host()
        host.type("yu")
        host.modifiers(Self.change(.right, down: true, at: 40))
        host.secure = true
        host.modifiers(Self.change(.right, down: false, at: 40.1))
        host.secure = false
        guard pinyin.rawInput == "yu" else {
            Issue.record("the release told with secure input on changed the pinyin (\"\(pinyin.rawInput)\"): not the case the finding is about")
            return
        }
        tap(host, at: 50)
        #expect(pinyin.rawInput == "yu`", "the first tap after a lost release typed nothing: the pinyin is \"\(pinyin.rawInput)\"")
    }

    /// Item 28, the field left with the key down (another field, another app) and focused again: pinyin typed anew
    /// there, the next tap is a tap. (It is today too, a key typed since having ended the press: a guard for the fix.)
    @Test func aTapAfterTheFieldWasLeftWithTheKeyDownIsATap() {
        let (host, pinyin) = host()
        host.modifiers(Self.change(.right, down: true, at: 60))
        host.send(.blur)
        host.focus()
        host.type("yu")
        tap(host, at: 70)
        #expect(pinyin.rawInput == "yu`", "the pinyin is \"\(pinyin.rawInput)\"")
    }

    // MARK: Item 29

    /// Item 29 (`InputSession.settings`, InputSession.swift:633). Shape codes are turned off in the config file while
    /// the field keeps the focus (iCloud brought another Mac's setting, the file was edited): the session reads the
    /// settings at each change of the modifiers already (the switch key: `services.loadSettings().switchKey`), and the
    /// right Option's tap goes by the shape codes as they are then, not as they were when the field took the focus.
    ///
    /// Seam for the implementer: none new. `InputSession.modifiers` takes `Config.typedShapeCode` from the settings it
    /// reads there (as `composer.shiftTapSwitches`), so no event of the shell's is needed; `SessionEvent.configChanged`
    /// still applies everything else.
    @Test func shapeCodesTurnedOffElsewhereStopTheTapWithoutAChangeOfFocus() {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.chinese, .english])
        config.shapeCode = "moqi"
        config.actionKey = .optionSpace
        let settings = Review076Settings(config)
        let (host, pinyin) = host(settings)
        host.type("yu")
        settings.change { $0.shapeCode = nil }
        tap(host, at: 80)
        #expect(pinyin.rawInput == "yu", "shape codes are off, and the tap typed \"`\": \"\(pinyin.rawInput)\"")
    }

    /// Item 29, turned on elsewhere: the tap is "`" at once, the focus where it was.
    @Test func shapeCodesTurnedOnElsewhereMakeTheTapWorkWithoutAChangeOfFocus() {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.chinese, .english])
        config.shapeCode = nil
        config.actionKey = .optionSpace
        let settings = Review076Settings(config)
        let (host, pinyin) = host(settings)
        host.type("yu")
        settings.change { $0.shapeCode = "moqi" }
        tap(host, at: 90)
        #expect(pinyin.rawInput == "yu`", "shape codes are on, and the tap typed nothing: \"\(pinyin.rawInput)\"")
    }
}
