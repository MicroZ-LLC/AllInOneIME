import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The runner itself (`HostRun`, `HostField`): each profile's host tells and does what the contract says, and a check
/// that fails is reported at its line. What the core should do in these hosts is the scenarios' to say.
struct HostRunTests {
    func run(_ source: String, on profile: HostProfile) throws -> (run: HostRun, failures: [HostFailure]) {
        let scenario = try HostCaseParser.parse(source, fallbackName: "inline")
        return UIText.$scopedInterface.withValue(UIText.ScopedInterface(choice: "en", commandTrigger: "@")) {
            let run = HostRun(scenario, profile: profile)
            return (run, run.run())
        }
    }

    // MARK: What the host tells

    @Test func whatEachHostTellsOfItsField() throws {
        let text = String(repeating: "a", count: 150) + "|" + String(repeating: "b", count: 150)
        for profile in HostProfile.allCases {
            let (run, _) = try run("TEXT \"\(text)\"", on: profile)
            let field = run.field
            switch profile {
            case .nstextview:
                #expect(field.length() == 300 && field.selectedRange() == 150..<150)
                #expect(field.substring(0..<3) == "aaa" && field.substring(297..<300) == "bbb" && field.substring(299..<301) == nil)
            case .chromium, .electron:
                #expect(field.length() == 0 && field.selectedRange() == 150..<150)
                #expect(field.substring(50..<150)?.count == 100 && field.substring(49..<150) == nil, "only 100 around the caret")
                #expect(field.substring(150..<250)?.count == 100 && field.substring(150..<251) == nil)
            case .webkit:
                #expect(field.length() == 0 && field.selectedRange() == 150..<150)
                #expect(field.substring(0..<3) == "aaa" && field.substring(297..<300) == "bbb" && field.substring(299..<301) == nil)
            case .qt:
                #expect(field.length() == 0 && field.selectedRange() == 150..<150)
                #expect(field.substring(0..<150)?.count == 150 && field.substring(150..<300)?.count == 150)
                #expect(field.substring(299..<301) == "b" && field.substring(300..<302) == nil, "cut at the end, nil past it")
            case .tellsnothing, .terminal:
                #expect(field.length() == 0 && field.selectedRange() == nil && field.markedRange() == nil)
                #expect(field.substring(0..<1) == nil)
            }
            let calls = field.takeCalls()
            #expect(calls[.length] == 1 && calls[.selectedRange] == 1 && calls[.total] >= 3, "every call counted: \(calls)")
            #expect(field.takeCalls()[.total] == 0, "counted again from nothing")
        }
    }

    /// Chromium tells the ranges from before a key until the next turn; NSTextView tells them as they are.
    @Test func chromiumsRangesAreStaleDuringAKey() throws {
        for profile in [HostProfile.chromium, .nstextview] {
            let (run, _) = try run("TEXT \"ab|\"", on: profile)
            run.field.beginTurn()
            run.host.document = "abcd"
            run.host.caretOffset = 4
            #expect(run.field.selectedRange() == (profile == .chromium ? 2..<2 : 4..<4))
            run.field.endTurn()
            #expect(run.field.selectedRange() == 4..<4)
        }
    }

    /// The shell reads the text around the caret through what the host tells: all of it from NSTextView, what is within
    /// reach of the caret from Chromium (no length told), nothing from a field that tells nothing.
    @Test func theShellReadsTheTextAroundTheCaret() throws {
        for profile in HostProfile.allCases {
            let (run, _) = try run("TEXT \"Hi |Bob\"", on: profile)
            let read = run.reader.text(before: 1500, after: 200)
            #expect(read == (profile.tellsNothing ? nil : FieldText(before: "Hi ", after: "Bob")), "\(profile)")
        }
    }

    // MARK: What the host does

    /// Chromium hands every modifier change over twice: the shell drops the copy, so a tap of Shift is one switch. A copy
    /// that reached the session would be reported.
    @Test func copiesAreDroppedAndOneThatIsntIsReported() throws {
        for profile in [HostProfile.chromium, .electron] {
            let (_, failures) = try run("KEY shift\nEXPECT switches 1\nTYPE ab\nEXPECT doc \"ab\"", on: profile)
            #expect(failures.isEmpty, "\(failures)")
        }
        let (run, _) = try run("KEY shift", on: .chromium)
        // A copy with a time of its own: the guards can't tell it, the runner does.
        let change = ModifierChange(key: .modifier(.shift, .left), modifiers: HostKeys.left(.shift), timestamp: run.now + 1)
        run.advance(to: run.now + 1)
        run.deliver(.modifiers(change, code: HostKeys.code(of: .shift)), copy: true)
        #expect(run.failures.contains { $0.message.contains("reached the session") })
    }

    /// A click in a field with marked text (the app's own: since contract v1.3 the input method marks none): Chromium
    /// commits it as it shows it, itself; one inside it on NSTextView is the input method's, and nothing moves.
    @Test func aClickCommitsTheMarkedText() throws {
        #expect(try run("TEXT \"Hi {nihao}\"\nCLICK inside 0", on: .chromium).run.host.document == "Hi nihao")
        let inside = try run("TEXT \"Hi {nihao}\"\nCLICK inside 4", on: .nstextview).run
        #expect(inside.host.marked == "nihao" && inside.host.document == "Hi ")
    }

    /// Losing the focus, Chromium commits the marked text as it shows it (the app's own here).
    @Test func chromiumCommitsTheMarkedTextAsTheFieldLosesTheFocus() throws {
        let (chromium, _) = try run("TEXT \"Hi {nihao}\"\nFOCUS away", on: .chromium)
        #expect(chromium.host.document == "Hi nihao" && chromium.host.marked.isEmpty)
    }

    /// Qt reads only what `ImTextBeforeCursor` / `ImTextAfterCursor` give, 1024 characters each way, and answers the part
    /// of a range within that (nil where none is).
    @Test func qtReadsWithinItsReach() throws {
        let text = String(repeating: "a", count: 1100) + "|"
        let (run, _) = try run("TEXT \"\(text)\"", on: .qt)
        #expect(run.field.substring(76..<1100)?.count == 1024 && run.field.substring(75..<1100)?.count == 1024)
        #expect(run.field.substring(0..<76) == nil)
        // The shell still reads what is before the caret, the part within reach.
        #expect(run.reader.text(before: 1500, after: 200)?.before.count == 1024)
    }

    /// A terminal is told as one (its real bundle id, `FieldInfo.terminal`), so the core's terminal rules apply, and
    /// its field tells nothing.
    @Test func aTerminalIsToldAsOne() throws {
        let (run, failures) = try run("LANG english\nTEXT \"ls |\"\nTYPE la\nEXPECT doc \"ls la\"", on: .terminal)
        #expect(failures.isEmpty, "\(failures)")
        #expect(run.host.session.field.terminal && run.host.session.field.app == "com.mitchellh.ghostty")
        #expect(!run.host.composer.pastesIntoDraft && !run.host.composer.appTakesKeysAfterInsert)
        #expect(run.reader.everything().field == FieldInfo(app: "com.mitchellh.ghostty", terminal: true))
    }

    /// A terminal sends a key the session took to the shell unless text went in during it, marked text is after it, or
    /// the Mac's shell kept it (the key composed, or the rows took it); elsewhere a taken key is never the app's.
    @Test func aTerminalSendsATakenKeyTheShellDidntKeep() throws {
        let (terminal, _) = try run("LANG chinese\nTEXT \"|\"", on: .terminal)
        let none = terminal.host.outputs[terminal.host.outputs.endIndex...]
        #expect(terminal.terminalSends(composing: false, outputs: none))
        #expect(!terminal.terminalSends(composing: true, outputs: none), "a key that composes is kept")
        #expect(!terminal.terminalSends(composing: false, outputs: [.rowsTookKey]), "the rows took it")
        #expect(!terminal.terminalSends(composing: false, outputs: [.commit("你")]), "text went in during it")
        #expect(terminal.terminalSends(composing: false, outputs: [.commitAfterKey("你")]), "after the key isn't during it")
        let (nstextview, _) = try run("TEXT \"|\"", on: .nstextview)
        #expect(!nstextview.terminalSends(composing: false, outputs: none))
    }

    /// WebKit confirms the marked text itself as it loses first responder (`confirmCompositionAsync`); Qt commits it
    /// itself on a click (`commitPreedit`); a click in WebKit goes to the input context first, as NSTextView's.
    @Test func webKitAndQtCommitTheMarkedTextThemselves() throws {
        let (webkit, _) = try run("TEXT \"Hi {nihao}\"\nFOCUS away", on: .webkit)
        #expect(webkit.host.document == "Hi nihao" && webkit.host.marked.isEmpty)
        #expect(try run("TEXT \"Hi {nihao}\"\nCLICK inside 0", on: .qt).run.host.document == "Hi nihao")
        let inside = try run("TEXT \"Hi {nihao}\"\nCLICK inside 4", on: .webkit).run
        #expect(inside.host.marked == "nihao" && inside.host.document == "Hi ")
    }

    // MARK: Checks

    @Test func aFailedCheckIsReportedAtItsLine() throws {
        let (_, failures) = try run("""
            LANG chinese
            TYPE nihao
            EXPECT panel shown
            KEY space
            EXPECT doc "你好"
            EXPECT doc "wrong"
            EXPECT panel shown
            EXPECT lang english
            EXPECT switches 2
            """, on: .nstextview)
        #expect(failures.map(\.line) == [6, 7, 8, 9], "\(failures)")
    }

    @Test func callsAreCountedPerKey() throws {
        let (run, failures) = try run("LANG chinese\nTYPE ni\nEXPECT calls markedRange==1", on: .nstextview)
        // Nothing is marked in the field any more: no key asks for the marked range at all.
        #expect(failures.count == 2 && failures.allSatisfy { $0.message.contains("made 0 markedRange calls") }, "\(failures)")
        #expect(run.keyCalls.isEmpty, "the budget checked and the count started again")
    }

    @Test func theContextIsTheFieldsTextElseWhatWasTyped() throws {
        let typed = "LANG english\nTEXT \"Hi |\"\nTYPE there"
        #expect(try run(typed + "\nEXPECT context before \"Hi there\"", on: .nstextview).failures.isEmpty)
        // A field that tells nothing: what was typed in it since the focus stands in; nothing at all, unreadable.
        #expect(try run(typed + "\nEXPECT context before \"there\"", on: .tellsnothing).failures.isEmpty)
        #expect(try run("TEXT \"Hi |\"\nEXPECT context unreadable", on: .tellsnothing).failures.isEmpty)
        // An empty text expected: nothing to read meets it too.
        #expect(try run("TEXT \"Hi |\"\nEXPECT context before \"\"", on: .tellsnothing).failures.isEmpty)
        #expect(try run("TEXT \"|\"\nEXPECT context before \"\"", on: .nstextview).failures.isEmpty)
    }

    @Test func theAppsKeys() throws {
        let (run, failures) = try run("""
            LANG english
            TEXT "ab|c"
            KEY backspace
            EXPECT doc "a|c"
            KEY right enter
            EXPECT doc "ac\\n|"
            KEY cmd+z
            EXPECT doc "ac|"
            TYPE x
            SWITCH abc
            TYPE y
            SWITCH back
            EXPECT doc "acxy|"
            EXPECT nolost
            """, on: .nstextview)
        #expect(failures.isEmpty, "\(failures)")
        #expect(run.focused && !run.inABC)
    }

    // MARK: v1.1

    /// `KEY shift+a`: Shift down and up told as modifier changes around the key (their copies dropped where the host sends
    /// them twice), the capital typed, no switch.
    @Test func aShiftChordHasRealModifierEvents() throws {
        for profile in HostProfile.allCases {
            let (run, failures) = try run("LANG english\nTEXT \"|\"\nKEY shift+a\nEXPECT doc \"A\"\nEXPECT switches 0", on: profile)
            #expect(failures.isEmpty, "\(profile): \(failures)")
            let changes = run.modifierChanges
            #expect(changes.map { $0.modifiers.contains(.shift) } == [true, false], "\(profile): \(changes)")
        }
        #expect(HostKeys.event(.character("1"), modifiers: [.shift]).characters == "!")
    }

    /// `SET switchKey capsLock`: Caps Lock switches, a tap of Shift doesn't.
    @Test func theSwitchKeyIsSet() throws {
        let source = "SET switchKey capsLock\nLANG chinese\nKEY capslock\nEXPECT lang english\nKEY shift\nEXPECT switches 1"
        for profile in HostProfile.allCases {
            #expect(try run(source, on: profile).failures.isEmpty, "\(profile)")
        }
    }

    /// `APP clears` empties the field and drops its marked text; the input method may keep its composition (contract
    /// v1.3: it is only in the panel).
    @Test func anAppThatClearsTheField() throws {
        let (cleared, failures) = try run("LANG english\nTEXT \"old|\"\nAPP clears\nEXPECT doc \"\"\nEXPECT marked none", on: .chromium)
        #expect(failures.isEmpty && cleared.host.marked.isEmpty, "\(failures)")
        let (_, kept) = try run("LANG chinese\nTEXT \"old|\"\nTYPE ni\nAPP clears\nEXPECT doc \"\"", on: .nstextview)
        #expect(kept.isEmpty, "\(kept)")
    }

    /// `EXPECT preedit` reads the panel's input line: none where the panel is hidden; a wrong one is reported.
    @Test func thePreeditIsThePanelsInputLine() throws {
        #expect(try run("TEXT \"Hi |\"\nEXPECT preedit none", on: .nstextview).failures.isEmpty)
        let (_, wrong) = try run("TEXT \"Hi |\"\nEXPECT preedit \"ni hao\"", on: .nstextview)
        #expect(wrong.map(\.line) == [2] && wrong.first?.message.contains("input line") == true, "\(wrong)")
    }

    /// `EXPECT context after` reads past the caret; `EXPECT fallback none` holds once a click forgot what was typed.
    @Test func contextAfterAndTheFallback() throws {
        #expect(try run("TEXT \"Hi |Bob\"\nEXPECT context after \"Bob\"", on: .chromium).failures.isEmpty)
        #expect(try run("TEXT \"Hi |\"\nEXPECT context after \"\"", on: .tellsnothing).failures.isEmpty)
        let typed = "LANG english\nTEXT \"|\"\nTYPE there"
        #expect(try run(typed + "\nEXPECT fallback none", on: .tellsnothing).failures.count == 1)
        #expect(try run(typed + "\nCLICK inside 0\nEXPECT fallback none", on: .tellsnothing).failures.isEmpty)
    }
}
