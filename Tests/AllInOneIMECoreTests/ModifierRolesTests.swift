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

    /// AltGr, which Windows reports as Ctrl+Alt: with a key that types, text, never a ⌃⌥ shortcut.
    @Test func altGrTypesText() {
        let altGr = WindowsKeyCodes.markingAltGraph([.control, .option], rightAltDown: true)
        #expect(altGr == [.control, .option, .altGraph])
        #expect(WindowsKeyCodes.markingAltGraph([.control, .option], rightAltDown: false) == [.control, .option])  // left Alt
        #expect(WindowsKeyCodes.markingAltGraph(.option, rightAltDown: true) == .option)  // right Alt alone, no AltGr
        // AltGr+Q on a German layout types "@": the command palette opens, as for "@" typed anywhere.
        let (c, _) = composer()
        c.modifierRoles = .windows
        let at = pc(.character, 0x14, "@", altGr)
        #expect(at.modifiers.isEmpty && at.printableText == "@")
        _ = c.handleKeyDown(at)
        #expect(c.draft == "@")
        // AltGr+A on a Polish layout, in a draft: "ą" goes in, AltGr+Shift+A "Ą".
        let (d, _) = improveDraft(key: .enter, english: true)
        d.modifierRoles = .windows
        _ = d.handleKeyDown(pc(.character, 0x04, "ą", altGr))
        let capital = pc(.character, 0x04, "Ą", altGr.union(.shift))
        #expect(capital.modifiers == .shift)
        _ = d.handleKeyDown(capital)
        #expect(d.draft == "@improve ąĄ")
        // Ctrl+Alt with the left Alt, or with a key that types nothing, stays Ctrl+Alt.
        #expect(pc(.character, 0x14, "", altGr).modifiers == [.control, .option])
        #expect(pc(.enter, 0x28, "\r", altGr).modifiers == [.control, .option])
        #expect(pc(.character, 0x14, "q", [.control, .option]).printableText == nil)
    }

    /// Shift+keypad 7 with Num Lock on, as Windows sends it: real Shift down, its own Shift up (E0 AA), Home, its own
    /// Shift down (E0 2A), real Shift up. No tap of Shift: the language stays.
    @Test func windowsOwnShiftIsNoTap() {
        typealias Change = (scanCode: UInt8, extended: Bool, down: Bool)
        let numLockSeven: [Change] = [(0x2A, false, true), (0x2A, true, false), (0x2A, true, true), (0x2A, false, false)]
        #expect(WindowsKeyCodes.isFakeShift(scanCode: 0x2A, extended: true) && WindowsKeyCodes.isFakeShift(scanCode: 0x36, extended: true))
        #expect(!WindowsKeyCodes.isFakeShift(scanCode: 0x2A, extended: false) && !WindowsKeyCodes.isFakeShift(scanCode: 0x36, extended: false))
        #expect(WindowsKeyCodes.key(virtualKey: 0x10, usage: WindowsKeyCodes.usage(scanCode: 0x2A, extended: true)) == .other)

        /// The changes as a shell gives them (`drops`: it leaves out Windows' own, as it should), with Home between.
        func language(after changes: [Change], drops: Bool) -> Language {
            let c = Composer(engine: FakeEngine(), actionKey: .enter)
            c.modifierRoles = .windows
            var time = 1.0
            for (i, change) in changes.enumerated() {
                if i == 2 { _ = c.handleKeyDown(pc(.home, 0x4A)) }
                guard !drops || !WindowsKeyCodes.isFakeShift(scanCode: change.scanCode, extended: change.extended) else { continue }
                let usage = WindowsKeyCodes.usage(scanCode: change.scanCode, extended: change.extended)
                let key = WindowsKeyCodes.key(virtualKey: 0x10, usage: usage)
                _ = c.handleFlagsChanged(key: key, modifiers: change.down ? [.shift, .leftShift] : [], timestamp: time)
                time += 0.05
            }
            return c.inputLanguage
        }
        let start = Composer(engine: FakeEngine(), actionKey: .enter).inputLanguage
        #expect(language(after: numLockSeven, drops: true) == start)
        #expect(language(after: numLockSeven, drops: false) == start)  // even let through, Windows' own is no Shift
        // A real tap still switches.
        #expect(language(after: [(0x2A, false, true), (0x2A, false, false)], drops: true) != start)
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
