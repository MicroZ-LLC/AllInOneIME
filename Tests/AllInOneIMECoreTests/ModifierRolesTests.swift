import Testing
@testable import AllInOneIMECore

/// What a modifier does is the system's (`ModifierRoles`): the same keys under the Mac's roles and Windows', the
/// events made as each system's shell makes them (`KeyEvent(key:usage:…)` for Windows').
extension ComposerTests {
    /// A Windows key-down: Ctrl+C is `pc(.character, 0x06, "c", .control)`.
    func pc(_ key: Key, _ usage: UInt16, _ characters: String = "", _ modifiers: Modifiers = []) -> KeyEvent {
        KeyEvent(key: key, usage: usage, characters: characters, modifiers: modifiers)
    }

    func pcArrow(_ arrow: Key.Arrow, _ modifiers: Modifiers = []) -> KeyEvent {
        pc(.arrow(arrow), [.left: 0x50, .right: 0x4F, .up: 0x52, .down: 0x51][arrow]!, "", modifiers)
    }

    @Test func aWordAtATimeAndTheEdgesAreTheRoles() {
        let (c, _) = improveDraft(key: .enter, english: true)
        c.modifierRoles = .windows
        type("hello big world", c)
        // Ctrl+← → a word at a time (Ctrl being the shortcuts' modifier too), Home and End to the edges.
        _ = c.handleKeyDown(pcArrow(.left, .control))
        #expect(c.markedCursor == "improve › hello big ".count)
        #expect(c.handleKeyDown(pcArrow(.left, .control)).handled)
        #expect(c.markedCursor == "improve › hello ".count)
        _ = c.handleKeyDown(pc(.home, 0x4A))
        #expect(c.markedCursor == "improve › ".count)
        _ = c.handleKeyDown(pcArrow(.right, .control))
        #expect(c.markedCursor == "improve › hello".count)
        _ = c.handleKeyDown(pc(.end, 0x4D))
        #expect(c.markedCursor == c.markedText.count)
        // There Alt+← is one character, as ⌃← is on the Mac; ⌥← a word on the Mac, ⌘← the start.
        _ = c.handleKeyDown(pcArrow(.left, .option))
        #expect(c.markedCursor == c.markedText.count - 1)
        c.modifierRoles = .mac
        _ = c.handleKeyDown(arrow(VirtualKey.right))
        _ = c.handleKeyDown(arrow(VirtualKey.left, .control))
        #expect(c.markedCursor == c.markedText.count - 1)
        _ = c.handleKeyDown(arrow(VirtualKey.left, .option))
        #expect(c.markedCursor == "improve › hello big ".count)
        _ = c.handleKeyDown(arrow(VirtualKey.left, .command))
        #expect(c.markedCursor == "improve › ".count)
        #expect(c.draft == "@improve hello big world")
    }

    @Test func copyAndPasteAreThePrimaryModifiers() {
        let (c, _) = translating()
        c.modifierRoles = .windows
        _ = c.receive(final, isFinal: true, id: 1)
        #expect(c.handleKeyDown(pc(.character, 0x06, "c", .control)) == .consumed([.copy("Hi there."), .notice("已复制")]))
        // The Windows key is no shortcut of the input method's there.
        #expect(c.handleKeyDown(pc(.character, 0x06, "c", .command)).effects.first != .copy("Hi there."))

        func asksForTheClipboard(_ c: Composer, _ event: KeyEvent) -> Bool {
            c.handleKeyDown(event).effects.contains { if case .readClipboard = $0 { true } else { false } }
        }
        let ctrlV = pc(.character, 0x19, "v", .control)
        let (w, _) = improveDraft(key: .enter)
        w.modifierRoles = .windows
        #expect(asksForTheClipboard(w, ctrlV))
        // Where the app pastes on its own (`pastesIntoDraft` off): the Mac still pastes ⌃V into the draft, Windows has
        // no second paste key.
        let (m, _) = improveDraft(key: .enter)
        m.pastesIntoDraft = false
        #expect(asksForTheClipboard(m, KeyEvent(keyCode: 0x09, characters: "v", modifiers: .control)))
        #expect(!asksForTheClipboard(m, pasteKey))
        let (n, _) = improveDraft(key: .enter)
        n.pastesIntoDraft = false
        n.modifierRoles = .windows
        #expect(!asksForTheClipboard(n, ctrlV))
    }

    @Test func theActionKeysModifierIsTheRoles() {
        // Ctrl+Space is ⌥Space there; Alt+Space (the window's system menu) is not.
        let (c, _) = improveDraft(key: .optionSpace)
        c.modifierRoles = .windows
        type("nihao", c)
        #expect(!startsConversion(c.handleKeyDown(pc(.space, 0x2C, " ", .option)).effects))
        #expect(startsConversion(c.handleKeyDown(pc(.space, 0x2C, " ", .control)).effects))

        // A tap of either Ctrl is the Option tap; a tap of Alt is not.
        func change(_ c: Composer, _ kind: Key.ModifierKind, _ side: Key.Side, down: Bool, at time: Double) -> [Composer.Effect] {
            c.handleFlagsChanged(key: .modifier(kind, side), modifiers: down ? [Modifiers.kind(kind), Modifiers.side(side, of: kind)] : [],
                                 timestamp: time)
        }
        let (t, _) = improveDraft(key: .optionTap)
        t.modifierRoles = .windows
        type("nihao", t)
        _ = change(t, .option, .left, down: true, at: 1)
        #expect(!startsConversion(change(t, .option, .left, down: false, at: 1.1)))
        _ = change(t, .control, .left, down: true, at: 2)
        #expect(startsConversion(change(t, .control, .left, down: false, at: 2.1)))

        // The right Ctrl held dictates; the right Alt (AltGr on many layouts) doesn't.
        let (v, _) = composer()
        v.modifierRoles = .windows
        #expect(change(v, .option, .right, down: true, at: 1).isEmpty)
        _ = change(v, .option, .right, down: false, at: 1.1)
        #expect(change(v, .control, .right, down: true, at: 2) == [.armVoice(delay: Composer.voiceArmDelay)])
    }

    @Test func theMacsRolesAreTheMacsKeys() {
        let mac = ModifierRoles.mac
        #expect(mac.primary == .command && mac.word == .option && mac.lineEdge == .command && mac.pasteAnywhere == .control)
        #expect(mac.voiceHold.key == MacKeyCodes.key(VirtualKey.rightOption) && mac.actionTap == .option)
        let windows = ModifierRoles.windows
        #expect(windows.voiceHold.key == WindowsKeyCodes.key(virtualKey: 0xA3, usage: 0xE4))  // VK_RCONTROL
        #expect(windows.lineEdge == nil && windows.pasteAnywhere == nil)
        // A Composer starts with the Mac's.
        #expect(Composer(engine: FakeEngine(), actionKey: .enter).modifierRoles == mac)
    }
}
