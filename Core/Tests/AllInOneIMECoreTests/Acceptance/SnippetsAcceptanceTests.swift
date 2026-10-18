import Foundation
import Testing
@testable import AllInOneIMECore

// Independent acceptance tests for "Snippets and placeholders" (0.6.5/snippets), written from the spec only, one test
// per core scenario (s1 … s19). The composer is driven key by key, as the input controller hands it keys; what the
// controller does with the effects (inserting, typing out, moving the caret, reading the clipboard) is checked as the
// effects the spec names.
//
// ASSUMPTIONS where the spec leaves an API detail open (the narrowest reading; the implementation should match them):
//  1. `CustomCommand.CommandType.snippet` is written `"snippet"` in JSON. `CustomCommand.text: String?` is a settable
//     `var` (the tests make `CustomCommand(name:type:)` and then set `text` and `summary`), encoded under `"text"` and
//     left out when nil, like the other optional keys.
//  2. `CustomCommand.problem(among:plugins:)` returns `.emptyText` for a blank text and `.twoCursors` for a text with two
//     `{cursor}`; such a definition isn't `isValid`, so `Command.catalog` leaves it out.
//  3. `Command.Kind.snippet`. `Command.bundle: String?` is the bundle's name for a bundle's snippet ("team"), nil for a
//     snippet from the config.
//  4. `Command.catalog(_:plugins:scripts:snippets:)`, `snippets: [BundleSnippet]` defaulting to `[]`.
//  5. `ExtensionIndex.snippets: [BundleSnippet]`, each with `name`, `alias`, `text` and `id == "<bundle>/<name>"`.
//     `ExtensionIndex.enabledSnippets(_ disabled: [String]) -> [BundleSnippet]` leaves out the ones turned off in
//     `Config.disabledExtensions`, as `enabled(_:)` does for commands.
//  6. `SnippetTemplate.parse(_ text: String) -> SnippetTemplate` (it neither throws nor returns an optional);
//     `render(_ values: SnippetValues)` returns something with `.text: String` and `.caretBack: Int?`;
//     `fieldLabels: [String]`, in the order the fields first appear, each label once.
//  7. `SnippetValues(input:fields:clipboard:selection:now:timeZone:locale:)`, labelled and ordered as the spec lists them;
//     `fields: [String]` (positional, numbered as the fields first appear); `clipboard` and `selection` take a string.
//  8. `Composer.timeZone: TimeZone` is a settable `var` (default `.current`). `{date}` and `{time}` come from
//     `Composer.now`. A `{date:FMT}` in the interface language's locale is checked at the renderer with
//     `Locale(identifier: "zh-Hans")`; how the composer picks that locale isn't tested.
//  9. `Composer.Effect.moveCaret(back: Int)`.
// 10. The clipboard answer is the existing `Composer.pasted(_ clipboard: String?, id: Int)`: the spec's `.text("X")`
//     is `"X"`, and its `.none` is `nil`.
// 11. The palette row's text for a snippet is `Command.snippetRowText: String?` (nil for any other command): its
//     `summary`, or else the start of its text, at most 40 characters (an ellipsis after them is allowed), with no line
//     break in it.
// 12. S2/S3/S4: the effects contain the ones the spec names (`finish` decides the order of `.hidePanel`), and
//     `.moveCaret` comes after the text is inserted. S7: what is committed, joined, is the signature then " thanks"
//     (one commit or two).
// 13. S12/S13: a snippet inside a text is typed with something after it ("。", " 吧", "「…」"): ⏎ while "@name" is
//     still being typed inside a text completes the name, as it does today, so the end-of-text case isn't driven here.
// 14. S9: the draft that stays after `nothingToPaste` is "@quote", with or without its trailing space. Pressing the
//     action key on it again asks for the clipboard again, with a new id.
// 15. S18: the notice for a rendered text over 20,000 characters isn't named by the spec: any notice.
// 16. S19: the config is read and written with `JSONDecoder` / `JSONEncoder`; the unknown entry is written back
//     unchanged somewhere in `customCommands`, and isn't one of `Config.customCommands`.

// MARK: - Helpers

private let snAt = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
private let snTab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

/// A snippet as the config holds it.
private func snippet(_ name: String, _ text: String, summary: String? = nil) -> CustomCommand {
    var definition = CustomCommand(name: name, type: .snippet)
    definition.text = text
    definition.summary = summary
    return definition
}

/// The signature of the spec's examples.
private let sig = snippet("sig", "Best,\nWei\n{cursor}", summary: "Email signature")

/// 2026-10-17 14:05 UTC (a Saturday).
private let snNow: Date = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 14, minute: 5))!
}()

private let utc = TimeZone(identifier: "UTC")!

/// A text field: English typed, the built-ins and `snippets` offered, the clock at `snNow` in UTC.
private func field(_ snippets: [CustomCommand], actionKey: ActionKey = .enter, selection: Composer.Selection? = nil,
                   others: [CustomCommand] = []) -> Composer {
    let c = Composer(engine: FakeEngine(), voiceEnabled: false, actionKey: actionKey)
    c.commands = Command.catalog(others + snippets)
    c.inputLanguages = [.chinese, .english]
    c.setInputMode(.english)
    c.now = { snNow }
    c.timeZone = utc
    if let selection { c.readSelection = { selection } }
    return c
}

/// Each character as a key ("@" as Shift-2, Space as the Space key); every effect, in order.
@discardableResult
private func typeKeys(_ text: String, _ c: Composer) -> [Composer.Effect] {
    text.flatMap { ch -> [Composer.Effect] in
        let event = ch == "@" ? snAt : ch == " " ? spaceKey : KeyEvent(keyCode: 0, characters: String(ch),
                                                                       modifiers: ch.isUppercase ? .shift : [])
        return c.handleKeyDown(event).effects
    }
}

/// "@", the letters, Tab: "@name ".
private func pick(_ name: String, _ c: Composer) {
    typeKeys("@" + name, c)
    _ = c.handleKeyDown(snTab)
}

private func notices(_ effects: [Composer.Effect]) -> [String] {
    effects.compactMap { if case let .notice(s) = $0 { return s } else { return nil } }
}

private func typedOut(_ effects: [Composer.Effect]) -> [String] {
    effects.compactMap { if case let .typeOut(s) = $0 { return s } else { return nil } }
}

private func caretMoves(_ effects: [Composer.Effect]) -> [Int] {
    effects.compactMap { if case let .moveCaret(back) = $0 { return back } else { return nil } }
}

private func clipboardRequests(_ effects: [Composer.Effect]) -> [Int] {
    effects.compactMap { if case let .readClipboard(id) = $0 { return id } else { return nil } }
}

private func conversions(_ effects: [Composer.Effect]) -> [String] {
    effects.compactMap { if case let .startConversion(input, _) = $0 { return input } else { return nil } }
}

private func commandStarts(_ effects: [Composer.Effect]) -> [(Command, String)] {
    effects.compactMap { if case let .startCommand(command, input, _) = $0 { return (command, input) } else { return nil } }
}

/// Whether anything was sent or started: a model request, a program, a plan.
private func startsAnything(_ effects: [Composer.Effect]) -> Bool {
    effects.contains {
        switch $0 {
        case .startConversion, .startCommand, .startRun, .startPlan, .startScript, .startRefine: return true
        default: return false
        }
    }
}

/// Where the first effect matching `match` is.
private func position(_ effects: [Composer.Effect], _ match: (Composer.Effect) -> Bool) -> Int? {
    effects.firstIndex(where: match)
}

/// Values for the renderer: nothing typed, nothing on the clipboard or selected, the clock at `snNow` in UTC.
private func values(input: String = "", fields: [String] = [], locale: Locale = Locale(identifier: "en_US_POSIX"))
    -> SnippetValues {
    SnippetValues(input: input, fields: fields, clipboard: "", selection: "", now: snNow, timeZone: utc, locale: locale)
}

/// Presses `actionKey` as the user does; what it does.
private func act(_ c: Composer) -> [Composer.Effect] {
    switch c.actionKey {
    case .enter: return c.handleKeyDown(enterKey).effects
    case .optionSpace: return c.handleKeyDown(optionSpace).effects
    case .space: return c.handleKeyDown(spaceKey).effects
    case .optionTap:
        _ = c.handleFlagsChanged(keyCode: VirtualKey.leftOption, modifiers: [.option, .leftOption], timestamp: 1)
        return c.handleFlagsChanged(keyCode: VirtualKey.leftOption, modifiers: [], timestamp: 1.1)
    case let .shortcut(key):
        return c.handleKeyDown(KeyEvent(keyCode: key.keyCode, characters: "", modifiers: key.modifiers)).effects
    }
}

/// A folder of extensions holding the bundle "team", which ships only snippets; removed after the test. (Not
/// `ScriptFolder`, which Windows leaves out: no script runs here.)
private final class TeamFolder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("snippets-\(UUID().uuidString)", isDirectory: true)

    init() {
        let bundle = url.appendingPathComponent("team", isDirectory: true)
        try? FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try? Data(#"""
            {"schemaVersion": 1, "name": "team", "title": "Team",
             "snippets": [
               {"name": "addr", "text": "1 Main Street\nSpringfield", "summary": "Office address", "alias": "teamaddr"},
               {"name": "wifi", "text": "guest / hunter2"}
             ]}
            """#.utf8).write(to: bundle.appendingPathComponent(ExtensionBundle.manifestName))
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func load() -> ExtensionIndex { ExtensionStore.load([ExtensionStore.Folder(path: url.path, found: false)]) }
}

// MARK: - The scenarios

struct SnippetsAcceptanceTests {
    @Test func s1_aSnippetEntryRoundTripsAndBadOnesAreRefused() throws {
        // The entry as written in the config: decoded and encoded again, the same JSON.
        let json = #"{ "name": "sig", "type": "snippet", "summary": "Email signature", "text": "Best,\nWei\n{cursor}" }"#
        let decoded = try JSONDecoder().decode(CustomCommand.self, from: Data(json.utf8))
        #expect(decoded.type == .snippet && decoded.text == "Best,\nWei\n{cursor}" && decoded.summary == "Email signature")
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? NSDictionary
        let original = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary
        #expect(written == original, "\(String(describing: written))")
        // Inside the config file too.
        let file = #"{"customCommands": ["# + json + #"]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(file.utf8))
        #expect(config.customCommands == [decoded])
        let rewritten = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any]
        let entries = rewritten?["customCommands"] as? [NSDictionary]
        #expect(entries == [original!], "\(String(describing: entries))")
        #expect(decoded.problem(among: []) == nil)

        // An empty text, and two {cursor}: refused, and not offered.
        let empty = snippet("blank", "  \n ")
        let twice = snippet("twice", "a{cursor}b{cursor}")
        #expect(empty.problem(among: []) == .emptyText)
        #expect(snippet("none", "").problem(among: []) == .emptyText)
        #expect(twice.problem(among: []) == .twoCursors)
        #expect(!empty.isValid && !twice.isValid)
        let catalog = Command.catalog([empty, twice, decoded])
        #expect(!catalog.contains { $0.name == "blank" || $0.name == "twice" })
        let offered: Command? = catalog.first { $0.name == "sig" }
        #expect(offered?.kind == Command.Kind.snippet)
        #expect(offered != nil && offered?.bundle == nil)
    }

    @Test func s2_returnInThePaletteInsertsASnippetThatNeedsNothing() {
        let c = field([sig])
        typeKeys("@sig", c)
        #expect(c.paletteMatches.first?.name == "sig")
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.contains(.commit("Best,\nWei\n")), "\(effects)")
        #expect(effects.contains(.moveCaret(back: 0)), "\(effects)")
        #expect(effects.contains(.commandUsed("sig")) && effects.contains(.hidePanel), "\(effects)")
        #expect(commits(effects) == ["Best,\nWei\n"] && caretMoves(effects) == [0])
        let inserted = position(effects) { $0 == .commit("Best,\nWei\n") }
        let moved = position(effects) { $0 == .moveCaret(back: 0) }
        #expect(inserted != nil && moved != nil && inserted! < moved!, "\(effects)")
        #expect(!startsAnything(effects) && c.draft.isEmpty && !c.isComposing)
    }

    @Test(arguments: [ActionKey.enter, .optionTap, .optionSpace, .space,
                      .shortcut(KeyShortcut(keyCode: VirtualKey.returnKey, modifiers: .control, name: "⌃⏎"))])
    func s3_theActionKeyOnACompletedNameInserts(_ key: ActionKey) {
        let c = field([sig], actionKey: key)
        // Tab only completes the name.
        typeKeys("@sig", c)
        let tab = c.handleKeyDown(snTab).effects
        #expect(c.draft == "@sig " && commits(tab).isEmpty && caretMoves(tab).isEmpty, "\(key): \(tab)")
        let effects = act(c)
        #expect(commits(effects) == ["Best,\nWei\n"], "\(key): \(effects)")
        #expect(caretMoves(effects) == [0], "\(key): \(effects)")
        #expect(effects.contains(.commandUsed("sig")) && effects.contains(.hidePanel), "\(key): \(effects)")
        let inserted = position(effects) { $0 == .commit("Best,\nWei\n") }
        let moved = position(effects) { $0 == .moveCaret(back: 0) }
        #expect(inserted != nil && moved != nil && inserted! < moved!, "\(key): \(effects)")
        #expect(c.draft.isEmpty && !c.isComposing, "\(key)")
    }

    @Test func s4_theCaretGoesBackToTheCursor() {
        let thanks = snippet("thx", "Hi {cursor}, thanks")
        // The renderer: ", thanks" is 8 UTF-16 units after the cursor.
        let rendered = SnippetTemplate.parse("Hi {cursor}, thanks").render(values())
        #expect(rendered.text == "Hi , thanks" && rendered.caretBack == 8)
        #expect(SnippetTemplate.parse("no cursor").render(values()).caretBack == nil)
        // The composer.
        let c = field([thanks])
        typeKeys("@thx", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(commits(effects) == ["Hi , thanks"] && caretMoves(effects) == [8], "\(effects)")
        let inserted = position(effects) { $0 == .commit("Hi , thanks") }
        let moved = position(effects) { $0 == .moveCaret(back: 8) }
        #expect(inserted != nil && moved != nil && inserted! < moved!, "\(effects)")
        // No {cursor}: the caret isn't moved.
        let plain = field([snippet("plain", "no cursor here")])
        typeKeys("@plain", plain)
        let none = plain.handleKeyDown(enterKey).effects
        #expect(commits(none) == ["no cursor here"] && caretMoves(none).isEmpty, "\(none)")
    }

    @Test func s5_fieldsAreFilledFromWhatIsTypedSeparatedByCommas() {
        let meet = snippet("meet", "Dear {name?}, see you {day?}.")
        #expect(SnippetTemplate.parse("Dear {name?}, see you {day?}.").fieldLabels == ["name", "day"])
        // The same label twice is one field, with one value.
        let twice = SnippetTemplate.parse("{a?} and {b?}, {a?} again")
        #expect(twice.fieldLabels == ["a", "b"])
        #expect(twice.render(values(fields: ["x", "y"])).text == "x and y, x again")

        let c = field([meet])
        pick("meet", c)
        typeKeys("张三，周五", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(commits(effects) == ["Dear 张三, see you 周五."], "\(effects)")
        #expect(effects.contains(.commandUsed("meet")))

        // A field missing: the notice names it, nothing goes in, the draft stays.
        let short = field([meet])
        pick("meet", short)
        typeKeys("张三", short)
        let missing = short.handleKeyDown(enterKey).effects
        #expect(notices(missing) == ["还要写：day"], "\(missing)")
        #expect(commits(missing).isEmpty && caretMoves(missing).isEmpty && !startsAnything(missing), "\(missing)")
        #expect(short.draft == "@meet 张三" && short.isComposing)
    }

    @Test func s6_inputIsTheWholeTextTypedAfterTheName() {
        #expect(SnippetTemplate.parse("#{input}").render(values(input: "foo bar")).text == "#foo bar")
        let c = field([snippet("tag", "#{input}")])
        pick("tag", c)
        typeKeys("foo bar", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(commits(effects) == ["#foo bar"], "\(effects)")
        #expect(caretMoves(effects).isEmpty && !startsAnything(effects))
    }

    @Test func s7_textAfterASnippetWithoutPlaceholdersGoesInAfterIt() {
        let c = field([sig])
        pick("sig", c)
        typeKeys("thanks", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(commits(effects).joined() == "Best,\nWei\n thanks", "\(effects)")
        #expect(effects.contains(.commandUsed("sig")) && !startsAnything(effects))
        #expect(c.draft.isEmpty && !c.isComposing)
    }

    @Test func s8_dateAndTime() {
        // The composer: Composer.now in Composer.timeZone.
        let c = field([snippet("stamp", "{date} {time}")])
        typeKeys("@stamp", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(commits(effects) == ["2026-10-17 14:05"], "\(effects)")
        // Another time zone moves the clock: 14:05 UTC is 22:05 in Shanghai.
        let shanghai = field([snippet("stamp", "{date} {time}")])
        shanghai.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        typeKeys("@stamp", shanghai)
        #expect(commits(shanghai.handleKeyDown(enterKey).effects) == ["2026-10-17 22:05"])
        // The renderer, with a pattern in the Chinese interface's locale.
        #expect(SnippetTemplate.parse("{date} {time}").render(values()).text == "2026-10-17 14:05")
        let chinese = values(locale: Locale(identifier: "zh-Hans"))
        #expect(SnippetTemplate.parse("{date:M月d日 EEEE}").render(chinese).text == "10月17日 星期六")
    }

    @Test func s9_theClipboardIsAskedForByID() throws {
        let c = field([snippet("quote", "> {clipboard}")])
        typeKeys("@quote", c)
        let asked = c.handleKeyDown(enterKey).effects
        let first = try #require(clipboardRequests(asked).first, "\(asked)")
        #expect(commits(asked).isEmpty, "\(asked)")
        // No text on the clipboard: a notice, and the draft stays.
        let nothing = c.pasted(nil, id: first)
        #expect(notices(nothing) == [c.messages.nothingToPaste], "\(nothing)")
        #expect(commits(nothing).isEmpty && c.isComposing, "\(nothing)")
        #expect(c.draft.trimmingCharacters(in: .whitespaces) == "@quote", "\(c.draft)")
        // Asked again: the old id is stale and does nothing; the new one's text goes in.
        let again = act(c)
        let second = try #require(clipboardRequests(again).first, "\(again)")
        #expect(second != first)
        let stale = c.pasted("old", id: first)
        #expect(commits(stale).isEmpty && notices(stale).isEmpty && c.isComposing, "\(stale)")
        let pasted = c.pasted("X", id: second)
        #expect(commits(pasted) == ["> X"], "\(pasted)")
        #expect(!c.isComposing)
        // Once done, the same id again does nothing.
        #expect(commits(c.pasted("X", id: second)).isEmpty)

        // The first answer can be the text right away.
        let d = field([snippet("quote", "> {clipboard}")])
        typeKeys("@quote", d)
        let id = try #require(clipboardRequests(d.handleKeyDown(enterKey).effects).first)
        #expect(commits(d.pasted("X", id: id)) == ["> X"])
    }

    @Test func s10_theSelectionIsReplaced() {
        let selected = Composer.Selection(text: "abc", range: 4..<7)
        let bold = snippet("bold", "**{selection}**")
        let c = field([bold], selection: selected)
        typeKeys("@bold", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.contains(.replaceSelection("**abc**", selected)), "\(effects)")
        #expect(commits(effects).isEmpty, "\(effects)")
        // A template without {selection} replaces it too.
        let d = field([sig], selection: selected)
        typeKeys("@sig", d)
        let signed = d.handleKeyDown(enterKey).effects
        #expect(signed.contains(.replaceSelection("Best,\nWei\n", selected)), "\(signed)")
        #expect(commits(signed).isEmpty, "\(signed)")
        // No selection: {selection} is empty.
        let e = field([bold])
        typeKeys("@bold", e)
        #expect(commits(e.handleKeyDown(enterKey).effects) == ["****"])
    }

    @Test func s11_doubledBracesAreEscapes() {
        #expect(SnippetTemplate.parse("{{input}} {x}").render(values(input: "typed")).text == "{input} {x}")
        let c = field([snippet("braces", "{{input}} {x}")])
        typeKeys("@braces", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(commits(effects) == ["{input} {x}"], "\(effects)")
    }

    @Test func s12_aSnippetInsideATextIsExpandedBeforeTheRequest() {
        let zoom = snippet("zoom", "https://zoom.us/j/123")
        let addr = snippet("addr", "{name?} 收")
        #expect(SnippetTemplate.parse("https://zoom.us/j/123").canBeInner)
        #expect(!SnippetTemplate.parse("{name?} 收").canBeInner)
        #expect(!SnippetTemplate.parse("> {clipboard}").canBeInner && !SnippetTemplate.parse("**{selection}**").canBeInner)

        // Before punctuation.
        let c = field([zoom, addr])
        typeKeys("@improve 链接是 @zoom。", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(conversions(effects) == ["链接是 https://zoom.us/j/123。"], "\(effects)")
        #expect(c.refineRequest != nil)
        #expect(!effects.contains { if case .startPlan = $0 { return true } else { return false } }, "\(effects)")

        // Before a space: it takes no argument, the rest stays text.
        let d = field([zoom, addr])
        typeKeys("@improve 链接是 @zoom 吧", d)
        #expect(conversions(d.handleKeyDown(enterKey).effects) == ["链接是 https://zoom.us/j/123 吧"])
        #expect(d.refineRequest != nil)

        // A snippet with fields stays as literal text, and isn't offered inside a text.
        let e = field([zoom, addr])
        typeKeys("@improve 地址 @add", e)
        #expect(!e.paletteMatches.contains { $0.name == "addr" }, "\(e.paletteMatches.map(\.name))")
        typeKeys("r 张三。", e)
        #expect(conversions(e.handleKeyDown(enterKey).effects) == ["地址 @addr 张三。"])
    }

    @Test func s13_aSnippetWithInputInsideATextTakesAQuotedArgument() throws {
        let meet = snippet("meet", "会议：{input}")
        let c = field([meet])
        typeKeys("@question 总结 @meet「周五 3点」", c)
        let effects = c.handleKeyDown(enterKey).effects
        let started = try #require(commandStarts(effects).first, "\(effects)")
        #expect(started.0 == .question && started.1 == "总结 会议：周五 3点", "\(effects)")
        #expect(c.refineRequest != nil)
    }

    @Test func s14_typedOutThenTheCaretMoves() {
        let c = field([sig])
        c.typesResults = true
        typeKeys("@sig", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(typedOut(effects) == ["Best,\nWei\n"], "\(effects)")
        #expect(commits(effects).allSatisfy(\.isEmpty), "\(effects)")
        let finished = position(effects) { $0 == .hidePanel }
        let typed = position(effects) { $0 == .typeOut("Best,\nWei\n") }
        let moved = position(effects) { $0 == .moveCaret(back: 0) }
        #expect(finished != nil && typed != nil && moved != nil, "\(effects)")
        if let finished, let typed, let moved { #expect(finished < typed && typed < moved, "\(effects)") }
    }

    @Test func s15_thePaletteListsSnippetsWithTheirSummaryOrFirstLine() throws {
        let plain = snippet("sign", "Thanks,\nWei")
        let long = snippet("sigh", String(repeating: "abcdefghij", count: 6))
        let c = field([sig, plain, long])
        typeKeys("@si", c)
        let listed = c.paletteMatches.map(\.name)
        #expect(listed.contains("sig") && listed.contains("sign"), "\(listed)")
        let catalog = c.commands
        let withSummary = try #require(catalog.first { $0.name == "sig" })
        #expect(withSummary.snippetRowText == "Email signature")
        let sign = try #require(catalog.first { $0.name == "sign" })
        let firstLine = try #require(sign.snippetRowText)
        #expect(firstLine.hasPrefix("Thanks,") && !firstLine.contains("\n"), "\(firstLine)")
        let sigh = try #require(catalog.first { $0.name == "sigh" })
        let cut = try #require(sigh.snippetRowText)
        let text = String(repeating: "abcdefghij", count: 6)
        #expect(cut.hasPrefix(String(text.prefix(40))) && cut.count <= 41, "\(cut)")
        #expect(Command.question.snippetRowText == nil)
    }

    @Test func s16_aBundleCanShipOnlySnippets() throws {
        let folder = TeamFolder()
        let index = folder.load()
        #expect(index.skipped.isEmpty, "\(index.skipped)")
        #expect(index.bundles.map(\.name) == ["team"])
        #expect(index.snippets.map(\.name) == ["addr", "wifi"])
        let addr = try #require(index.snippets.first)
        #expect(addr.id == "team/addr" && addr.alias == "teamaddr" && addr.text == "1 Main Street\nSpringfield")

        // A custom command has the name: the bundle's snippet goes by its alias.
        let mine = CustomCommand(name: "addr", type: .prompt, prompt: "Write an address.")
        let catalog = Command.catalog([mine], snippets: index.enabledSnippets([]))
        #expect(catalog.first { $0.name == "addr" }?.kind == .generate)
        let aliased = try #require(catalog.first { $0.name == "teamaddr" })
        #expect(aliased.kind == .snippet && aliased.bundle == "team")
        #expect(catalog.first { $0.name == "wifi" }?.bundle == "team")

        // Turned off by "<bundle>/<name>".
        let enabled = index.enabledSnippets(["team/addr"])
        #expect(enabled.map(\.name) == ["wifi"])
        let fewer = Command.catalog([mine], snippets: enabled)
        #expect(!fewer.contains { $0.name == "teamaddr" } && fewer.contains { $0.name == "wifi" })

        // A bundle's snippet inserts like the user's own.
        let c = Composer(engine: FakeEngine(), voiceEnabled: false, actionKey: .enter)
        c.commands = catalog
        c.setInputMode(.english)
        typeKeys("@wifi", c)
        #expect(commits(c.handleKeyDown(enterKey).effects) == ["guest / hunter2"])
    }

    @Test func s17_snippetsNeedNoChildProcess() {
        let folder = TeamFolder()
        let index = folder.load()
        var fake = Platform.current
        fake.processes = NoProcessLauncher()
        Platform.$override.withValue(fake) {
            #expect(!Platform.current.processes.canLaunch)
            let catalog = Command.catalog([sig], snippets: index.enabledSnippets([]))
            #expect(catalog.contains { $0.name == "sig" && $0.kind == .snippet }, "\(catalog.map(\.name))")
            #expect(catalog.contains { $0.name == "wifi" && $0.kind == .snippet }, "\(catalog.map(\.name))")
            #expect(catalog.filter { $0.kind == .snippet }.allSatisfy { !$0.needsChildProcess && !$0.usesAI })
        }
    }

    @Test func s18_noAIAppsAndTheLengthLimit() {
        // AI off in this app: a snippet still goes in.
        let c = field([sig])
        let refusal = "AI is off in this app"
        c.aiRefusal = { refusal }
        typeKeys("@sig", c)
        let effects = c.handleKeyDown(enterKey).effects
        #expect(commits(effects) == ["Best,\nWei\n"], "\(effects)")
        #expect(!notices(effects).contains(refusal))

        // A template of 18,000 characters is fine; rendered, it is 30,000: a notice, nothing inserted.
        let template = String(repeating: "{date}", count: 3000)
        #expect(template.count <= Composer.maxNoteLength)
        let long = snippet("long", template)
        #expect(long.problem(among: []) == nil)
        let d = field([long])
        #expect(d.commands.contains { $0.name == "long" })
        typeKeys("@long", d)
        let refused = d.handleKeyDown(enterKey).effects
        #expect(commits(refused).isEmpty && typedOut(refused).isEmpty && caretMoves(refused).isEmpty, "\(refused.count) effects")
        #expect(!notices(refused).isEmpty)
    }

    @Test func s19_anUnknownCustomCommandTypeIsKept() throws {
        let unknown = #"{"name": "future", "type": "hologram", "beam": 42, "nested": {"a": [1, "two", null, true]}}"#
        let known = #"{"name": "sig", "type": "snippet", "text": "Best,\nWei"}"#
        let file = #"{"customCommands": ["# + known + ", " + unknown + #"]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(file.utf8))
        #expect(config.customCommands.map(\.name) == ["sig"])
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any]
        let entries = try #require(written?["customCommands"] as? [NSDictionary])
        let original = try #require(try JSONSerialization.jsonObject(with: Data(unknown.utf8)) as? NSDictionary)
        #expect(entries.contains(original), "\(entries)")
        #expect(entries.count == 2)
        // Read and written once more: still there, once.
        let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        let twice = try JSONSerialization.jsonObject(with: JSONEncoder().encode(again)) as? [String: Any]
        let entriesTwice = try #require(twice?["customCommands"] as? [NSDictionary])
        #expect(entriesTwice.filter { $0 == original }.count == 1 && entriesTwice.count == 2)
    }
}
