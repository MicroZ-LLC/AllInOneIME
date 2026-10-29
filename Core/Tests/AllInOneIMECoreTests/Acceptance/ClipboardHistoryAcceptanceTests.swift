import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Clipboard history acceptance index (the shell supplies copied items and clipboard contents):
// defaultHistoryShowsNewestClipboardTextOnceAndReturnInsertsIt: default panel, deduplication, choice, insertion.
// limitsClampAndLoweringDropsOldestRows: 20 default, 5…100 bounds, immediate lower limit.
// rowsShowTrimmedFirstLineLengthLinesAndAge: text and comment presented to the user.
// fiveRowsScrollWithKeysAndWheelAndWrapWithKeys: viewport, footer range, arrows, wheel, wrap.
// digitAndOtherKeyDismissWithoutPicking: ordinary typing continues; digits never choose.
// rightAndEscapeDismissAndConsumeTheirKeys: panel dismissal and key ownership.
// shiftSelectionMarksRowsAndInsertsOldestFirst: selection, footer, insertion order.
// clickInsertsOnlyClickedRowAndPlainArrowEndsSelection: click and selection reset.
// commandChoicePastesLikeControlV: command panel and one-line, 2,000-character paste.
// noteChoiceKeepsLinesAndItsLargerLimit: @note paste rules.
// imageRowPassesPasteKeyOrHidesAndCommandReadsImage: screenshot behavior.
// secondControlVFallsThroughOrUsesTodaysCommandPaste: escape hatch while panel is open.
// offAndUnavailableMatchLegacyControlV: history-disabled/unavailable behavior.
// deniedPermissionShowsCurrentTextAndHowToAllow: permission row and command fallback.
// secureInputAndEmptyClipboardNeverShowRows: secure and empty cases.
// rowKeysUseChromiumSafeOutputsAndNeverChangeClipboard: rowsTookKey, rowByKey, commit.
// terminalMultilineInsertsAsOneCommit: terminal paste semantics.
// firstShowingFooterAppearsOnce: local-only and off guidance.
// settingsAreLocalAndDefaultOn: config defaults, clamp, and iCloud exclusion.
@Suite(.serialized)
struct ClipboardHistoryAcceptanceTests {
    private func host(items: [String] = [], clipboard: ClipboardContent = .none,
                      state: ClipboardHistoryState = .recording, config: Config = .default,
                      terminal: Bool = false, withHistory: Bool = true) -> FakeHost {
        let services = SessionServices(loadSettings: { config })
        let composer = Composer()
        composer.setInputMode(.english)
        let host = FakeHost(services: services, composer: composer)
        host.terminal = terminal
        host.clipboard = clipboard
        host.clipboardHistoryState = state
        host.clipboardNow = Date(timeIntervalSince1970: 1_000_000)
        host.clipboardHistory = items.enumerated().map { index, text in
            ClipboardHistoryItem(text: text, copiedAt: host.clipboardNow.addingTimeInterval(-Double(index + 1) * 60))
        }
        if withHistory { host.keepClipboardHistory() }
        host.focus()
        return host
    }

    private func open(_ host: FakeHost) {
        #expect(host.press(FakeHost.controlV))
    }

    private func command(_ host: FakeHost, _ name: String = "improve") {
        host.type("@\(name) ")
        #expect(host.composer.draft == "@\(name) ")
    }

    @Test func defaultHistoryShowsNewestClipboardTextOnceAndReturnInsertsIt() async throws {
        try await withInterfaceLanguage("en") {
            let h = host(items: ["older", "oldest"], clipboard: .text("just copied"))
            open(h)
            #expect(h.panel?.rows.map(\.text) == ["just copied", "older", "oldest"])
            #expect(h.panel?.highlighted == 0)
            #expect(h.panel?.detail == "Clipboard")
            #expect(h.press(FakeHost.enter))
            #expect(h.document == "just copied")
            #expect(h.clipboard == .text("just copied"))

            let duplicate = host(items: ["older", "same"], clipboard: .text("same"))
            open(duplicate)
            #expect(duplicate.panel?.rows.map(\.text) == ["same", "older"])
        }
    }

    @Test func limitsClampAndLoweringDropsOldestRows() async throws {
        try await withInterfaceLanguage("en") {
            #expect(Config.default.clipboardHistoryKept == 20)
            var config = Config.default
            config.clipboardHistoryLimit = 2
            #expect(config.clipboardHistoryKept == 5)
            config.clipboardHistoryLimit = 200
            #expect(config.clipboardHistoryKept == 100)
            let items = (0..<105).map { "item \($0)" }
            let h = host(items: items, clipboard: .text("item 0"), config: config)
            open(h)
            #expect(h.panel?.detail?.contains("/ 100") == true)
            h.send(.scroll(200))
            #expect(h.panel?.rows.last?.text == "item 99")
            config.clipboardHistoryLimit = 5
            // A Settings change is observed by an existing session.
            h.session.services.loadSettings = { config }
            h.send(.configChanged)
            h.press(FakeHost.escape)
            open(h)
            #expect(h.panel?.rows.count == 5)
            h.send(.scroll(200))
            #expect(h.panel?.rows.last?.text == "item 4")

            let defaultHost = host(items: items, clipboard: .text("item 0"))
            open(defaultHost)
            #expect(defaultHost.panel?.detail?.contains("/ 20") == true)
        }
    }

    @Test func rowsShowTrimmedFirstLineLengthLinesAndAge() async throws {
        try await withInterfaceLanguage("en") {
            let h = host(items: ["  first line  \nsecond\nthird", "short"], clipboard: .text("fresh"))
            open(h)
            let rows = h.panel?.rows ?? []
            #expect(rows.map(\.text) == ["fresh", "first line", "short"])
            #expect(rows[0].comment == "5 chars · on the clipboard")
            #expect(rows[1].comment.contains("+2 lines"))
            #expect(rows[1].comment.contains("ago"))
            #expect(rows[2].comment.contains("5 chars"))
            #expect(rows.allSatisfy { $0.label.isEmpty || $0.label == " " })
        }
    }

    @Test func fiveRowsScrollWithKeysAndWheelAndWrapWithKeys() async throws {
        try await withInterfaceLanguage("en") {
            let h = host(items: (0..<8).map { "item \($0)" }, clipboard: .text("item 0"))
            open(h)
            #expect(h.panel?.rows.map(\.text) == (0..<5).map { "item \($0)" })
            #expect(h.panel?.detail == "Clipboard · 1–5 / 8")
            for _ in 0..<5 { #expect(h.press(FakeHost.down)) }
            #expect(h.panel?.rows.map(\.text) == (1..<6).map { "item \($0)" })
            #expect(h.panel?.detail == "Clipboard · 2–6 / 8")
            h.send(.scroll(20))
            #expect(h.panel?.highlighted == 4)
            #expect(h.panel?.rows.last?.text == "item 7")
            #expect(h.panel?.detail == "Clipboard · 4–8 / 8")
            #expect(h.press(FakeHost.down))
            #expect(h.panel?.highlighted == 0)
            #expect(h.panel?.rows.first?.text == "item 0")
            #expect(h.press(FakeHost.up))
            #expect(h.panel?.rows.last?.text == "item 7")
        }
    }

    @Test func digitAndOtherKeyDismissWithoutPicking() async throws {
        try await withInterfaceLanguage("en") {
            let digit = host(items: ["one", "two"], clipboard: .text("one"))
            digit.appTypesKeys = true
            open(digit)
            digit.press(KeyEvent(keyCode: 0, characters: "2"))
            #expect(digit.panel == nil)
            #expect(digit.document == "2")
            #expect(!digit.outputs.contains(.rowByKey))

            let letter = host(items: ["one"], clipboard: .text("one"))
            letter.appTypesKeys = true
            open(letter)
            letter.press(KeyEvent(keyCode: 0, characters: "x"))
            #expect(letter.panel == nil)
            #expect(letter.document == "x")
        }
    }

    @Test func rightAndEscapeDismissAndConsumeTheirKeys() async throws {
        try await withInterfaceLanguage("en") {
            for key in [FakeHost.right, FakeHost.escape] {
                let h = host(items: ["one"], clipboard: .text("one"))
                open(h)
                let before = h.outputs.count
                #expect(h.press(key))
                #expect(h.panel == nil && h.document.isEmpty)
                #expect(h.outputs.dropFirst(before).contains(.rowsTookKey))
            }
        }
    }

    @Test func shiftSelectionMarksRowsAndInsertsOldestFirst() async throws {
        try await withInterfaceLanguage("en") {
            let h = host(items: ["new", "middle\n", "old\n"], clipboard: .text("new"))
            open(h)
            #expect(h.press(FakeHost.shiftDown))
            #expect(h.press(FakeHost.shiftDown))
            #expect(h.panel?.rows.map(\.label) == ["✓", "✓", "✓"])
            #expect(h.panel?.detail?.contains("3 selected") == true)
            #expect(h.press(FakeHost.shiftUp))
            #expect(h.panel?.rows.map(\.label) == ["✓", "✓", ""])
            #expect(h.press(FakeHost.shiftDown))
            #expect(h.press(FakeHost.enter))
            #expect(h.document == "old\nmiddle\nnew")
        }
    }

    @Test func clickInsertsOnlyClickedRowAndPlainArrowEndsSelection() async throws {
        try await withInterfaceLanguage("en") {
            let clicked = host(items: ["new", "middle", "old"], clipboard: .text("new"))
            open(clicked)
            clicked.press(FakeHost.shiftDown)
            clicked.send(.pick(2))
            #expect(clicked.document == "old")
            #expect(clicked.panel == nil)

            let moved = host(items: ["new", "middle", "old"], clipboard: .text("new"))
            open(moved)
            moved.press(FakeHost.shiftDown)
            moved.press(FakeHost.down)
            #expect(moved.panel?.detail?.contains("selected") == false)
            #expect(moved.panel?.rows.contains(where: { $0.label == "✓" }) == false)
            moved.press(FakeHost.enter)
            #expect(moved.document == "old")
        }
    }

    @Test func commandChoicePastesLikeControlV() async throws {
        try await withInterfaceLanguage("en") {
            let newest = host(items: ["older"], clipboard: .text("latest\ncopy"))
            command(newest)
            open(newest)
            #expect(newest.panel?.highlighted == 0)
            newest.press(FakeHost.enter)
            #expect(newest.composer.draft == "@improve latest copy")

            let h = host(items: ["older\ntext", "other"], clipboard: .text("newest"))
            command(h)
            open(h)
            #expect(h.panel?.rows.map(\.text) == ["newest", "older", "other"])
            h.press(FakeHost.down)
            h.press(FakeHost.enter)
            #expect(h.composer.draft == "@improve older text")

            // "As ⌃V appends the clipboard today": today's ⌃V refuses more than 2,000 characters with a notice (it
            // doesn't cut them), so a row that long leaves the draft as it was and says so.
            let long = String(repeating: "a", count: 2_100)
            let capped = host(items: [long], clipboard: .text("now"))
            command(capped)
            let draft = capped.composer.draft
            open(capped)
            #expect(capped.panel?.rows.count == 2)
            capped.press(FakeHost.down)
            #expect(capped.panel?.highlighted == 1)
            capped.press(FakeHost.enter)
            #expect(capped.composer.draft == draft)
            #expect(capped.panel?.detail == "The clipboard text is too long: 2000 characters at most")
        }
    }

    @Test func noteChoiceKeepsLinesAndItsLargerLimit() async throws {
        try await withInterfaceLanguage("en") {
            let long = String(repeating: "n", count: 20_100) + "\nlast"
            let h = host(items: [long], clipboard: .text("now"))
            command(h, "note")
            let noteDraft = h.composer.draft
            open(h)
            #expect(h.panel?.rows.count == 2)
            h.press(FakeHost.down)
            #expect(h.panel?.highlighted == 1)
            h.press(FakeHost.enter)
            // Today's ⌃V refuses more than 20,000 characters for a note with a notice: the draft stays as it was.
            #expect(h.composer.draft == noteDraft)
            #expect(h.panel?.detail?.hasPrefix("The clipboard text is too long") == true)
            let lines = host(items: ["first\nsecond"], clipboard: .text("now"))
            command(lines, "note")
            open(lines)
            lines.press(FakeHost.down)
            lines.press(FakeHost.tab)
            #expect(lines.composer.draft == "@note first\nsecond")
        }
    }

    @Test func imageRowPassesPasteKeyOrHidesAndCommandReadsImage() async throws {
        try await withInterfaceLanguage("en") {
            let image = ClipboardContent.image(Data([1, 2, 3]))
            let h = host(items: ["old"], clipboard: image)
            open(h)
            #expect(h.panel?.rows.first?.text == "Image on the clipboard")
            #expect(h.panel?.highlighted == 0)
            h.press(FakeHost.enter)
            #expect(h.pasteKeysPassed == 1)
            #expect(h.document.isEmpty)

            let denied = host(items: ["old"], clipboard: image)
            denied.passesPasteKey = false
            open(denied)
            // Changed by the spec's owner (0.6.8.2): without the paste key posted, ⌃V again gives the app ⌃V, which pastes
            // nothing in most apps (Slack); the row says the image is on the clipboard already, for the app's own paste.
            #expect(denied.panel?.rows.first?.comment == "on the clipboard already")
            denied.press(FakeHost.enter)
            #expect(denied.pasteKeysPassed == 0 && denied.panel == nil)

            let reply = host(items: ["old"], clipboard: image)
            command(reply, "reply")
            open(reply)
            #expect(reply.panel?.rows.first?.text == "Image on the clipboard")
            reply.press(FakeHost.enter)
            #expect(reply.composer.attachment != nil)
        }
    }

    @Test func secondControlVFallsThroughOrUsesTodaysCommandPaste() async throws {
        try await withInterfaceLanguage("en") {
            // Changed by the spec's owner (0.6.8.2, the owner: in Slack ⌃V ⌃V didn't paste the image): outside a command ⌃V
            // again gives the app its own paste key where it can be posted (⌘V in an app, ⌃V in a terminal); without
            // that (no Accessibility) the app gets ⌃V as it is, as before.
            let outside = host(items: ["old"], clipboard: .text("now"))
            open(outside)
            #expect(outside.press(FakeHost.controlV) && outside.pasteKeysPassed == 1)
            #expect(outside.panel == nil && outside.document.isEmpty)
            let unposted = host(items: ["old"], clipboard: .text("now"))
            unposted.passesPasteKey = false
            open(unposted)
            #expect(!unposted.press(FakeHost.controlV) && unposted.pasteKeysPassed == 0)
            #expect(unposted.panel == nil && unposted.document.isEmpty)

            let inside = host(items: ["old"], clipboard: .text("now\nclipboard"))
            command(inside)
            open(inside)
            #expect(inside.press(FakeHost.controlV))
            #expect(inside.panel?.rows.isEmpty == true)
            #expect(inside.composer.draft == "@improve now clipboard")
        }
    }

    @Test func offAndUnavailableMatchLegacyControlV() async throws {
        try await withInterfaceLanguage("en") {
            var offConfig = Config.default
            offConfig.clipboardHistory = false
            for inCommand in [false, true] {
                let legacy = host(clipboard: .text("last\ncopy"), withHistory: false)
                let off = host(items: ["older"], clipboard: .text("last\ncopy"), config: offConfig)
                let unavailable = host(items: ["older"], clipboard: .text("last\ncopy"), state: .unavailable)
                let worlds = [legacy, off, unavailable]
                if inCommand { worlds.forEach { command($0) } }
                let handled = worlds.map { $0.press(FakeHost.controlV) }
                #expect(handled[1] == handled[0] && handled[2] == handled[0])
                #expect(off.panel == legacy.panel && unavailable.panel == legacy.panel)
                #expect(off.composer.draft == legacy.composer.draft)
                #expect(unavailable.composer.draft == legacy.composer.draft)
            }
        }
    }

    @Test func deniedPermissionShowsCurrentTextAndHowToAllow() async throws {
        try await withInterfaceLanguage("en") {
            let h = host(clipboard: .text("current"), state: .notAllowed)
            open(h)
            #expect(h.panel?.rows.first?.text == "current")
            #expect(h.panel?.rows.last?.text.contains("allow Paste from Other Apps") == true)
            #expect(h.panel?.rows.last?.pickable == false)
            let last = (h.panel?.rows.count ?? 1) - 1
            h.send(.pick(last))
            #expect(h.permissionOpened == 1)

            let commandHost = host(clipboard: .text("current\ntext"), state: .notAllowed)
            command(commandHost)
            commandHost.press(FakeHost.controlV)
            #expect(commandHost.composer.draft == "@improve current text")
        }
    }

    @Test func secureInputAndEmptyClipboardNeverShowRows() async throws {
        try await withInterfaceLanguage("en") {
            let secure = host(items: ["secret"], clipboard: .text("secret"))
            secure.secure = true
            #expect(!secure.press(FakeHost.controlV))
            #expect(secure.panel == nil)
            let anywhere = host(items: ["private"], clipboard: .text("private"))
            anywhere.session.services.secureInputActive = { true }
            #expect(!anywhere.press(FakeHost.controlV))
            #expect(anywhere.panel == nil)
            let empty = host(clipboard: .none)
            empty.press(FakeHost.controlV)
            #expect(empty.panel == nil)
            #expect(empty.noticeAlone?.localizedCaseInsensitiveContains("clipboard") == true,
                    "notice: \(String(describing: empty.noticeAlone))")
        }
    }

    @Test func rowKeysUseChromiumSafeOutputsAndNeverChangeClipboard() async throws {
        try await withInterfaceLanguage("en") {
            let h = host(items: ["new", "old"], clipboard: .text("new"))
            h.app = "com.tinyspeck.slackmacgap"
            open(h)
            #expect(h.outputs.contains(.rowsTookKey))
            let beforeMove = h.outputs.count
            h.press(FakeHost.down)
            #expect(h.outputs.dropFirst(beforeMove).contains(.rowsTookKey))
            let beforeInsert = h.outputs.count
            h.press(FakeHost.enter)
            let inserted = Array(h.outputs.dropFirst(beforeInsert))
            #expect(inserted.contains(.rowByKey))
            #expect(inserted.contains(.commit("old")))
            #expect(h.document == "old")
            #expect(h.clipboard == .text("new"))
            #expect(!h.outputs.contains(where: { if case .copy = $0 { true } else { false } }))
        }
    }

    @Test func terminalMultilineInsertsAsOneCommit() async throws {
        try await withInterfaceLanguage("en") {
            let h = host(items: ["first\nsecond"], clipboard: .text("first\nsecond"), terminal: true)
            h.session.services.pastesInTerminal = { true }
            open(h)
            let before = h.outputs.count
            h.press(FakeHost.enter)
            let commits = h.outputs.dropFirst(before).compactMap { output -> String? in
                if case let .commit(text) = output { return text }
                return nil
            }
            #expect(commits == ["first\nsecond"])
            #expect(h.document == "first\nsecond")
        }
    }

    @Test func firstShowingFooterAppearsOnce() async throws {
        try await withInterfaceLanguage("en") {
            let h = host(items: ["one"], clipboard: .text("one"))
            h.firstClipboardPanel = true
            open(h)
            #expect(h.panel?.footer.contains("Kept on this Mac only") == true)
            #expect(h.panel?.footer.contains("Settings → General → Clipboard history") == true)
            h.press(FakeHost.escape)
            open(h)
            #expect(h.panel?.footer.contains("Kept on this Mac only") == false)
            #expect(h.panel?.footer.contains("⏎ inserts") == true)
        }
    }

    @Test func settingsAreLocalAndDefaultOn() throws {
        let oldConfig = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(oldConfig.clipboardHistoryOn)
        #expect(oldConfig.clipboardHistoryKept == 20)
        let localKeys = ["clipboardHistory", "clipboardHistoryLimit"]
        for key in localKeys {
            #expect(ICloudSync.neverSynced.contains(key))
            #expect(ICloudSync.category(of: key) == nil)
        }
        var config = oldConfig
        config.clipboardHistory = false
        config.clipboardHistoryLimit = 35
        let encoded = try JSONEncoder().encode(config)
        let restored = try JSONDecoder().decode(Config.self, from: encoded)
        #expect(!restored.clipboardHistoryOn && restored.clipboardHistoryKept == 35)
    }
}
