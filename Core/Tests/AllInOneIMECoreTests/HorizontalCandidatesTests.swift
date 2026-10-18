import CoreGraphics
import Foundation
import Testing
@testable import AllInOneIMECore

/// Candidates in a row (`Config.candidateLayout`): ← → move the highlight and ↑↓ turn the page, the engine given
/// the keys of a column for that; in a column every key is as before.
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

    @Test func aColumnIsAsBefore() {
        let (c, e) = pinyin(horizontal: false)
        for key in [right, left, downKey, upKey] { _ = c.handleKeyDown(key) }
        #expect(e.keys.map(\.keycode) == [RimeKey.right, RimeKey.left, RimeKey.down, RimeKey.up])
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
