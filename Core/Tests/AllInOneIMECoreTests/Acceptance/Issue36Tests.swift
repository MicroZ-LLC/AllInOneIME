import Foundation
import Testing
@testable import AllInOneIMECore

// Issue #36: a bundle snippet (or alias) whose name has a digit in it, such as `addr2` (letters and digits, a letter
// first: `ScriptCommand.isValidName`, docs/extensions.md), is sent as the literal "@addr2" when used inside another
// command's text. In `@question 把地址 @addr2 翻译` the draft shows addr2 as chosen, but the AI receives "@addr2"
// instead of the snippet's text; in `@search 苹果 @addr2 …` the name doesn't end the search phrase. Expected: the
// snippet's text is filled in, as it is for a name of letters only. The text is planned as the composer plans it
// (`CommandPlan.make`, then `fillingSnippets`) and typed into the composer key by key, as a user does.

private let issue36At = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)

/// A bundle's snippet with no placeholders, so it can go inside a text.
private func bundleSnippet(_ name: String, alias: String? = nil, _ text: String) -> BundleSnippet {
    BundleSnippet(bundle: "team", name: name, alias: alias, text: text)
}

/// The text with its inner commands planned, the snippets in it filled in: what the outer command gets once the
/// commands that fetch something have given `outputs`.
private func sent(_ text: String, _ catalog: [Command], outputs: [String] = []) -> String {
    CommandPlan.make(text, commands: catalog).fillingSnippets(SnippetValues()).plan.input(outputs: outputs)
}

/// A text field typing English, with the built-ins, `custom` and the bundle's `snippets`.
private func issue36Field(_ snippets: [BundleSnippet], custom: [CustomCommand] = []) -> Composer {
    let c = Composer(engine: FakeEngine(), voiceEnabled: false, actionKey: .enter)
    c.commands = Command.catalog(custom, snippets: snippets)
    c.inputLanguages = [.chinese, .english]
    c.setInputMode(.english)
    return c
}

/// Each character as a key ("@" as Shift-2, Space as the Space key).
private func issue36Type(_ text: String, _ c: Composer) {
    for ch in text {
        let event = ch == "@" ? issue36At : ch == " " ? spaceKey
            : KeyEvent(keyCode: 0, characters: String(ch), modifiers: ch.isUppercase ? .shift : [])
        _ = c.handleKeyDown(event)
    }
}

private func issue36Starts(_ effects: [Composer.Effect]) -> [(Command, String)] {
    effects.compactMap { if case let .startCommand(command, input, _) = $0 { return (command, input) } else { return nil } }
}

@Suite struct Issue36Tests {
    let addr = bundleSnippet("addr", "9 Elm Rd")
    let addr2 = bundleSnippet("addr2", "1 Main St")

    @Test func aSnippetWithADigitInItsNameIsFilledIn() {
        let catalog = Command.catalog([], snippets: [addr, addr2])
        #expect(catalog.contains { $0.name == "addr2" && $0.kind == .snippet })
        // A name of letters only is filled in today…
        #expect(sent("把地址 @addr 翻译", catalog) == "把地址 9 Elm Rd 翻译")
        // …and one with a digit after its letters is too: before a space, punctuation or the end of the text.
        let plan = CommandPlan.make("把地址 @addr2 翻译", commands: catalog)
        #expect(plan.inner.map(\.command.name) == ["addr2"], "\(plan)")
        #expect(sent("把地址 @addr2 翻译", catalog) == "把地址 1 Main St 翻译")
        #expect(sent("寄到 @addr2。", catalog) == "寄到 1 Main St。")
        #expect(sent("寄到 @addr2", catalog) == "寄到 1 Main St")
        #expect(sent("@Addr2, please", catalog) == "1 Main St, please")
        // Still not after a letter or a digit, and not a longer name.
        #expect(sent("mail a@addr2 now", catalog) == "mail a@addr2 now")
        #expect(sent("寄到 @addr23 吧", catalog) == "寄到 @addr23 吧")
    }

    @Test func anAliasWithADigitInItIsFilledIn() {
        // The config has `sig`: the bundle's snippet answers to its alias.
        let sig = BundleSnippet(bundle: "team", name: "sig", alias: "sig2", text: "Team Wei")
        let mine = CustomCommand(name: "sig", type: .snippet, text: "Wei")
        let catalog = Command.catalog([mine], snippets: [sig])
        #expect(catalog.contains { $0.name == "sig2" && $0.bundle == "team" }, "\(catalog.map(\.name))")
        #expect(sent("署名用 @sig 吧", catalog) == "署名用 Wei 吧")
        #expect(sent("署名用 @sig2 吧", catalog) == "署名用 Team Wei 吧")
    }

    @Test func aSnippetWithADigitInItsNameEndsASearchPhrase() {
        // @search is off in what the input method offers (`Command.webSearchOffered`): added, as its own tests do.
        let catalog = Command.builtins + Command.catalog([], snippets: [addr, addr2]).filter { $0.bundle != nil }
        func inner(_ text: String) -> [String] {
            CommandPlan.make(text, commands: catalog).inner.map { "@\($0.command.name) \($0.argument)" }
        }
        // A name of letters only ends what to search for today…
        #expect(inner("总结 @search 苹果 @addr 附近的店") == ["@search 苹果", "@addr "])
        #expect(sent("总结 @search 苹果 @addr 附近的店", catalog, outputs: ["X"]) == "总结 X 9 Elm Rd 附近的店")
        // …and one with a digit after its letters does too: it isn't searched for, it's filled in.
        #expect(inner("总结 @search 苹果 @addr2 附近的店") == ["@search 苹果", "@addr2 "])
        #expect(sent("总结 @search 苹果 @addr2 附近的店", catalog, outputs: ["X"]) == "总结 X 1 Main St 附近的店")
    }

    @Test func theQuestionReceivesTheSnippetsText() throws {
        // Letters only, as a control.
        let c = issue36Field([addr, addr2])
        issue36Type("@question 把地址 @addr 翻译", c)
        let control = try #require(issue36Starts(c.handleKeyDown(enterKey).effects).first)
        #expect(control.0 == .question && control.1 == "把地址 9 Elm Rd 翻译", "\(control)")

        let d = issue36Field([addr, addr2])
        issue36Type("@question 把地址 @addr2 翻译", d)
        #expect(d.draft == "@question 把地址 @addr2 翻译", "\(d.draft)")
        let effects = d.handleKeyDown(enterKey).effects
        let started = try #require(issue36Starts(effects).first, "\(effects)")
        #expect(started.0 == .question, "\(effects)")
        #expect(started.1 == "把地址 1 Main St 翻译", "\(effects)")
        #expect(effects.contains(.commandUsed("addr2")), "\(effects)")
    }
}
