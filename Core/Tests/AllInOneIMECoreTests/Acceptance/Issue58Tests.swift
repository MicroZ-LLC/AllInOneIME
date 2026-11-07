import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// #58: into a terminal, only text with a line break goes in as a paste (where the shell can paste) or on one line
/// (where it can't: `SessionServices.pastesInTerminal`, no Accessibility). One-line text with a tab or a control
/// character (ESC, ^C, ^D) is inserted as it is: the terminal takes a tab as the shell's completion (the command line
/// garbled) and ^D as the end of input (an empty shell closes). A Makefile line ("\tmake test") or a TSV pair copied,
/// then ⌃V and ⏎ on its clipboard history row, or a snippet with a tab. Expected: the text arrives as copied, through
/// the paste, or as command output already does (`CommandRunner.oneLine`: tabs become spaces, nothing that would run or
/// complete). Here a terminal's field where the shell can't paste: what the session commits has no tab or other control
/// character, its words as they were. Where the shell can paste, which of the two it does is the shell's and the
/// session's together: Tests/AllInOneIMEMacTests/Acceptance/Issue58Tests.swift. Outside a terminal a tab goes in as
/// copied, as before.
@Suite(.serialized)
struct Issue58Tests {
    /// One-line texts a terminal mustn't get as they are, each with the words it holds: a tab (completion), ESC, ^C, ^D.
    static let texts: [(text: String, words: [String])] = [
        ("\tmake test", ["make", "test"]),  // a Makefile line
        ("name\tvalue", ["name", "value"]),  // a TSV pair
        ("echo hi\u{1B}", ["echo", "hi"]),
        ("\u{03}sleep 1", ["sleep", "1"]),
        ("exit\u{04}", ["exit"]),
    ]

    /// A field with focus, typing English, a clipboard history of `items` (newest first) and the newest on the clipboard;
    /// a terminal's (where the shell can paste or not, `pastes`) or not.
    private func host(items: [String] = [], terminal: Bool, pastes: Bool = false, config: Config = .default) -> FakeHost {
        var services = SessionServices(loadSettings: { config })
        services.pastesInTerminal = { pastes }
        let composer = Composer()
        composer.setInputMode(.english)
        let host = FakeHost(services: services, composer: composer)
        host.terminal = terminal
        host.clipboard = items.first.map { .text($0) } ?? .none
        host.clipboardNow = Date(timeIntervalSince1970: 1_000_000)
        host.clipboardHistory = items.enumerated().map { index, text in
            ClipboardHistoryItem(text: text, copiedAt: host.clipboardNow.addingTimeInterval(-Double(index + 1) * 60))
        }
        host.keepClipboardHistory()
        host.focus()
        return host
    }

    /// What the session committed after output `from`.
    private func commits(_ host: FakeHost, from: Int) -> [String] {
        host.outputs.dropFirst(from).compactMap { output -> String? in
            switch output {
            case let .commit(text), let .commitAfterKey(text), let .typeOut(text): return text
            default: return nil
            }
        }
    }

    /// `text` with its control characters shown (`\t`, `\u{1B}`).
    private func shown(_ text: String) -> String { text.unicodeScalars.map { $0.escaped(asASCII: true) }.joined() }

    private func controls(_ text: String) -> [Unicode.Scalar] {
        text.unicodeScalars.filter { $0.properties.generalCategory == .control }
    }

    /// The issue's trigger: copied, then ⌃V and ⏎ on its row in a terminal where the shell can't paste. What goes in
    /// has no tab or other control character, and its words as they were.
    @Test func aClipboardRowWithATabOrAControlCharacterReachesATerminalWithoutIt() async throws {
        try await withInterfaceLanguage("en") {
            for (text, words) in Self.texts {
                let h = host(items: [text, "an older copy"], terminal: true)
                #expect(h.press(FakeHost.controlV))
                #expect(h.panel?.rows.first?.text.contains(words[0]) == true, "\(shown(text)): the row \(h.panel?.rows.map(\.text) ?? [])")
                let before = h.outputs.count
                h.press(FakeHost.enter)
                let put = commits(h, from: before).joined()
                #expect(!put.isEmpty, "\(shown(text)): nothing went in")
                #expect(controls(put).isEmpty, "\(shown(text)) went into the terminal as \(shown(put)): the shell gets its control characters")
                #expect(put.split(whereSeparator: \.isWhitespace).map(String.init) == words,
                        "\(shown(text)) went into the terminal as \(shown(put))")
                #expect(controls(h.document).isEmpty, "\(shown(text)): the terminal has \(shown(h.document))")
            }
        }
    }

    /// The Makefile line among other rows, ↓ to it: the same.
    @Test func anOlderRowWithATabReachesATerminalWithoutIt() async throws {
        try await withInterfaceLanguage("en") {
            let h = host(items: ["git status", "\tmake test"], terminal: true)
            #expect(h.press(FakeHost.controlV))
            h.press(FakeHost.down)
            let before = h.outputs.count
            h.press(FakeHost.enter)
            let put = commits(h, from: before).joined()
            #expect(controls(put).isEmpty, "the Makefile line went into the terminal as \(shown(put))")
            #expect(put.split(whereSeparator: \.isWhitespace) == ["make", "test"], "\(shown(put))")
        }
    }

    /// A snippet with a tab (`@tsv`), in a terminal where the shell can't paste: the same.
    @Test func aSnippetWithATabReachesATerminalWithoutIt() async throws {
        try await withInterfaceLanguage("en") {
            for (text, words) in [("name\tvalue", ["name", "value"]), ("\tmake test", ["make", "test"])] {
                var config = Config.default
                config.uiLanguage = "en"
                config.customCommands = [CustomCommand(name: "tsv", type: .snippet, text: text)]
                let h = host(terminal: true, config: config)
                h.composer.setInputMode(.english)
                let before = h.outputs.count
                h.press(FakeHost.at)
                h.type("tsv")
                h.press(FakeHost.enter)
                let put = commits(h, from: before).joined()
                #expect(!put.isEmpty, "@tsv (\(shown(text))): nothing went in")
                #expect(controls(put).isEmpty, "@tsv (\(shown(text))) went into the terminal as \(shown(put))")
                #expect(put.split(whereSeparator: \.isWhitespace).map(String.init) == words, "@tsv went in as \(shown(put))")
                #expect(controls(h.document).isEmpty, "@tsv: the terminal has \(shown(h.document))")
            }
        }
    }

    /// Outside a terminal the tab is the text's: the row and the snippet go in as copied, as before.
    @Test func outsideATerminalATabGoesInAsCopied() async throws {
        try await withInterfaceLanguage("en") {
            let h = host(items: ["\tmake test"], terminal: false)
            #expect(h.press(FakeHost.controlV))
            let before = h.outputs.count
            h.press(FakeHost.enter)
            #expect(commits(h, from: before) == ["\tmake test"], "\(commits(h, from: before).map(shown))")

            var config = Config.default
            config.uiLanguage = "en"
            config.customCommands = [CustomCommand(name: "tsv", type: .snippet, text: "name\tvalue")]
            let s = host(terminal: false, config: config)
            s.composer.setInputMode(.english)
            s.press(FakeHost.at)
            s.type("tsv")
            s.press(FakeHost.enter)
            #expect(s.document == "name\tvalue", "\(shown(s.document))")
        }
    }
}
