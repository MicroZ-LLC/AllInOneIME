import Testing
@testable import AllInOneIMECore

/// ← → in a command's text: the cursor moves as in any text field, and typing, pinyin, ⌫, a paste and
/// speech go in where it is; it never goes into the command ("improve › ").
extension ComposerTests {
    func arrow(_ code: UInt16, _ mods: KeyModifiers = []) -> KeyEvent { KeyEvent(keyCode: code, characters: "", modifiers: mods) }

    @Test func theCursorMovesInACommandsText() {
        let (c, _) = improveDraft(key: .enter, english: true)
        type("helo world", c)
        #expect(c.markedText == "improve › helo world" && c.markedCursor == c.markedText.count)
        for _ in 0..<7 { _ = c.handleKeyDown(arrow(VirtualKey.left)) }
        #expect(c.markedCursor == "improve › hel".count)
        type("l", c)
        #expect(c.draft == "@improve hello world" && c.markedText == "improve › hello world" && c.markedCursor == "improve › hell".count)
        // ⌫ before the cursor; ⌘← to the start of the text, never into the command; ⌫ there does nothing.
        _ = c.handleKeyDown(backspaceKey)
        #expect(c.draft == "@improve helo world" && c.markedCursor == "improve › hel".count)
        type("l", c)
        _ = c.handleKeyDown(arrow(VirtualKey.left, .command))
        _ = c.handleKeyDown(arrow(VirtualKey.left))
        #expect(c.markedCursor == "improve › ".count)
        _ = c.handleKeyDown(backspaceKey)
        #expect(c.draft == "@improve hello world" && c.markedText == "improve › hello world")
        // ⌥→ a word at a time; fn⌫ deletes after the cursor; → at the end stays there.
        _ = c.handleKeyDown(arrow(VirtualKey.right, .option))
        #expect(c.markedCursor == "improve › hello".count)
        _ = c.handleKeyDown(arrow(VirtualKey.forwardDelete))
        #expect(c.draft == "@improve helloworld" && c.markedCursor == "improve › hello".count)
        _ = c.handleKeyDown(arrow(VirtualKey.end))
        _ = c.handleKeyDown(arrow(VirtualKey.right))
        type("!", c)
        #expect(c.draft == "@improve helloworld!" && c.markedCursor == c.markedText.count)
        // ⏎ runs the whole text, wherever the cursor is.
        _ = c.handleKeyDown(arrow(VirtualKey.home))
        #expect(c.handleKeyDown(enterKey).effects.first == .startConversion(input: "helloworld!", id: 1))
    }

    @Test func pinyinAndPastesGoInAtTheCursor() {
        let (c, _) = improveDraft(key: .enter)
        type("nihao", c)
        _ = c.handleKeyDown(spaceKey)  // picks 你好
        #expect(c.draft == "@improve 你好")
        _ = c.handleKeyDown(arrow(VirtualKey.left))
        type("nihao", c)
        // The pinyin being typed shows at the cursor, before what follows it.
        #expect(c.markedText.hasPrefix("improve › 你") && c.markedText.hasSuffix("好") && c.markedText.contains("ni"))
        _ = c.handleKeyDown(spaceKey)  // picks 你好, in at the cursor
        #expect(c.draft == "@improve 你你好好" && c.markedCursor == "improve › 你你好".count)
        // A paste (⌘V) goes in at the cursor too.
        #expect(paste("们", into: c) == [.updateMarkedText, .showPanel])
        #expect(c.draft.hasSuffix("们好"))
        // A new command (the draft replaced) puts the cursor back at the end.
        _ = c.handleKeyDown(escKey)
        _ = c.handleKeyDown(at)
        type("q", c)
        _ = c.handleKeyDown(tab)
        type("abc", c)
        #expect(c.markedCursor == c.markedText.count)
    }
}
