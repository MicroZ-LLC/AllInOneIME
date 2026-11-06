import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// #43: into a terminal, a line break typed is Return (the shell runs the line), so text with line breaks goes in only as
/// a paste (`SessionServices.pastesInTerminal`), else on one line. Every kind of line break: a bare CR (classic Mac line
/// endings, some Office for Mac copies) and a CRLF are line breaks too, and go in as "\n", which the shell pastes;
/// raw, they went in as typed (the Mac's paste looks for "\n") and the shell ran the first line at once.
/// Driven as the Mac drives it (`FakeHost`): clipboard history (⌃V ⏎), a snippet's `{clipboard}` and its own text, put
/// in or typed out ("Type results out").
@Suite(.serialized)
struct Issue43Tests {
    final class Settings: @unchecked Sendable {
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
        }
    }

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A session in a terminal (or not) that has the focus, its shell keeping `history` (newest first) and the clipboard
    /// `clipboard` (the newest kept, else); the terminal pastes (Accessibility allowed) unless `pastes` is false.
    func host(_ history: [String] = [], clipboard: String? = nil, settings: Settings = Settings(), terminal: Bool = true,
              pastes: Bool = true) -> FakeHost {
        let engine = FakeEngine()
        var services = SessionServices(loadSettings: { settings.config })
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        services.pastesInTerminal = { pastes }
        let host = FakeHost(services: services)
        host.app = terminal ? "com.apple.Terminal" : "com.example.editor"
        host.terminal = terminal
        host.clipboardNow = Self.now
        host.clipboardHistory = history.enumerated().map { ClipboardHistoryItem(text: $1, copiedAt: Self.now - 300 - Double($0) * 60) }
        host.clipboard = (clipboard ?? history.first).map(ClipboardContent.text) ?? .none
        host.keepClipboardHistory()
        host.focus()
        return host
    }

    func snippet(_ name: String, _ text: String) -> CustomCommand {
        var definition = CustomCommand(name: name, type: .snippet)
        definition.text = text
        return definition
    }

    /// Settings with `snippets`, results typed out or not.
    func settings(_ snippets: [CustomCommand] = [], typeOut: Bool = false) -> Settings {
        let settings = Settings()
        settings.config.customCommands = snippets
        settings.config.typeOut = typeOut
        return settings
    }

    /// Runs `@name` in English ("@", the name, ⏎), the clipboard read once the key is done.
    func run(_ name: String, in host: FakeHost) {
        host.composer.setInputMode(.english)
        host.press(FakeHost.at)
        host.type(name)
        host.press(FakeHost.enter)
    }

    /// Whether `text` has a CR anywhere, a CRLF's included (one Character with the "\n").
    func hasCR(_ text: String) -> Bool { text.unicodeScalars.contains("\r") }

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    // MARK: - Clipboard history

    /// The issue's case: lines copied with a bare CR between them, ⌃V ⏎ in a terminal that pastes: they go in with "\n"
    /// (a paste), not with the CR the shell takes for Return.
    @Test func aBareCRFromClipboardHistoryGoesInAsAPasteInATerminal() async {
        await inEnglish {
            let host = host(["echo one\recho two"])
            host.press(FakeHost.controlV)
            host.press(FakeHost.enter)
            #expect(host.document == "echo one\necho two", "\(host.document.debugDescription)")
            #expect(!hasCR(host.document), "no CR reaches the shell: \(host.document.debugDescription)")
        }
    }

    /// A CRLF between the lines (Windows line endings) goes in as "\n" too.
    @Test func aCRLFFromClipboardHistoryGoesInAsAPasteInATerminal() async {
        await inEnglish {
            let host = host(["echo one\r\necho two"])
            host.press(FakeHost.controlV)
            host.press(FakeHost.enter)
            #expect(host.document == "echo one\necho two", "\(host.document.debugDescription)")
            #expect(!hasCR(host.document), "no CR reaches the shell: \(host.document.debugDescription)")
        }
    }

    /// Several entries chosen (⇧↓), one with a bare CR in it: one paste, every line break "\n".
    @Test func severalEntriesWithABareCRGoInAsOnePasteInATerminal() async {
        await inEnglish {
            let host = host(["echo three", "echo one\recho two"])
            host.press(FakeHost.controlV)
            host.press(FakeHost.shiftDown)
            host.press(FakeHost.enter)
            #expect(host.document == "echo one\necho two\necho three", "\(host.document.debugDescription)")
            #expect(!hasCR(host.document), "no CR reaches the shell: \(host.document.debugDescription)")
        }
    }

    /// A terminal that can't paste (no Accessibility) gets a bare CR's lines on one line, as it gets "\n"'s; a field
    /// that isn't a terminal gets the text as copied.
    @Test func aBareCRElsewhereIsAsBefore() async {
        await inEnglish {
            let cannot = host(["echo one\recho two"], pastes: false)
            cannot.press(FakeHost.controlV)
            cannot.press(FakeHost.enter)
            #expect(cannot.document == "echo one echo two", "\(cannot.document.debugDescription)")
            let editor = host(["one\rtwo"], terminal: false)
            editor.press(FakeHost.controlV)
            editor.press(FakeHost.enter)
            #expect(editor.document == "one\rtwo", "\(editor.document.debugDescription)")
        }
    }

    // MARK: - Snippets

    /// A snippet's `{clipboard}` with a bare CR in it, into a terminal that pastes: "\n", put in or typed out.
    @Test(arguments: [false, true])
    func aSnippetsClipboardWithABareCRGoesInAsAPasteInATerminal(_ typeOut: Bool) async {
        await inEnglish {
            let host = host(clipboard: "echo one\recho two", settings: settings([snippet("clip", "{clipboard}")], typeOut: typeOut))
            run("clip", in: host)
            #expect(host.document == "echo one\necho two", "\(host.document.debugDescription)")
            #expect(!hasCR(host.document), "no CR reaches the shell: \(host.document.debugDescription)")
            if typeOut { #expect(host.typedOut == ["echo one\necho two"], "\(host.typedOut.map(\.debugDescription))") }
        }
    }

    /// A snippet whose own text has a bare CR (a bundle's string, a file edited elsewhere), into a terminal that pastes:
    /// "\n", put in or typed out.
    @Test(arguments: [false, true])
    func aSnippetWithABareCRGoesInAsAPasteInATerminal(_ typeOut: Bool) async {
        await inEnglish {
            let host = host(settings: settings([snippet("two", "echo one\recho two")], typeOut: typeOut))
            run("two", in: host)
            #expect(host.document == "echo one\necho two", "\(host.document.debugDescription)")
            #expect(!hasCR(host.document), "no CR reaches the shell: \(host.document.debugDescription)")
            if typeOut { #expect(host.typedOut == ["echo one\necho two"], "\(host.typedOut.map(\.debugDescription))") }
        }
    }
}
