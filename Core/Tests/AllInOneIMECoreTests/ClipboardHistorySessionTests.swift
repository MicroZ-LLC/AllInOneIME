import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Clipboard history in a text field's session (Session/ClipboardHistory.swift): ⌃V shows the texts copied lately in the
/// rows panel, newest first, the first chosen; ↓ ↑ choose, ⇧↓ ⇧↑ select several, ⏎ or Tab puts in what is selected (in
/// the order copied, one per line), → or Esc hides, ⌃V again is the old ⌃V; inside a command the row joins its text as
/// ⌃V's clipboard does. Driven as the Mac drives it (`FakeHost`, its history `keepClipboardHistory`).
@Suite(.serialized)
struct ClipboardHistorySessionTests {
    final class Settings: @unchecked Sendable {
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
        }
    }

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A session in a field that has the focus, its shell keeping `history` (texts newest first, copied a minute apart,
    /// the newest 5 minutes ago), the clipboard `clipboard`.
    func host(_ history: [String] = ["gamma", "beta", "alpha"], clipboard: ClipboardContent? = nil, settings: Settings = Settings(),
              terminal: Bool = false, _ adjust: (inout SessionServices) -> Void = { _ in }) -> FakeHost {
        let engine = FakeEngine()
        var services = SessionServices(loadSettings: { settings.config })
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        adjust(&services)
        let host = FakeHost(services: services)
        host.terminal = terminal
        host.clipboardNow = Self.now
        host.clipboardHistory = history.enumerated().map { ClipboardHistoryItem(text: $1, copiedAt: Self.now - 300 - Double($0) * 60) }
        host.clipboard = clipboard ?? history.first.map(ClipboardContent.text) ?? .none
        host.keepClipboardHistory()
        host.focus()
        return host
    }

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    func texts(_ host: FakeHost) -> [String] { host.panel?.rows.map(\.text) ?? [] }
    func labels(_ host: FakeHost) -> [String] { host.panel?.rows.map(\.label) ?? [] }
    func readsWithin(_ outputs: ArraySlice<SessionOutput>) -> [Int] {
        outputs.compactMap { if case let .readClipboard(id) = $0 { id } else { nil } }
    }

    /// Picks `@improve` ("@", "i", Tab).
    func pickImprove(_ host: FakeHost) {
        host.press(FakeHost.at)
        host.type("i")
        host.press(FakeHost.tab)
    }

    // MARK: - Opening

    /// ⌃V with nothing composed: taken, the clipboard read (an id below 0) once the key is done, the panel shows the
    /// history newest first, the first chosen, each row its text with its length and how long ago, "Clipboard" on its
    /// right; nothing in the field yet. A Chromium page keeps the key (`rowsTookKey`).
    @Test func controlVShowsTheHistoryNewestFirst() async {
        await inEnglish {
            let host = host()
            let before = host.outputs.count
            #expect(host.press(FakeHost.controlV), "⌃V is taken")
            let outputs = host.outputs[before...]
            #expect(readsWithin(outputs).count == 1 && readsWithin(outputs).allSatisfy { $0 < 0 }, "\(Array(outputs))")
            #expect(outputs.contains(.rowsTookKey))
            #expect(texts(host) == ["gamma", "beta", "alpha"] && host.panel?.highlighted == 0, "\(texts(host))")
            #expect(host.panel?.rows.map(\.comment) == ["5 chars · 5 min ago", "4 chars · 6 min ago", "5 chars · 7 min ago"],
                    "\(host.panel?.rows.map(\.comment) ?? [])")
            #expect(host.panel?.detail == "Clipboard" && labels(host) == ["", "", ""], "\(host.panel?.detail ?? "-")")
            #expect(host.panel?.footer.contains("⇧↓") == true, "\(host.panel?.footer ?? "-")")
            #expect(host.document.isEmpty)
        }
    }

    /// ⌃V ⏎ puts in the newest (the clipboard's: today's ⌃V), as a row a key put in (`rowByKey`, then the text), and the
    /// panel goes; ↓ ⏎ the one under it; Tab and keypad Enter as ⏎.
    @Test func returnPutsInTheChosenRow() async {
        await inEnglish {
            let host = host()
            host.press(FakeHost.controlV)
            let before = host.outputs.count
            #expect(host.press(FakeHost.enter))
            let outputs = Array(host.outputs[before...])
            #expect(host.document == "gamma" && host.panel == nil, "\(host.document)")
            #expect(outputs.firstIndex(of: .rowByKey).map { $0 < (outputs.firstIndex(of: .commit("gamma")) ?? -1) } == true, "\(outputs)")
            let down = self.host()
            down.press(FakeHost.controlV)
            #expect(down.press(FakeHost.down) && down.panel?.highlighted == 1)
            #expect(down.press(FakeHost.tab) && down.document == "beta", "\(down.document)")
            let keypad = self.host()
            keypad.press(FakeHost.controlV)
            keypad.press(FakeHost.down)
            keypad.press(FakeHost.down)
            #expect(keypad.press(KeyEvent(keyCode: VirtualKey.keypadEnter, characters: "\u{3}")) && keypad.document == "alpha", "\(keypad.document)")
        }
    }

    /// ↓ and ↑ go around the ends; each says the key put nothing in (`rowsTookKey`).
    @Test func arrowsGoAroundTheEnds() async {
        await inEnglish {
            let host = host()
            host.press(FakeHost.controlV)
            let before = host.outputs.count
            #expect(host.press(FakeHost.up) && host.panel?.highlighted == 2, "↑ on the first: the last")
            #expect(host.press(FakeHost.down) && host.panel?.highlighted == 0, "↓ on the last: the first")
            #expect(host.outputs[before...].filter { $0 == .rowsTookKey }.count == 2)
        }
    }

    /// ⇧↓ ⇧↑ select from the row chosen; the rows selected are marked "✓" and counted on the right; ⏎ puts them in in the
    /// order they were copied (oldest first), one per line, a line break at the end of one not doubled. ⇧↑ back, and
    /// plain ↓ ends the selection.
    @Test func shiftArrowsSelectSeveralPutInOldestFirst() async {
        await inEnglish {
            let host = host(["third", "second\n", "first"])
            host.press(FakeHost.controlV)
            #expect(host.press(FakeHost.shiftDown) && host.press(FakeHost.shiftDown))
            #expect(labels(host) == ["✓", "✓", "✓"] && host.panel?.highlighted == 2, "\(labels(host))")
            #expect(host.panel?.detail == "Clipboard · 3 selected", "\(host.panel?.detail ?? "-")")
            #expect(host.press(FakeHost.shiftDown) && host.panel?.highlighted == 2, "⇧↓ stops at the last")
            #expect(host.press(FakeHost.enter))
            #expect(host.document == "first\nsecond\nthird", "\(host.document.debugDescription)")

            let back = self.host(["c", "b", "a"])
            back.press(FakeHost.controlV)
            back.press(FakeHost.down)
            back.press(FakeHost.shiftDown)
            back.press(FakeHost.shiftUp)
            back.press(FakeHost.shiftUp)
            #expect(labels(back) == ["✓", "✓", ""] && back.panel?.highlighted == 0, "from the row chosen, both ways: \(labels(back))")
            #expect(back.press(FakeHost.shiftUp) && back.panel?.highlighted == 0, "⇧↑ stops at the first")
            back.press(FakeHost.enter)
            #expect(back.document == "b\nc", "\(back.document.debugDescription)")

            let ended = self.host(["c", "b", "a"])
            ended.press(FakeHost.controlV)
            ended.press(FakeHost.shiftDown)
            ended.press(FakeHost.down)
            #expect(labels(ended) == ["", "", ""] && ended.panel?.highlighted == 2 && ended.panel?.detail == "Clipboard")
            ended.press(FakeHost.enter)
            #expect(ended.document == "a")
        }
    }

    /// One row goes in as it was copied, its lines and the line break at its end too.
    @Test func oneRowGoesInAsCopied() async {
        await inEnglish {
            let host = host(["line one\nline two\n"])
            host.press(FakeHost.controlV)
            #expect(texts(host) == ["line one"] && host.panel?.rows.first?.comment.hasPrefix("+1 line ·") == true,
                    "\(host.panel?.rows.first?.comment ?? "-")")
            host.press(FakeHost.enter)
            #expect(host.document == "line one\nline two\n")
        }
    }

    /// → and Esc hide the panel, the key taken, nothing put in; ⌃V again hides it and isn't taken (the app has ⌃V: vim, the
    /// shell); another key (a digit) hides it and goes on as it would, never picking.
    @Test func rightEscapeAndControlVAgain() async {
        await inEnglish {
            for key in [FakeHost.right, FakeHost.escape] {
                let host = host()
                host.press(FakeHost.controlV)
                let before = host.outputs.count
                #expect(host.press(key) && host.panel == nil && host.document.isEmpty)
                #expect(host.outputs[before...].contains(.rowsTookKey))
            }
            // ⌃V again: the app's own paste where it can be posted (0.6.8.2: ⌘V in an app, ⌃V in a terminal), else ⌃V as it is.
            let again = host()
            again.press(FakeHost.controlV)
            #expect(again.press(FakeHost.controlV) && again.pasteKeysPassed == 1, "⌃V again: the app's own paste")
            #expect(again.panel == nil && again.document.isEmpty)
            #expect(again.press(FakeHost.controlV) && again.panel != nil, "and the next ⌃V shows it again")
            let without = host()
            without.passesPasteKey = false
            without.press(FakeHost.controlV)
            #expect(!without.press(FakeHost.controlV) && without.pasteKeysPassed == 0, "without Accessibility ⌃V again is the app's")

            let digit = host()
            digit.composer.setInputMode(.english)
            digit.appTypesKeys = true
            digit.press(FakeHost.controlV)
            #expect(!digit.press(KeyEvent(keyCode: 0x12, characters: "1")), "a digit is typed by the app")
            #expect(digit.document == "1" && digit.panel == nil, "\(digit.document)")
        }
    }

    /// A click puts in the row clicked, alone; the wheel moves the choice, stopping at the ends.
    @Test func clickAndWheel() async {
        await inEnglish {
            let host = host()
            host.press(FakeHost.controlV)
            host.press(FakeHost.shiftDown)
            host.send(.pick(2))
            #expect(host.document == "alpha" && host.panel == nil, "\(host.document)")
            #expect(!host.outputs.contains(.rowByKey), "no key put it in")

            let wheel = self.host()
            wheel.press(FakeHost.controlV)
            wheel.send(.scroll(1))
            #expect(wheel.panel?.highlighted == 1)
            wheel.send(.scroll(10))
            #expect(wheel.panel?.highlighted == 2, "stops at the last")
            wheel.send(.scroll(-10))
            #expect(wheel.panel?.highlighted == 0, "and at the first")
        }
    }

    /// More than 5: 5 shown at a time, the rows shown following the choice, which of them on the right.
    @Test func moreThanFiveScroll() async {
        await inEnglish {
            let host = host((1...12).map { "item \($0)" })
            host.press(FakeHost.controlV)
            #expect(texts(host) == (1...5).map { "item \($0)" } && host.panel?.detail == "Clipboard · 1–5 / 12", "\(host.panel?.detail ?? "-")")
            for _ in 1...5 { host.press(FakeHost.down) }
            #expect(texts(host) == (2...6).map { "item \($0)" } && host.panel?.highlighted == 4 && host.panel?.detail == "Clipboard · 2–6 / 12")
            host.press(FakeHost.up)
            for _ in 1...5 { host.press(FakeHost.up) }
            #expect(texts(host).last == "item 12" && host.panel?.detail == "Clipboard · 8–12 / 12", "around to the last: \(texts(host))")
        }
    }

    /// The limit (`clipboardHistoryLimit`, 5…100): no more than it of the history show.
    @Test func theLimitShows() async {
        await inEnglish {
            let settings = Settings()
            settings.config.clipboardHistoryLimit = 2
            let host = host((1...8).map { "item \($0)" }, settings: settings)
            host.press(FakeHost.controlV)
            #expect(settings.config.clipboardHistoryKept == 5)
            #expect(host.panel?.detail == "Clipboard" && texts(host).count == 5, "5 at least: \(texts(host))")
        }
    }

    /// The clipboard's text the history doesn't have (copied just now, or not kept) comes first, "on the clipboard";
    /// one it has further down comes first, once.
    @Test func theClipboardsTextComesFirst() async {
        await inEnglish {
            let new = host(clipboard: .text("delta"))
            new.press(FakeHost.controlV)
            #expect(texts(new) == ["delta", "gamma", "beta", "alpha"] && new.panel?.rows.first?.comment == "5 chars · on the clipboard",
                    "\(texts(new)) \(new.panel?.rows.first?.comment ?? "-")")
            new.press(FakeHost.enter)
            #expect(new.document == "delta")
            let older = host(clipboard: .text("alpha"))
            older.press(FakeHost.controlV)
            #expect(texts(older) == ["alpha", "gamma", "beta"], "\(texts(older))")
            let blank = host(clipboard: .text("  \n "))
            blank.press(FakeHost.controlV)
            #expect(texts(blank) == ["gamma", "beta", "alpha"], "\(texts(blank))")
        }
    }

    /// A row shows the first line that isn't blank, trimmed, 80 characters at most; "+N lines"; how long ago in hours.
    @Test func whatARowSays() async {
        await inEnglish {
            let long = String(repeating: "x", count: 100)
            let host = host(["\n\n  \(long)  \nsecond\nthird"])
            host.clipboardHistory[0].copiedAt = Self.now - 2 * 3600
            host.press(FakeHost.controlV)
            #expect(texts(host) == [String(repeating: "x", count: 80) + "…"], "\(texts(host))")
            #expect(host.panel?.rows.first?.comment == "+2 lines · 2 hr ago", "\(host.panel?.rows.first?.comment ?? "-")")
        }
    }

    /// The first time the panel shows on the device, its footer says where the history is kept and how to turn it off;
    /// the keys after.
    @Test func theFirstShowingSaysWhereItIsKept() async {
        await inEnglish {
            let host = host()
            host.firstClipboardPanel = true
            host.press(FakeHost.controlV)
            #expect(host.panel?.footer == "Kept on this Mac only; turn it off in Settings → General → Clipboard history",
                    "\(host.panel?.footer ?? "-")")
            host.press(FakeHost.escape)
            host.press(FakeHost.controlV)
            #expect(host.panel?.footer.contains("⇧↓") == true, "\(host.panel?.footer ?? "-")")
        }
    }

    /// Nothing to show (no text on the clipboard, nothing kept): no panel, the composer's notice.
    @Test func nothingToShow() async {
        await inEnglish {
            let host = host([], clipboard: ClipboardContent.none)
            #expect(host.press(FakeHost.controlV))
            #expect(host.panel == nil && host.noticeAlone == host.composer.messages.nothingToPaste, "\(host.noticeAlone ?? "-")")
        }
    }

    // MARK: - Where ⌃V is as before

    /// A shell that keeps no history (`.unavailable`, the default: Windows'), the history turned off, secure input, pinyin
    /// being typed: ⌃V as before 0.6.8, the app's with nothing composed.
    @Test func controlVAsBefore() async {
        await inEnglish {
            let none = FakeHost(services: SessionServices(loadSettings: { Settings().config }))
            none.focus()
            #expect(!none.press(FakeHost.controlV) && none.panel == nil)
            let settings = Settings()
            settings.config.clipboardHistory = false
            let off = host(settings: settings)
            #expect(!off.press(FakeHost.controlV) && off.panel == nil && readsWithin(off.outputs[...]).isEmpty)
            let secure = host()
            secure.secure = true
            #expect(!secure.press(FakeHost.controlV) && secure.panel == nil && readsWithin(secure.outputs[...]).isEmpty)
            let pinyin = host()
            pinyin.type("ni")
            pinyin.press(FakeHost.controlV)
            #expect(texts(pinyin).allSatisfy { !["gamma", "beta", "alpha"].contains($0) } && readsWithin(pinyin.outputs[...]).isEmpty,
                    "pinyin being typed: not the history (\(texts(pinyin)))")
            let shifted = host()
            #expect(!shifted.press(KeyEvent(keyCode: 0x09, characters: "\u{16}", charactersIgnoringModifiers: "V", modifiers: [.control, .shift])))
            #expect(shifted.panel == nil, "⌃⇧V isn't ⌃V")
        }
    }

    /// A field where the shell can't keep the panel's keys from the app (`clipboardPanelAllowed` false: the Mac's Chromium
    /// page that tells no caret): ⌃V as before 0.6.8 there, the app's with nothing composed, the composer's in a command
    /// (the clipboard read for it, joined); allowed again, the panel.
    @Test func controlVAsBeforeWhereThePanelIsNotAllowed() async {
        await inEnglish {
            let host = host()
            host.session.clipboardPanelAllowed = false
            #expect(!host.press(FakeHost.controlV) && host.panel == nil && readsWithin(host.outputs[...]).isEmpty)
            #expect(!host.outputs.contains(.rowsTookKey), "the key is the app's: nothing to keep from it")
            let command = self.host(clipboard: .text("from the clipboard"))
            pickImprove(command)
            command.session.clipboardPanelAllowed = false
            let before = command.outputs.count
            #expect(command.press(FakeHost.controlV))
            #expect(readsWithin(command.outputs[before...]).allSatisfy { $0 > 0 } && command.composer.draft == "@improve from the clipboard"
                    && !texts(command).contains("gamma"), "\(command.composer.draft)")
            host.session.clipboardPanelAllowed = true
            #expect(host.press(FakeHost.controlV) && texts(host) == ["gamma", "beta", "alpha"], "\(texts(host))")
        }
    }

    // MARK: - Inside a command

    /// In a command's text ⌃V shows the history too; the row chosen joins the text as ⌃V's clipboard does (its lines made
    /// one), the panel giving way to the command's; several, in the order copied. Esc gives the command's panel back.
    @Test func inACommandTheRowJoinsItsText() async {
        await inEnglish {
            let host = host(["second line\nmore", "first"])
            pickImprove(host)
            #expect(host.composer.draft == "@improve ")
            #expect(host.press(FakeHost.controlV) && texts(host) == ["second line", "first"], "\(texts(host))")
            host.press(FakeHost.shiftDown)
            #expect(host.press(FakeHost.enter))
            #expect(host.composer.draft == "@improve first second line more", "\(host.composer.draft)")
            #expect(host.document.isEmpty && host.panel?.rows.map(\.text) != ["second line", "first"])

            let one = self.host()
            pickImprove(one)
            one.press(FakeHost.controlV)
            one.press(FakeHost.down)
            one.press(FakeHost.enter)
            #expect(one.composer.draft == "@improve beta", "\(one.composer.draft)")

            let escaped = self.host()
            pickImprove(escaped)
            escaped.press(FakeHost.controlV)
            #expect(escaped.press(FakeHost.escape) && escaped.composer.draft == "@improve " && !texts(escaped).contains("gamma"))
        }
    }

    /// `@note` keeps the lines of what goes in.
    @Test func aNoteKeepsTheLines() async {
        await inEnglish {
            let host = host(["two\n", "one"])
            host.press(FakeHost.at)
            host.type("note")
            host.press(FakeHost.tab)
            #expect(host.composer.draftCommand?.kind == .note, "\(host.composer.draft)")
            host.press(FakeHost.controlV)
            host.press(FakeHost.shiftDown)
            host.press(FakeHost.enter)
            #expect(host.composer.draft.hasSuffix("one\ntwo"), "\(host.composer.draft.debugDescription)")
        }
    }

    /// In a command ⌃V ⌃V is today's ⌃V: the clipboard read for the command (an id above 0) and joined.
    @Test func inACommandControlVAgainIsTodays() async {
        await inEnglish {
            let host = host(clipboard: .text("from the clipboard"))
            pickImprove(host)
            host.press(FakeHost.controlV)
            let before = host.outputs.count
            #expect(host.press(FakeHost.controlV))
            #expect(readsWithin(host.outputs[before...]).allSatisfy { $0 > 0 } && host.composer.draft == "@improve from the clipboard",
                    "\(host.composer.draft)")
        }
    }

    /// In a command where the history isn't allowed: today's ⌃V, no panel.
    @Test func inACommandNotAllowedIsTodays() async {
        await inEnglish {
            let host = host(clipboard: .text("copied"))
            host.clipboardHistoryState = .notAllowed
            pickImprove(host)
            let before = host.outputs.count
            #expect(host.press(FakeHost.controlV))
            #expect(readsWithin(host.outputs[before...]).allSatisfy { $0 > 0 } && host.composer.draft == "@improve copied", "\(host.composer.draft)")
        }
    }

    // MARK: - Not allowed, the image

    /// Not allowed yet: the panel has what's on the clipboard now, and last a row saying how to keep a history; ⏎ on it
    /// opens where to allow it, nothing put in; ⌃V ⏎ is today's (the clipboard's text).
    @Test func notAllowedShowsTheClipboardAndHowToKeepAHistory() async {
        await inEnglish {
            let host = host([], clipboard: .text("now"))
            host.clipboardHistoryState = .notAllowed
            host.press(FakeHost.controlV)
            #expect(texts(host) == ["now", "To keep a history, allow Paste from Other Apps"], "\(texts(host))")
            #expect(host.panel?.rows.last?.pickable == false)
            host.press(FakeHost.up)
            #expect(host.press(FakeHost.enter) && host.permissionOpened == 1 && host.document.isEmpty && host.panel == nil)
            let today = self.host([], clipboard: .text("now"))
            today.clipboardHistoryState = .notAllowed
            today.press(FakeHost.controlV)
            today.press(FakeHost.enter)
            #expect(today.document == "now")
        }
    }

    /// An image on the clipboard is the first row, chosen: ⏎ gives the app its own paste key (`passPasteKey`), nothing put
    /// in; where it can't (no Accessibility) the row says it's on the clipboard already and ⏎ only hides; ⌃V ⌃V pastes as
    /// the app does.
    @Test func anImageIsTheFirstRow() async {
        await inEnglish {
            let host = host(clipboard: .image(Data([0x89, 0x50])))
            host.press(FakeHost.controlV)
            #expect(texts(host) == ["Image on the clipboard", "gamma", "beta", "alpha"] && host.panel?.highlighted == 0, "\(texts(host))")
            #expect(host.press(FakeHost.enter) && host.pasteKeysPassed == 1 && host.document.isEmpty && host.panel == nil)
            let without = self.host(clipboard: .image(Data([0x89, 0x50])))
            without.passesPasteKey = false
            without.press(FakeHost.controlV)
            #expect(without.panel?.rows.first?.comment == "on the clipboard already", "\(without.panel?.rows.first?.comment ?? "-")")
            #expect(without.press(FakeHost.enter) && without.pasteKeysPassed == 0 && without.panel == nil)
            let twice = self.host(clipboard: .image(Data([0x89, 0x50])))
            twice.press(FakeHost.controlV)
            #expect(twice.press(FakeHost.controlV) && twice.pasteKeysPassed == 1)
        }
    }

    /// In a command, the image row's ⏎ is today's ⌃V: the clipboard read for the command, its image taken as a
    /// screenshot.
    @Test func inACommandTheImageIsTodays() async {
        await inEnglish {
            let host = host(clipboard: .image(Data([0x89, 0x50])))
            pickImprove(host)
            host.press(FakeHost.controlV)
            #expect(texts(host).first == "Image on the clipboard" && host.panel?.rows.first?.comment == "")
            let before = host.outputs.count
            host.press(FakeHost.enter)
            #expect(readsWithin(host.outputs[before...]).count == 1 && readsWithin(host.outputs[before...]).allSatisfy { $0 > 0 },
                    "\(Array(host.outputs[before...]))")
            #expect(host.pasteKeysPassed == 0)
        }
    }

    // MARK: - Terminals

    /// In a terminal lines go in as a paste where it can paste, else on one line (a line break typed there is Return).
    @Test func linesIntoATerminal() async {
        await inEnglish {
            let pastes = host(["echo one\necho two"], terminal: true) { $0.pastesInTerminal = { true } }
            pastes.press(FakeHost.controlV)
            pastes.press(FakeHost.enter)
            #expect(pastes.document == "echo one\necho two", "\(pastes.document.debugDescription)")
            let cannot = host(["echo one\necho two"], terminal: true) { $0.pastesInTerminal = { false } }
            cannot.press(FakeHost.controlV)
            cannot.press(FakeHost.enter)
            #expect(cannot.document == "echo one echo two", "\(cannot.document.debugDescription)")
        }
    }

    /// The field left: the panel goes.
    @Test func leavingTheFieldHidesIt() async {
        await inEnglish {
            let host = host()
            host.press(FakeHost.controlV)
            host.send(.blur)
            #expect(host.panel == nil)
            host.focus()
            #expect(host.press(FakeHost.enter) == false && host.document.isEmpty, "⏎ is the app's again")
        }
    }
}

extension ClipboardHistorySessionTests {
    /// Secure input come on before the clipboard was read (a password prompt): nothing shows, nothing is read into it.
    @Test func secureInputBeforeTheRead() async {
        await inEnglish {
            let secure = Locked(initialState: false)
            let host = host { $0.secureInputActive = { secure.withLock { $0 } } }
            let asked = host.session.handle(.key(FakeHost.controlV, host.context)).outputs
            guard let id = asked.lazy.compactMap({ if case let .readClipboard(id) = $0 { id } else { nil } }).first else {
                Issue.record("the clipboard isn't asked for: \(asked)")
                return
            }
            secure.withLock { $0 = true }
            host.send(.clipboard(.text("hunter2"), id: id))
            #expect(host.panel == nil && host.document.isEmpty)
        }
    }
}

/// Suggestions' rows showing when ⌃V is pressed: the history takes their place (a paste ends the token), and the row
/// chosen goes in after what was typed.
@Suite(.serialized, SuggestionsOneAtATime())
struct ClipboardHistoryInPlaceOfRowsTests {
    @Test func theHistoryTakesTheRowsPlace() async throws {
        try await withInterfaceLanguage("en") {
            let world = SuggestionsWorld()
            try world.github(items: SuggestionsScrollTests.issues(3), manifest: SuggestionsPlugins.githubManifest(query: false))
            let field = world.field()
            field.type("#7")
            #expect(field.settle { field.issuesShown == SuggestionsScrollTests.shown(1...3) }, "\(field.issuesShown)")
            field.host.clipboardHistory = [ClipboardHistoryItem(text: "copied text", copiedAt: Date())]
            field.host.clipboard = .text("copied text")
            field.host.keepClipboardHistory()
            #expect(field.press(FakeHost.controlV))
            #expect(field.host.panel?.rows.map(\.text) == ["copied text"] && field.issuesShown.isEmpty,
                    "\(field.host.panel?.rows.map(\.text) ?? [])")
            #expect(field.press(SuggestionKeys.enter))
            #expect(field.document == "#7copied text" && field.host.panel == nil, "\(field.document)")
        }
    }
}
