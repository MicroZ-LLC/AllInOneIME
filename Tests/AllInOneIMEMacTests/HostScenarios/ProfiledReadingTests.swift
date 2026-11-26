import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Testing

/// The input method's reading and anchoring code (the Mac library's, moved there from the input method's controller so
/// that it runs in-process here), over a field of each host profile (`ProfiledTextClient`): what each tells it, and what
/// it makes of that.
@MainActor
struct ProfiledReadingTests {
    /// How the input method reads a field, with nothing of its process's to tell (no secure input, no Accessibility).
    func reading(_ client: ProfiledTextClient) -> FieldReading {
        FieldReading(isTerminal: { _ in false }, secureInputActive: { false },
                     chromiumApp: { [profile = client.profile] _ in profile.isChromium })
    }

    func field(_ profile: HostProfile, _ markup: String) throws -> ProfiledTextClient {
        let text = try HostText(markup: markup)
        return ProfiledTextClient(profile, text: text.text, selection: text.selection, marked: text.marked)
    }

    // MARK: What the field tells

    /// The text around the caret (`FieldTextReading`): where the field tells its length; where it tells 0 (Chromium's,
    /// whatever its text), read back up to the caret and after it as far as it reads; nothing from a field that tells no
    /// caret (a terminal, WeChat).
    @Test(arguments: HostProfile.allCases)
    func theTextAroundTheCaret(_ profile: HostProfile) throws {
        let client = try field(profile, "Hello wor|ld")
        let text = FieldTextReading.read(from: client, before: 1500, after: 200, purpose: "test",
                                         secureInputActive: { false }, isTerminal: { _ in false })
        switch profile {
        case .nstextview, .chromium, .electron, .webkit, .qt:
            #expect(text == FieldText(before: "Hello wor", after: "ld"), "\(String(describing: text))")
        case .tellsnothing:
            #expect(text == nil, "\(String(describing: text))")
        }
        // Never during secure input, nor in a terminal: the field isn't even asked its length.
        client.resetCalls()
        #expect(FieldTextReading.read(from: client, before: 1500, after: 200, purpose: "test", secureInputActive: { true },
                                      isTerminal: { _ in false }) == nil)
        #expect(FieldTextReading.read(from: client, before: 1500, after: 200, purpose: "test", secureInputActive: { false },
                                      isTerminal: { _ in true }) == nil)
        #expect(client.calls["length"] == nil)
    }

    /// What a key reads (`FieldReading.context`): the selection's range, the character before the caret, the selected
    /// text, as each field tells them.
    @Test(arguments: HostProfile.allCases)
    func whatAKeyReads(_ profile: HostProfile) throws {
        let client = try field(profile, "Hi [Bob]")
        let context = reading(client).context(in: client) { _ in [.selectedRange, .beforeCaret, .selection] }
        #expect(context.field == FieldInfo(app: profile.app))
        #expect(context.read == [.selectedRange, .beforeCaret, .selection])
        if profile == .tellsnothing {
            #expect(context.selectedRange == nil && context.selection == nil && context.beforeCaret == .unknown)
        } else {
            #expect(context.selectedRange == 3..<6)
            #expect(context.selection == Composer.Selection(text: "Bob", range: 3..<6))
            #expect(context.beforeCaret == .nothing)  // a selection: nothing before a caret
        }
        let caret = try field(profile, "Hi Bob|")
        let before = reading(caret).context(in: caret) { _ in [.beforeCaret] }.beforeCaret
        #expect(before == (profile == .tellsnothing ? .unknown : .text("b")))
    }

    /// Chromium's view during a key tells the ranges as they were when the key came: the input method's marked text is
    /// in it only once the run loop turned.
    @Test(arguments: [HostProfile.chromium, .electron, .nstextview])
    func theRangesDuringAKey(_ profile: HostProfile) throws {
        let client = try field(profile, "Hi |")
        client.beginTurn()
        client.setMarkedText("ni", selectionRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let during = (FieldReading.markedLength(client), client.selectedRange())
        client.endTurn()
        let after = (FieldReading.markedLength(client), client.selectedRange())
        #expect(after.0 == 2 && after.1 == NSRange(location: 5, length: 0))
        if profile.isChromium {
            #expect(during.0 == nil && during.1 == NSRange(location: 3, length: 0), "the old ranges")
        } else {
            #expect(during.0 == after.0 && during.1 == after.1)
        }
    }

    /// Chromium tells a substring only within ±100 UTF-16 units of its caret, and none past its text's end.
    @Test func chromiumsSubstringsAreNearTheCaret() throws {
        let long = String(repeating: "a", count: 300)
        let client = try field(.chromium, long + "|" + long)
        #expect(client.attributedSubstring(from: NSRange(location: 250, length: 50))?.string == String(repeating: "a", count: 50))
        #expect(client.attributedSubstring(from: NSRange(location: 150, length: 10)) == nil)
        #expect(client.attributedSubstring(from: NSRange(location: 395, length: 10)) == nil)
        let short = try field(.chromium, "Hi|")
        #expect(short.attributedSubstring(from: NSRange(location: 1, length: 5)) == nil)
        #expect(short.attributedSubstring(from: NSRange(location: 0, length: 2))?.string == "Hi")
    }

    /// WebKit reads anywhere in its text and nothing past its end; Qt only within 1024 of its caret, cut to it
    /// (`NSIntersectionRange`): a range partly past what it has reads the part it has, one wholly past it nil.
    @Test func webKitAndQtSubstrings() throws {
        let long = String(repeating: "a", count: 1100)
        let webkit = try field(.webkit, long + "|bc")
        #expect(webkit.attributedSubstring(from: NSRange(location: 0, length: 3))?.string == "aaa")
        #expect(webkit.attributedSubstring(from: NSRange(location: 1100, length: 3)) == nil)
        let qt = try field(.qt, long + "|bc")
        #expect(qt.attributedSubstring(from: NSRange(location: 0, length: 3)) == nil, "more than 1024 before the caret")
        #expect(qt.attributedSubstring(from: NSRange(location: 70, length: 10))?.string == "aaaa", "cut to what it has")
        #expect(qt.attributedSubstring(from: NSRange(location: 1100, length: 50))?.string == "bc", "cut at the end")
        #expect(qt.attributedSubstring(from: NSRange(location: 1102, length: 5)) == nil)
        // Qt's rect is its cursor's, whatever range is asked; WebKit's the range's.
        let rect = qt.firstRect(forCharacterRange: NSRange(location: 0, length: 1), actualRange: nil)
        #expect(rect.minX == ProfiledTextClient.lineOrigin.x + 1100 * 8)
        #expect(webkit.firstRect(forCharacterRange: NSRange(location: 0, length: 1), actualRange: nil).minX == ProfiledTextClient.lineOrigin.x)
    }

    /// A replacement range Qt can't place (past its text) goes in at its cursor; the others drop it (as they did).
    @Test func aReplacementRangePastTheEnd() throws {
        let qt = try field(.qt, "Hi |")
        qt.insertText("x", replacementRange: NSRange(location: 10, length: 2))
        #expect(qt.doc == "Hi x")
        let webkit = try field(.webkit, "Hi |")
        webkit.insertText("x", replacementRange: NSRange(location: 0, length: 2))
        #expect(webkit.doc == "x ")
    }

    /// Typing a result out (`TypingField`): the caret and the length as the field tells them; typed at the caret.
    @Test(arguments: HostProfile.allCases)
    func typingOut(_ profile: HostProfile) throws {
        let client = try field(profile, "Hi |")
        let typing = TypingField(client, pastesControls: false)
        #expect(typing.caret == (profile == .tellsnothing ? nil : 3))
        // Chromium, WebKit, Qt, a terminal and WeChat tell a length of 0 whatever their text: taken as told (a typo's
        // check then finds the field not as long as what was typed, and the app gets no typos).
        #expect(typing.length == (profile.tellsLength ? 3 : 0))
        var typist = TypeOut.Typist(TypeOut.plan(for: "Bob", rate: 40), start: typing.caret ?? 0, length: typing.length)
        var steps = 0
        while typist.step(in: typing) != .done, steps < 20 { steps += 1 }
        #expect(client.doc == "Hi Bob")
    }

    // MARK: The panel's anchor

    /// Where the panel goes (`FieldAnchor.place`): under the line NSTextView tells, at the rect a terminal or WeChat
    /// always tells; in Chromium, whose first key of a composition tells the page's corner, not there, and once asked
    /// again after the run loop turned, under the marked text.
    @Test(arguments: HostProfile.allCases)
    func thePanelsAnchor(_ profile: HostProfile) throws {
        let client = try field(profile, "Hi |")
        var memory = PanelAnchor.Memory(), lastByApp: [String: CGRect] = [:]
        memory.enter(PanelAnchor.Field(client: ObjectIdentifier(client), app: profile.app, session: 1))
        memory.learnWindow { (ProfiledTextClient.window, false) }
        client.beginTurn()
        client.setMarkedText("ni", selectionRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        var asked = 0
        let placed = FieldAnchor.place(in: client, app: profile.app, selection: nil, memory: &memory, lastByApp: &lastByApp,
                                       screens: [ProfiledTextClient.screen], pointer: { CGPoint(x: 5000, y: 5000) }) { _ in
            asked += 1
            return nil
        }
        client.endTurn()
        let screens = [ProfiledTextClient.screen]
        switch profile {
        case .nstextview, .webkit:
            #expect(placed.placement.source == .field && placed.placement.rect.minX == ProfiledTextClient.lineOrigin.x + 3 * 8)
            #expect(asked == 0 && lastByApp[profile.app] == placed.placement.rect)
        case .qt:
            // Qt tells its cursor's rect for any range: after the marked text here (nothing is marked in practice).
            #expect(placed.placement.source == .field && placed.placement.rect.minX == ProfiledTextClient.lineOrigin.x + 5 * 8)
            #expect(asked == 0)
        case .tellsnothing:
            #expect(placed.placement == PanelAnchor.Placement(rect: ProfiledTextClient.fixedCaret.offsetBy(dx: 0, dy: -18), source: .field))
        case .chromium, .electron:
            // The page's corner isn't trusted; nothing better known: as told, and asked again.
            #expect(placed.placement.source == .told && placed.placement.reasks && asked == 1)
            let reasked = FieldAnchor.reasked(in: client, selection: nil, memory: &memory, screens: screens)
            let marked = try #require(FieldAnchor.caretAnchor(client))
            #expect(reasked.rect == marked && PanelAnchor.trusted(marked, screens: screens, window: ProfiledTextClient.window))
        }
    }

    // MARK: The events and their copies

    /// Chromium's copy of a modifier change (the same event, 5–20 ms later) and Electron's (100 ms or more later, after
    /// the next change) are told as copies (`MacKeyEvents.copy`) and never reach the session; a change of its own is no
    /// copy.
    @Test(arguments: [HostProfile.chromium, .electron])
    func theCopiesOfAModifierChange(_ profile: HostProfile) throws {
        var events = HostEvents(profile: profile, seed: "copies")
        var echoes = ModifierEchoes(), capsLock = CapsLockCopies()
        func copy(_ event: NSEvent) -> MacKeyEvents.Copy? {
            MacKeyEvents.copy(event, now: events.now, echoes: &echoes, capsLock: &capsLock, lockOn: { false })
        }
        let shiftDown = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x02)
        let down = try #require(events.flagsChanged(keyCode: 0x38, flags: shiftDown))
        #expect(copy(down) == nil)
        events.sendsCopy(of: down)
        events.move(to: events.now + 0.08)
        let up = try #require(events.flagsChanged(keyCode: 0x38, flags: []))
        if profile == .chromium {
            // The copy came before the release.
            let first = try #require(events.nextCopy)
            #expect(first - 1000 >= 0.005 && first - 1000 <= 0.020)
        }
        #expect(copy(up) == nil)
        events.sendsCopy(of: up)
        while let event = events.takeCopy() {
            #expect(copy(event) == .echo, "\(event)")
        }
        // The next tap, its own time: no copy.
        events.move(to: events.now + 0.5)
        #expect(copy(try #require(events.flagsChanged(keyCode: 0x38, flags: shiftDown))) == nil)
        let change = MacKeyEvents.modifierChange(down, now: down.timestamp + 0.01)
        #expect(change.key == MacKeyCodes.key(0x38) && change.modifiers == [.shift, .leftShift])
        #expect(abs(change.late - 0.01) < 0.0001)
    }

    // MARK: The scenario format

    @Test func aScenarioIsReadAsTheContractWritesIt() throws {
        let scenario = try HostCase.parse(#"""
            # a comment
            NAME   an emptied chat field doesn't reuse what was typed before it
            PROFILES nstextview chromium   # two of them
            LANG   english
            TEXT   "Hi [Bob] {ni}\|#|"
            TYPE   nihao
            TYPE   "#17 \"x\""
            KEY    space enter cmd+z opt+1 shift capslock
            CLICK  inside 2
            CLICK  outside
            FOCUS  closewindow
            SWITCH abc
            APP    clears
            WAIT   300ms
            EXPECT doc "Hi Bob你好"
            EXPECT marked none
            EXPECT panel hidden
            EXPECT lang chinese
            EXPECT context before "a # b"
            EXPECT context unreadable
            EXPECT switches 1
            EXPECT calls length<=1 substring<4
            EXPECT nolost
            EXPECT doc "x"   @profile chromium   # the owner's OK
            """#, source: "test")
        #expect(scenario.name == "an emptied chat field doesn't reuse what was typed before it")
        #expect(scenario.profiles == [.nstextview, .chromium] && scenario.language == .english)
        #expect(scenario.field.text == "Hi Bob ni|#" && scenario.field.selection == NSRange(location: 3, length: 3))
        #expect(scenario.field.marked == NSRange(location: 7, length: 2))
        #expect(scenario.steps.count == 19)
        guard case let .type(quoted) = scenario.steps[1].action else { throw Failure("TYPE") }
        #expect(quoted == "#17 \"x\"")
        guard case let .keys(keys) = scenario.steps[2].action else { throw Failure("KEY") }
        #expect(keys == [HostKey(kind: .named("space")), HostKey(kind: .named("enter")), HostKey(kind: .character("z"), modifiers: ["cmd"]),
                         HostKey(kind: .character("1"), modifiers: ["opt"]), HostKey(kind: .modifierTap("shift")), HostKey(kind: .capsLock)])
        guard case let .expect(.contextBefore(context)) = scenario.steps[13].action else { throw Failure("context") }
        #expect(context == "a # b")
        guard case let .expect(.calls(budgets)) = scenario.steps[16].action else { throw Failure("calls") }
        #expect(budgets.map(\.description) == ["length<=1", "substring<4"])
        #expect(scenario.steps[17].only == nil && scenario.steps[18].only == [.chromium])
    }

    @Test(arguments: ["KEY hyper+x", "EXPECT panel maybe", "PROFILES safari", "WAIT soon", "FROB x", "TEXT \"a]\""])
    func aLineTheFormatHasNotIsAnError(_ line: String) {
        #expect(throws: HostCase.ParseError.self) { try HostCase.parse("NAME x\n" + line, source: "bad") }
    }

    struct Failure: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }
}
