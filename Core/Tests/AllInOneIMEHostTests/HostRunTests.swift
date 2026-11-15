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
            case .tellsnothing:
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
            #expect(read == (profile == .tellsnothing ? nil : FieldText(before: "Hi ", after: "Bob")), "\(profile)")
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

    /// A click in a field with marked text: Chromium commits it as it shows it, itself; NSTextView has the input method
    /// commit it (its candidate).
    @Test func aClickCommitsTheMarkedText() throws {
        let source = "LANG chinese\nTEXT \"Hi |\"\nTYPE nihao\nCLICK inside 0"
        #expect(try run(source, on: .chromium).run.host.document == "Hi nihao")
        #expect(try run(source, on: .nstextview).run.host.document == "Hi 你好")
        // A click inside the marked text is the input method's: nothing moves.
        let inside = try run("LANG chinese\nTEXT \"Hi |\"\nTYPE nihao\nCLICK inside 4", on: .nstextview).run
        #expect(inside.host.marked == "nihao" && inside.host.document == "Hi ")
    }

    /// Losing the focus, Chromium commits the marked text as it shows it and drops what the input method puts in then:
    /// `nolost` says the candidate was lost.
    @Test func chromiumDropsWhatGoesInAsTheFieldLosesTheFocus() throws {
        let source = "LANG chinese\nTEXT \"Hi |\"\nTYPE nihao\nFOCUS away\nEXPECT nolost"
        let (chromium, lost) = try run(source, on: .chromium)
        #expect(chromium.host.document == "Hi nihao")
        #expect(lost.map(\.line) == [5] && lost.first?.message.contains("lost or doubled") == true, "\(lost)")
        let (textView, none) = try run(source, on: .nstextview)
        #expect(textView.host.document == "Hi 你好" && none.isEmpty, "\(none)")
    }

    // MARK: Checks

    @Test func aFailedCheckIsReportedAtItsLine() throws {
        let (_, failures) = try run("""
            LANG chinese
            TYPE nihao
            EXPECT marked "nihao"
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
        let (run, failures) = try run("LANG chinese\nTYPE ni\nEXPECT calls markedRange<=1", on: .nstextview)
        // The first letter: the marked text watched once it was set; the second: read before (whether the app took it)
        // as well.
        #expect(failures.count == 1 && failures.first?.message.contains("markedRange") == true, "\(failures)")
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

    /// `APP clears` drops the marked text with the rest; an input method still holding the draft then is reported.
    @Test func anAppThatClearsTheFieldLeavesNoDraft() throws {
        let (cleared, failures) = try run("LANG english\nTEXT \"old|\"\nAPP clears\nEXPECT doc \"\"\nEXPECT marked none", on: .chromium)
        #expect(failures.isEmpty && cleared.host.marked.isEmpty, "\(failures)")
        let (_, kept) = try run("LANG chinese\nTEXT \"old|\"\nTYPE ni\nAPP clears", on: .nstextview)
        #expect(kept.map(\.line) == [4] && kept.first?.message.contains("still holds the draft") == true, "\(kept)")
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
