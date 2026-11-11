import CoreGraphics
import Foundation
import Testing
@testable import AllInOneIMECore

/// Candidates in a row (`Config.candidateLayout`): ← → move the highlight and ↑↓ turn the page, the engine given
/// the keys of a column for that; in a column ↑↓ move and ← → turn the page. One @'s candidates and a follow-up's, a line of
/// pills, are a row in either layout. (With the real librime: CandidateKeysRimeTests.)
@Suite(MacTerms())
struct HorizontalCandidatesTests {
    let left = KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}")
    let right = KeyEvent(keyCode: VirtualKey.right, characters: "\u{F703}")

    func pinyin(horizontal: Bool) -> (Composer, FakeEngine) {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        c.horizontalCandidates = horizontal
        for ch in "nihao" { _ = c.handleKeyDown(k(String(ch))) }
        engine.keys = []
        return (c, engine)
    }

    @Test func arrowsInARow() {
        let (c, e) = pinyin(horizontal: true)
        for key in [right, left, downKey, upKey] { #expect(c.handleKeyDown(key).handled) }
        #expect(e.keys.map(\.keycode) == [RimeKey.down, RimeKey.up, RimeKey.pageDown, RimeKey.pageUp])
        // → is the next candidate, as ↓ in a column.
        _ = c.handleKeyDown(right)
        #expect(c.engineState.highlighted == 1 && c.engineState.isComposing && c.draft.isEmpty)
    }

    @Test func arrowsInAColumn() {
        // ↑↓ are the engine's own (down the column, on to the next page from the last); ← → turn the page.
        let (c, e) = pinyin(horizontal: false)
        for key in [right, left, downKey, upKey] { #expect(c.handleKeyDown(key).handled) }
        #expect(e.keys.map(\.keycode) == [RimeKey.pageDown, RimeKey.pageUp, RimeKey.down, RimeKey.up])
        _ = c.handleKeyDown(downKey)
        #expect(c.engineState.highlighted == 1 && c.engineState.isComposing && c.draft.isEmpty)
        // ⌥← ⌥→ stay librime's (a syllable at a time), as in a row.
        e.keys = []
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.right, characters: "\u{F703}", modifiers: .option))
        #expect(e.keys.map(\.keycode) == [RimeKey.right])
    }

    @Test(arguments: [false, true])
    func theSameKeysPutNothingIn(horizontal: Bool) {
        // Every arrow and page key leaves the composition as it is: nothing is picked or committed.
        let (c, _) = pinyin(horizontal: horizontal)
        for key in [right, left, downKey, upKey, k("="), k("-")] {
            let response = c.handleKeyDown(key)
            #expect(response.handled && commits(response.effects).isEmpty && c.engineState.isComposing && c.draft.isEmpty)
        }
    }

    @Test func onlyPlainArrowsWhileAWordIsTyped() {
        // ⌥← ⌥→ stay librime's (a syllable at a time); -/= turn the page as before.
        let (c, e) = pinyin(horizontal: true)
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.left, characters: "\u{F702}", modifiers: .option))
        _ = c.handleKeyDown(k("="))
        #expect(e.keys.map(\.keycode) == [RimeKey.left, 0x3D])
        // Nothing typed: the arrows are the app's.
        let d = Composer(engine: FakeEngine(), actionKey: .enter)
        d.horizontalCandidates = true
        #expect(!d.handleKeyDown(right).handled && !d.handleKeyDown(downKey).handled)
        // In a command's text, the cursor moves as before.
        for ch in "@imp" { _ = d.handleKeyDown(ch == "@" ? KeyEvent(keyCode: 0x13, characters: "@", modifiers: .shift) : k(String(ch))) }
        _ = d.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        for ch in "ab " { _ = d.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) }
        d.setInputMode(.english)
        _ = d.handleKeyDown(left)
        #expect(d.markedCursor < d.markedText.count)
    }

    @Test func hindiInARow() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.hindiTables = PackData.hindi
        c.inputLanguages = [.english, .hindi]
        c.setInputMode(.hindi)
        c.horizontalCandidates = true
        for ch in "kamra" { _ = c.handleKeyDown(k(String(ch))) }
        _ = c.handleKeyDown(right)
        #expect(c.engineState.highlighted == 1)
        _ = c.handleKeyDown(left)
        #expect(c.engineState.highlighted == 0)
        // One page of spellings: ↑↓ do nothing (they don't put the word in).
        let down = c.handleKeyDown(downKey), up = c.handleKeyDown(upKey)
        #expect(down.handled && up.handled && commits(down.effects + up.effects).isEmpty && c.engineState.isComposing)
    }

    @Test func hindiInAColumn() {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.hindiTables = PackData.hindi
        c.inputLanguages = [.english, .hindi]
        c.setInputMode(.hindi)
        for ch in "kamra" { _ = c.handleKeyDown(k(String(ch))) }
        _ = c.handleKeyDown(downKey)
        #expect(c.engineState.highlighted == 1)
        // One page of spellings: ← → turn none (nor put the word in).
        let on = c.handleKeyDown(right), back = c.handleKeyDown(left)
        #expect(on.handled && back.handled && commits(on.effects + back.effects).isEmpty && c.engineState.highlighted == 1)
    }

    /// One @'s pinyin candidates are a line of pills: a row in either layout, ← → moving along it (on to the next page
    /// from its last), - = turning its page; ↑↓ stay one @'s rows'. The pill highlighted is what Space picks.
    @Test(arguments: [false, true])
    func oneAtsCandidatesAreARow(horizontal: Bool) throws {
        let engine = FakeEngine()
        let c = Composer(engine: engine, voiceEnabled: false, actionKey: .enter)
        c.commands = Command.builtins
        c.horizontalCandidates = horizontal
        _ = c.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        for ch in "nihao" { _ = c.handleKeyDown(k(String(ch))) }
        try #require(c.oneAt != nil && c.engineState.isComposing && c.engineState.candidates.count > 1)
        engine.keys = []
        let row = c.oneAtHighlighted
        for key in [right, left, k("="), k("-")] { #expect(c.handleKeyDown(key).handled) }
        #expect(engine.keys.map(\.keycode) == [RimeKey.down, RimeKey.up, 0x3D, 0x2D])
        #expect(c.oneAtHighlighted == row && c.engineState.isComposing)
        // ↑↓: one @'s rows, not the candidates.
        engine.keys = []
        _ = c.handleKeyDown(downKey)
        #expect(engine.keys.isEmpty && c.oneAtHighlighted == row + 1)
        // → highlights the second pill: the panel shows it so.
        _ = c.handleKeyDown(right)
        let model = PanelPresenter(config: .default, language: "en").model(for: c)
        #expect(c.engineState.highlighted == 1 && model.candidatesHighlighted == 1 && model.candidates == "1 你好   2 拟好")
    }

    /// A follow-up's pinyin after results: its candidates are a line of pills too, ← → moving along it in either layout.
    @Test(arguments: [false, true])
    func aFollowUpsCandidatesAreARow(horizontal: Bool) throws {
        let engine = FakeEngine()
        let c = Composer(engine: engine, actionKey: .enter)
        c.horizontalCandidates = horizontal
        c.setInputMode(.english)
        _ = c.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        for ch in "i" { _ = c.handleKeyDown(k(String(ch))) }
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        for ch in "hello" { _ = c.handleKeyDown(k(String(ch))) }
        _ = c.handleKeyDown(enterKey)
        _ = c.receive(ConversionResult(versions: [CandidateLine("Hi."), CandidateLine("Howdy.")]), isFinal: true, id: 1)
        try #require(c.canRefine)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: .shift, timestamp: 1)
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftShift, modifiers: [], timestamp: 1.1)
        for ch in "nihao" { _ = c.handleKeyDown(k(String(ch))) }
        try #require(c.refineIsComposing)
        let highlighted = c.highlighted
        engine.keys = []
        _ = c.handleKeyDown(right)
        #expect(engine.keys.map(\.keycode) == [RimeKey.down] && c.engineState.highlighted == 1 && c.highlighted == highlighted)
        #expect(PanelPresenter(config: .default, language: "en").model(for: c).candidatesHighlighted == 1)
        _ = c.handleKeyDown(left)
        #expect(engine.keys.map(\.keycode) == [RimeKey.down, RimeKey.up] && c.refineLine == "nihao")
    }

    @Test func theSetting() throws {
        // In a row by default: a new install, a file from before the setting (an update), a value a later version added.
        #expect(Config.default.candidateLayout == .horizontal && Config.fresh.candidateLayout == .horizontal)
        let missing = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(missing.candidateLayout == .horizontal)
        let unknown = try JSONDecoder().decode(Config.self, from: Data(#"{"candidateLayout": "diagonal"}"#.utf8))
        #expect(unknown.candidateLayout == .horizontal)
        // Chosen: kept.
        let column = try JSONDecoder().decode(Config.self, from: Data(#"{"candidateLayout": "vertical"}"#.utf8))
        #expect(column.candidateLayout == .vertical)
        #expect(String(decoding: try JSONEncoder().encode(column), as: UTF8.self).contains(#""candidateLayout":"vertical""#))
        var config = Config.default
        config.candidateLayout = .horizontal
        let json = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(json.contains(#""candidateLayout":"horizontal""#))
        #expect(try JSONDecoder().decode(Config.self, from: Data(json.utf8)).candidateLayout == .horizontal)
    }

    @Test func cellsFlowIntoLines() {
        let cell = CGSize(width: 100, height: 30)
        let frames = CandidateLayout.flow(Array(repeating: cell, count: 5), spacing: 2, lineSpacing: 4, maxWidth: 320)
        // Three fit in 320 (100 + 2 + 100 + 2 + 100), the fourth starts the next line.
        #expect(frames.map(\.origin) == [CGPoint(x: 0, y: 0), CGPoint(x: 102, y: 0), CGPoint(x: 204, y: 0),
                                         CGPoint(x: 0, y: 34), CGPoint(x: 102, y: 34)])
        // One wider than the line still gets one of its own.
        let wide = CandidateLayout.flow([CGSize(width: 50, height: 30), CGSize(width: 900, height: 30)], spacing: 2, lineSpacing: 4, maxWidth: 320)
        #expect(wide.map(\.minY) == [0, 34] && wide[1].minX == 0)
        // A click on the second cell picks it.
        #expect(CandidateLayout.row(at: CGPoint(x: 150, y: 10), frames: frames, pickable: Array(repeating: true, count: 5)) == 1)
        #expect(CandidateLayout.row(at: CGPoint(x: 101, y: 10), frames: frames, pickable: Array(repeating: true, count: 5)) == nil)
    }
}
