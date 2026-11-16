import Foundation
import Testing
import AllInOneIMECore
import AllInOneIMETestSupport

/// The host scenario format as the runner reads it (`HostCaseParser`, `FieldMarkup`): the contract's steps, its markup,
/// and the lines it refuses, with their line numbers.
struct HostCaseParserTests {
    @Test func theContractsExampleReads() throws {
        let scenario = try HostCaseParser.parse("""
            NAME   an emptied chat field doesn't reuse what was typed before it
            PROFILES all                 # or a list: nstextview chromium electron tellsnothing
            LANG   chinese               # chinese | english: the field's starting language
            TEXT   "Hi Bob|"             # field text; | = caret, [..] = selection, {..} = marked
            TYPE   nihao                 # a string of plain keys
            KEY    space
            KEY    cmd+z opt+1 capslock shift
            CLICK  inside 2
            CLICK  outside
            FOCUS  away
            FOCUS  back
            SWITCH abc
            SWITCH back
            APP    clears                # the app empties the field (a chat app's send)
            WAIT   300ms
            EXPECT doc "Hi Bob你好"
            EXPECT marked "你好"
            EXPECT marked none
            EXPECT panel shown
            EXPECT lang english
            EXPECT context before "Hi "
            EXPECT context unreadable
            EXPECT switches 1
            EXPECT calls length<=1
            EXPECT nolost
            """, fallbackName: "file")
        #expect(scenario.name == "an emptied chat field doesn't reuse what was typed before it")
        #expect(scenario.profiles == HostProfile.allCases && scenario.language == .chinese)
        let actions = scenario.steps.map(\.action)
        #expect(actions.first == .text(FieldMarkup(text: "Hi Bob", caret: 6)))
        #expect(actions[1] == .type("nihao"))
        #expect(actions[3] == .keys([.key(.character("z"), modifiers: [.command]), .key(.character("1"), modifiers: [.option]),
                                     .capsLock, .tap(.shift)]))
        #expect(actions[4] == .click(2) && actions[5] == .click(nil))
        #expect(actions[6] == .focus(.away) && actions[8] == .switchSource(toABC: true) && actions[10] == .appClears)
        #expect(actions[11] == .wait(0.3))
        #expect(actions[12] == .expect(.doc(FieldMarkup(text: "Hi Bob你好"))))
        #expect(actions[13] == .expect(.marked("你好")) && actions[14] == .expect(.marked(nil)))
        #expect(actions[17] == .expect(.contextBefore("Hi ")) && actions[18] == .expect(.contextBefore(nil)))
        #expect(actions[20] == .expect(.calls(.length, HostCallBudget(comparison: .atMost, limit: 1))))
        #expect(actions.last == .expect(.nolost))
        #expect(scenario.steps.map(\.line).prefix(2) == [4, 5])
    }

    @Test func markup() throws {
        #expect(try FieldMarkup(parsing: "Hi [Bob]") == FieldMarkup(text: "Hi Bob", selection: 3..<6))
        #expect(try FieldMarkup(parsing: "Hi {nihao}") == FieldMarkup(text: "Hi ", marked: ("nihao", 3)))
        #expect(try FieldMarkup(parsing: "你|好") == FieldMarkup(text: "你好", caret: 1))
        // UTF-16: an emoji is two.
        #expect(try FieldMarkup(parsing: "😀|") == FieldMarkup(text: "😀", caret: 2))
        #expect(try FieldMarkup(parsing: #"a\|b\[c\]\{d\}\\\"e\nf|"#) == FieldMarkup(text: "a|b[c]{d}\\\"e\nf", caret: 14))
        for wrong in ["a|b|", "[a", "a]", "{a", "[a]{b}", "[a|]", "|{a}", "[{a}]", #"a\"#] {
            #expect(throws: HostCaseError.self, "\(wrong)") { try FieldMarkup(parsing: wrong) }
        }
    }

    /// `EXPECT preedit` (contract v1.3): the panel's input line, a `|` in it for its caret (in characters), or none.
    @Test func preedit() throws {
        let scenario = try HostCaseParser.parse("""
            EXPECT preedit "ni hao"
            EXPECT preedit "ni| hao"
            EXPECT preedit "improve › 好|"
            EXPECT preedit none
            """, fallbackName: "file")
        #expect(scenario.steps.map(\.action) == [.expect(.preedit("ni hao", caret: nil)), .expect(.preedit("ni hao", caret: 2)),
                                                 .expect(.preedit("improve › 好", caret: 11)), .expect(.preedit(nil, caret: nil))])
        for wrong in ["EXPECT preedit nihao", "EXPECT preedit \"[ni]\"", "EXPECT preedit \"{ni}\""] {
            #expect(throws: HostCaseError.self, "\(wrong)") { try HostCaseParser.parse(wrong, fallbackName: "file") }
        }
        // A syllable split isn't compared: librime shows "ni hao", the fake engine "nihao".
        #expect(HostRun.unsplit("ni hao") == "nihao" && HostRun.unsplit("improve › ok") == "improve › ok")
        #expect(HostRun.unsplit("question › hi there") == "question › hithere" && HostRun.unsplit(" a ") == " a ")
    }

    @Test func keys() throws {
        #expect(try HostCaseParser.keySpec("shift") == .tap(.shift))
        #expect(try HostCaseParser.keySpec("opt") == .tap(.option))
        #expect(try HostCaseParser.keySpec("CapsLock") == .capsLock)
        #expect(try HostCaseParser.keySpec("enter") == .key(.enter, modifiers: []))
        #expect(try HostCaseParser.keySpec("return") == .key(.enter, modifiers: []))
        #expect(try HostCaseParser.keySpec("ctrl+shift+A") == .key(.character("A"), modifiers: [.control, .shift]))
        #expect(try HostCaseParser.keySpec("cmd++") == .key(.character("+"), modifiers: [.command]))
        #expect(try HostCaseParser.keySpec("f5") == .key(.function(5), modifiers: []))
        for wrong in ["hyper+a", "cmd+banana", "f13", ""] {
            #expect(throws: HostCaseError.self, "\(wrong)") { try HostCaseParser.keySpec(wrong) }
        }
    }

    @Test func aStepForSomeProfilesNeedsTheOwnersOK() throws {
        let allowed = try HostCaseParser.parse("""
            TYPE nihao
            EXPECT marked "nihao" @profile chromium electron   # owner's OK, 2026-11-15: Chromium shows it as typed
            # owner's OK, 2026-11-15: the comment may be on the line before
            EXPECT panel shown @profile nstextview
            """, fallbackName: "file")
        #expect(allowed.steps[1].only == [.chromium, .electron] && allowed.steps[1].action == .expect(.marked("nihao")))
        #expect(allowed.steps[2].only == [.nstextview])
        #expect(!allowed.steps[1].applies(to: .nstextview) && allowed.steps[0].applies(to: .tellsnothing))
        let error = #expect(throws: HostCaseError.self) {
            try HostCaseParser.parse("TYPE nihao\nEXPECT marked \"nihao\" @profile chromium", fallbackName: "file")
        }
        #expect(error?.line == 2)
        // In quotes, it's the text's.
        let quoted = try HostCaseParser.parse(#"TYPE "a @profile b""#, fallbackName: "file")
        #expect(quoted.steps[0].action == .type("a @profile b") && quoted.steps[0].only == nil)
    }

    @Test func wrongLinesSayWhereTheyAre() {
        let cases: [(String, Int)] = [
            ("NAME x\nPROFILES safari", 2),
            ("TEXT Hi", 1),
            ("TYPE a\nLANG chinese", 2),
            ("EXPECT doc \"a{b}\"", 1),
            ("EXPECT calls widgets<=1", 1),
            ("EXPECT calls length", 1),
            ("EXPECT switches many", 1),
            ("\n\nCLICK somewhere", 3),
            ("WAIT soon", 1),
            ("JUMP", 1),
            ("TEXT \"a\" b\"", 1),
            ("TEXT \"open", 1),
        ]
        for (source, line) in cases {
            let error = #expect(throws: HostCaseError.self, "\(source)") { try HostCaseParser.parse(source, fallbackName: "file") }
            #expect(error?.line == line, "\(source): \(error.map(String.init(describing:)) ?? "")")
        }
    }

    @Test func defaultsAndForms() throws {
        let scenario = try HostCaseParser.parse("""
            TEXT "x"
            LANG english
            PROFILES chromium, tellsnothing
            WAIT 1.5s
            WAIT 20
            EXPECT calls substring == 2
            EXPECT calls total>3
            EXPECT calls all=0
            """, fallbackName: "the file's name")
        #expect(scenario.name == "the file's name" && scenario.language == .english)
        #expect(scenario.profiles == [.chromium, .tellsnothing])
        #expect(scenario.steps.map(\.action) == [
            .text(FieldMarkup(text: "x")), .wait(1.5), .wait(0.02),
            .expect(.calls(.substring, HostCallBudget(comparison: .exactly, limit: 2))),
            .expect(.calls(.total, HostCallBudget(comparison: .more, limit: 3))),
            .expect(.calls(.total, HostCallBudget(comparison: .exactly, limit: 0))),
        ])
    }

    /// v1.1: `SET`, `EXPECT context after`, `EXPECT fallback none`; `shift+a` is a chord.
    @Test func version1Point1() throws {
        let scenario = try HostCaseParser.parse("""
            TEXT "|"
            SET switchKey capsLock
            SET autocomplete false
            KEY shift+a
            EXPECT context after "x"
            EXPECT fallback none
            """, fallbackName: "file")
        #expect(scenario.settings.map(\.key) == ["switchKey", "autocomplete"] && scenario.settings.map(\.value) == ["capsLock", "false"])
        #expect(scenario.steps.map(\.action) == [
            .text(FieldMarkup(text: "", caret: 0)), .keys([.key(.character("a"), modifiers: [.shift])]),
            .expect(.contextAfter("x")), .expect(.fallbackNone),
        ])
        let config = try HostScenarioSettings.config(startingIn: .chinese, set: scenario.settings)
        #expect(config.switchKey == .capsLock && !config.autocomplete && config.provider == .apple)
        #expect(try HostScenarioSettings.config(startingIn: .english, set: [("switchKey", "shift")]).switchKey == .shift)
        #expect(try HostScenarioSettings.config(startingIn: .english, set: [("inputLanguages", #"["en"]"#)]).inputLanguages == [.english])
        let wrong: [(String, Int)] = [
            ("SET switchKey none", 1),  // the config has no such choice
            ("SET switchKey", 1),
            ("SET noSuchKey 1", 1),
            ("SET autocomplete maybe", 1),
            ("TYPE a\nSET switchKey capsLock", 2),
            ("EXPECT context around \"x\"", 1),
            ("EXPECT fallback \"x\"", 1),
        ]
        for (source, line) in wrong {
            let error = #expect(throws: HostCaseError.self, "\(source)") { try HostCaseParser.parse(source, fallbackName: "file") }
            #expect(error?.line == line, "\(source): \(error.map(String.init(describing:)) ?? "")")
        }
    }
}
