#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import CAllInOneIMEPanel
import Foundation
import Testing
import WinSDK

/// The candidate window draws the core's `PanelModel` as it is meant (input-session.md, "The Windows engine", step 4):
/// the input's prompt, text and caret (in UTF-16, where DirectWrite puts it), the header's lines, the hand-off's chips, a
/// list under its hint, the rows' icons (Segoe Fluent Icons, an emoji, an image), one @'s pinyin candidates on the side
/// nearest the caret, and a conversation no taller than its limit, scrolled to its last row. Drawn without a window
/// (`aio_panel_render_png`), as `--render-panel` draws the samples.
struct PanelDrawingTests {
    static func string(_ pointer: UnsafePointer<UInt16>?) -> String? {
        pointer.map { String(decodingCString: $0, as: UTF16.self) }
    }

    static func strings(_ pointer: UnsafePointer<UnsafePointer<UInt16>?>?, _ count: Int32) -> [String] {
        (0..<Int(count)).compactMap { string(pointer?[$0]) }
    }

    @Test func theIconsAreTheFontsGlyphs() {
        for builtin in IconToken.Builtin.allCases {
            let scalars = Array(PanelIcons.glyph(builtin).unicodeScalars)
            #expect(scalars.count == 1 && (0xE000...0xF8FF).contains(scalars[0].value), "\(builtin)")
        }
        #expect(PanelIcons.glyph(symbol: "heart.fill") == "\u{EB51}")
        #expect(PanelIcons.glyph(symbol: "gearshape.fill") == PanelIcons.glyph(.settings))
        #expect(PanelIcons.glyph(symbol: "no.such.symbol") == nil)
        // A symbol Windows hasn't: its fallback, on the square.
        let unknown = PanelIcons.flat(IconToken(.symbol("no.such.symbol", fallback: .prompt), color: .indigo))
        #expect(unknown == PanelIcons.Flat(kind: PanelIcons.glyphKind, text: PanelIcons.glyph(.prompt), fallback: PanelIcons.glyph(.prompt),
                                           color: 0x5856D6))
        let emoji = PanelIcons.flat(IconToken(.emoji("🍅", fallback: .scriptShow), color: .teal))
        #expect(emoji.kind == PanelIcons.emojiKind && emoji.text == "🍅" && emoji.fallback == PanelIcons.glyph(.scriptShow))
        let image = PanelIcons.flat(IconToken(.image(path: #"C:\icons\a.png"#, fallback: .scriptList), color: .teal))
        #expect(image.kind == PanelIcons.imageKind && image.text == #"C:\icons\a.png"#)
        // An app's, a folder's or a file's own icon: `@open`'s glyph, on its gray square, as before.
        let item = PanelIcons.flat(IconToken(.item(path: #"C:\Users\me\Documents"#, fallback: .open), color: .gray))
        #expect(item == PanelIcons.flat(IconToken.command(.open)), "\(item)")
        #expect(PanelIcons.rgb(.blue) == 0x007AFF && PanelIcons.rgb(.grayscale(0.25)) == 0x404040)
        #expect(PanelIcons.rgb(.rgb(red: 0x34, green: 0xC7, blue: 0x59)) == 0x34C759)
        // The C side's kinds.
        #expect((PanelIcons.glyphKind, PanelIcons.emojiKind, PanelIcons.imageKind)
                == (Int32(AIO_ICON_GLYPH), Int32(AIO_ICON_EMOJI), Int32(AIO_ICON_IMAGE)))
    }

    /// The core counts the caret in characters; DirectWrite in UTF-16 units: an emoji is two.
    @Test func theCaretInUTF16Units() {
        #expect(PanelModel.Input(text: "👋a你", caret: 1).utf16Caret == 2)
        #expect(PanelModel.Input(text: "👋a你", caret: 3).utf16Caret == 4)
        #expect(PanelModel.Input(text: "👋a你", caret: 9).utf16Caret == 4)
        #expect(PanelModel.Input(text: "abc", caret: nil).utf16Caret == nil)
    }

    /// What the window is given: the whole model, its structure as structure (no "▏" in the text, no lines joined).
    @Test func theFlatCopyCarriesTheWholeModel() {
        var model = PanelSamples.conversation(highlighted: nil)
        model.input = PanelModel.Input(prompt: "追问 › ", text: "👋好", caret: 1)
        model.header = ["选中的文字：Hello", "附件：截图 2 张"]
        model.status = .list("会附上：", items: ["版本", "日志"])
        model.candidates = "1 你好   2 拟好"
        model.rows[1].icon = IconToken(.question, color: .blue)
        CandidateWindow.withModel(model) { flat in
            let m = flat.pointee
            #expect(Self.string(m.candidates) == "1 你好   2 拟好")
            #expect(m.transcript == 1 && m.rowCount == Int32(model.rows.count) && m.highlighted == Int32(model.rows.count - 1))
            #expect(Self.string(m.inputPrompt) == "追问 › " && Self.string(m.inputText) == "👋好" && m.inputCaret == 2)
            #expect(Self.strings(m.headerLines, m.headerCount) == model.header)
            #expect(Self.string(m.handoffTitle) == "在 Claude 或其他 AI 中继续")
            #expect(Self.strings(m.handoffShortcuts, m.handoffCount) == ["Ctrl+1", "Ctrl+2", "Ctrl+3", "Ctrl+4", "Ctrl+5"])
            #expect(Self.strings(m.handoffNames, m.handoffCount).first == "Claude Code")
            #expect(m.statusKind == Int32(AIO_STATUS_LIST) && Self.string(m.status) == "会附上："
                    && Self.strings(m.statusItems, m.statusItemCount) == ["版本", "日志"])
            let icon = m.rows[1].icon
            #expect(icon.kind == Int32(AIO_ICON_GLYPH) && Self.string(icon.text) == PanelIcons.glyph(.question) && icon.color == 0x007AFF)
            #expect(m.rows[0].icon.kind == Int32(AIO_ICON_NONE) && m.rows[0].pickable == 0)
        }
        // An input with nothing typed yet is still there (its caret at its start); no input is none.
        var empty = PanelModel(input: PanelModel.Input(prompt: "question › ", text: "", caret: 0))
        CandidateWindow.withModel(empty) { #expect(Self.string($0.pointee.inputText) == "" && $0.pointee.inputCaret == 0) }
        empty.input = nil
        CandidateWindow.withModel(empty) { #expect($0.pointee.inputText == nil && $0.pointee.inputCaret == -1) }
        // No candidates' line: none (plain typing's candidates are the rows).
        CandidateWindow.withModel(PanelSamples.all()[0].model) { #expect($0.pointee.candidates == nil) }
    }

    func render(_ model: PanelModel, dpi: Int = 96, dark: Bool = false, maxHeight: Int = 0, above: Bool = false) throws -> AioPanelState {
        let folder = try temporaryFolder("panel-render")
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = folder.appendingPathComponent("panel.png")
        let state = try #require(CandidateWindow.renderPNG(model, dpi: dpi, dark: dark, maxHeight: maxHeight, above: above, to: png))
        let data = try Data(contentsOf: png)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]) && data.count > 300)
        return state
    }

    @Test func everySampleIsDrawn() throws {
        for sample in PanelSamples.all() {
            for (dpi, dark) in [(96, false), (144, true)] {
                let state = try render(sample.model, dpi: dpi, dark: dark, maxHeight: sample.maxHeight * dpi / 96, above: sample.above)
                #expect(state.width > 40 && state.height > 20 && state.dpi == Int32(dpi), "\(sample.name) at \(dpi)")
                #expect(state.above == (sample.above ? 1 : 0), "\(sample.name)")
            }
        }
    }

    /// The caret where DirectWrite puts its position in the input (after the prompt), none when the input is only shown.
    @Test func theInputsCaretIsAtItsPosition() throws {
        func caret(_ position: Int?) throws -> AioPanelState {
            try render(PanelModel(input: PanelModel.Input(prompt: "improve › ", text: "帮我改一下这句话", caret: position)))
        }
        let start = try caret(0), middle = try caret(6), end = try caret(8), none = try caret(nil)
        #expect(start.caretX > 40 && start.caretY >= 0)
        #expect(start.caretX < middle.caretX && middle.caretX < end.caretX)
        #expect(start.caretY == middle.caretY)
        #expect(none.caretX == -1)
        // At 1.5×, as far along in physical pixels.
        let scaled = try render(PanelModel(input: PanelModel.Input(prompt: "improve › ", text: "帮我改一下这句话", caret: 6)), dpi: 144)
        #expect(abs(Double(scaled.caretX) - Double(middle.caretX) * 1.5) < 6)
    }

    /// A conversation no taller than its limit, scrolled to show its last row, or the highlighted one when it is above;
    /// without a limit, all of it.
    @Test func aConversationIsNoTallerThanItsLimit() throws {
        let last = try render(PanelSamples.conversation(highlighted: nil), maxHeight: 400)
        #expect(last.height <= 400 && last.scrolled > 0)
        let above = try render(PanelSamples.conversation(highlighted: 1), maxHeight: 400)
        #expect(above.height <= 400 && above.scrolled < last.scrolled)
        let whole = try render(PanelSamples.conversation(highlighted: nil))
        #expect(whole.height > 400 && whole.scrolled == 0)
        // Other rows are never cut.
        let rows = PanelModel(rows: (1...30).map { PanelModel.Row(label: "\($0)", text: "row \($0)", kind: .candidate) })
        #expect(try render(rows, maxHeight: 200).height > 200)
    }

    /// One @'s candidates' line takes a line of its own, on the side nearest the caret: at the top below it, under the
    /// rows above it (the rows' places: `PanelCandidatesLineTests`); the panel is as big either way. A panel of it alone
    /// isn't empty.
    @Test func theCandidatesLineTakesItsRoomNearestTheCaret() throws {
        let composing = PanelSamples.oneAtPinyin
        var picked = composing
        picked.candidates = nil
        for dpi in [96, 144] {
            let below = try render(composing, dpi: dpi), above = try render(composing, dpi: dpi, above: true)
            let short = try render(picked, dpi: dpi)
            let line = below.height - short.height
            #expect(line > 0 && line < Int32(40 * dpi / 96), "\(below.height) / \(short.height)")
            #expect(above.width == below.width && above.height == below.height, "as big on either side: \(above.width)x\(above.height)")
            #expect(below.above == 0 && above.above == 1 && short.candidatesY == -1)
            // Below the caret the line at the top, under the padding; above it under the three rows, the footer under it.
            #expect(below.candidatesY >= 0 && below.candidatesY <= Int32((8 * Double(dpi) / 96).rounded(.up)), "\(below.candidatesY)")
            #expect(above.candidatesY > below.candidatesY + 3 * line && above.candidatesY + line < above.height, "\(above.candidatesY)")
        }
        #expect(try render(PanelModel(candidates: "1 你好   2 拟好")).height > 20)
    }

    /// A list's items each a line under its hint; the hand-off's chips wrap.
    @Test func listsAndChipsTakeTheirRoom() throws {
        let one = try render(PanelModel(status: .list("会附上：", items: ["版本"])))
        let three = try render(PanelModel(status: .list("会附上：", items: ["版本", "日志", "输入语言"])))
        #expect(three.height > one.height)
        func handoff(_ count: Int) -> PanelModel {
            PanelModel(handoff: PanelModel.Handoff(title: "Continue in", choices: (1...count).map { .init(shortcut: "Ctrl+\($0)", name: "Destination \($0)") }))
        }
        let few = try render(handoff(2)), many = try render(handoff(8))
        #expect(many.height > few.height)
        #expect(many.width <= Int32(616 + 12 + 1))
    }
}

extension OnTheDesktop {
    /// One @'s rows while pinyin is composed after the magic key, the candidates' line on the side nearest the caret:
    /// under the caret at the top, the rows under it; above the caret the rows at the top, the line under them, above the
    /// footer. As the line comes and goes the rows move by it only, all together: under the caret the window's top stays,
    /// above it its bottom stays at the caret. While typing on a line the window stays on its side, rather than flipping
    /// with each key. A click picks the row under it, never the line.
    @Suite(.serialized)
    struct PanelCandidatesLineTests {
        final class Clicks: @unchecked Sendable {
            private let lock = NSLock()
            private var rows: [Int] = []
            func add(_ row: Int) { lock.lock(); rows.append(row); lock.unlock() }
            func take() -> [Int] { lock.lock(); defer { rows = []; lock.unlock() }; return rows }
        }

        static var picked: PanelModel {
            var model = PanelSamples.oneAtPinyin
            model.candidates = nil
            return model
        }

        @Test func theCandidatesAreOnTheSideNearestTheCaret() throws {
            let window = try #require(CandidateWindow(), "no candidate window (no Direct2D here?)")
            let clicks = Clicks()
            let owner = PanelOwner(pid: nil, choose: { clicks.add($0) })
            let composing = PanelSamples.oneAtPinyin, picked = Self.picked
            let count = composing.rows.count
            let hwnd = try #require(window.window).assumingMemoryBound(to: HWND__.self)
            func rows() throws -> [[Int]] {
                _ = window.state
                return try (0..<count).map { let r = try #require(window.rowRect($0)); return [r.x, r.y, r.width, r.height] }
            }
            func click(x: Int, y: Int) -> [Int] {
                // Sent per-monitor aware: from a thread that isn't, Windows takes the point for logical pixels and scales it.
                _ = perMonitorAware { SendMessageW(hwnd, UINT(WM_LBUTTONUP), 0, LPARAM(Int32(y) << 16 | Int32(x))) }
                return clicks.take()
            }
            let work = workArea
            for above in [false, true] {
                let caret = above ? CaretRect(x: Int(work.left) + 300, y: Int(work.bottom) - 30, width: 2, height: 22)
                    : CaretRect(x: Int(work.left) + 200, y: Int(work.top) + 150, width: 2, height: 22)
                window.show(composing, owner: owner, caret: caret)
                let tall = window.state
                let shown = try rows()
                #expect(tall.visible == 1 && tall.rows == Int32(count) && tall.highlighted == 0)
                #expect(tall.above == (above ? 1 : 0))
                #expect(above ? Int(tall.y) + Int(tall.height) <= caret.y : Int(tall.y) >= caret.y + caret.height, "not over the caret")
                for index in 1..<count { #expect(shown[index][1] >= shown[index - 1][1] + shown[index - 1][3]) }
                let top = Int((8 * Double(tall.dpi) / 96).rounded(.up))
                if above {
                    // The rows first; the line under the last one, above the footer.
                    #expect(shown[0][1] <= top, "the rows at the top: \(shown[0])")
                    #expect(Int(tall.candidatesY) >= shown[count - 1][1] + shown[count - 1][3], "the line under the rows: \(tall.candidatesY)")
                } else {
                    // The line first, at the top; the rows under it.
                    #expect(tall.candidatesY >= 0 && Int(tall.candidatesY) <= top, "the line at the top: \(tall.candidatesY)")
                    #expect(shown[0][1] > Int(tall.candidatesY), "the rows under the line: \(shown[0])")
                }
                // Without the line: shorter by it, on the same side.
                window.show(picked, owner: owner, caret: caret)
                let short = window.state
                let line = Int(tall.height) - Int(short.height)
                #expect(line > 0 && line < Int(40 * tall.dpi / 96), "\(tall.height) / \(short.height)")
                #expect(short.above == tall.above && short.candidatesY == -1)
                let after = try rows()
                if above {
                    #expect(after == shown, "the rows where they were in the window")
                    #expect(Int(short.y) + Int(short.height) == Int(tall.y) + Int(tall.height), "its bottom stays at the caret")
                } else {
                    // Up by the line, all of them (a pixel either way: the line's height is a fraction of one).
                    for (moved, was) in zip(after, shown) {
                        #expect(moved[0] == was[0] && moved[2] == was[2] && abs(moved[3] - was[3]) <= 1 && abs(was[1] - moved[1] - line) <= 1,
                                "the rows up by the line: \(moved) / \(was)")
                    }
                    #expect(short.y == tall.y, "its top stays under the caret")
                }
                #expect(short.x == tall.x)
                // With it again: as it was; a click on each row picks it, one on the line picks nothing.
                window.show(composing, owner: owner, caret: caret)
                let again = window.state
                #expect(try rows() == shown && again.y == tall.y && again.height == tall.height && again.candidatesY == tall.candidatesY)
                for (index, row) in shown.enumerated() {
                    #expect(click(x: row[0] + row[2] / 2, y: row[1] + row[3] / 2) == [index])
                }
                #expect(click(x: shown[0][0] + shown[0][2] / 2, y: Int(tall.candidatesY) + line / 2 - 1).isEmpty)
            }
            window.hide(owner: owner)
        }

        /// A line with room under it for the window without the candidates' line, not with it: the line puts it above the
        /// caret, and while typing on that line it stays there, its bottom at the caret (pinyin picked, typed again, the
        /// caret moving along the line). Once it has hidden, where it goes is decided again.
        @Test func whileTypingOnALineItStaysOnItsSide() throws {
            let window = try #require(CandidateWindow(), "no candidate window (no Direct2D here?)")
            let owner = PanelOwner(pid: nil, choose: { _ in })
            let composing = PanelSamples.oneAtPinyin, picked = Self.picked
            let work = workArea
            let high = CaretRect(x: Int(work.left) + 200, y: Int(work.top) + 150, width: 2, height: 22)
            window.show(composing, owner: owner, caret: high)
            let tall = Int(window.state.height)
            window.show(picked, owner: owner, caret: high)
            let short = Int(window.state.height), dpi = Double(window.state.dpi)
            window.hide(owner: owner)
            #expect(tall > short)
            let gap = Int((4 * dpi / 96).rounded())
            // Room under it: halfway between the two heights.
            let caret = CaretRect(x: Int(work.left) + 300, y: Int(work.bottom) - gap - (tall + short) / 2 - 22, width: 2, height: 22)
            window.show(picked, owner: owner, caret: caret)
            let first = window.state
            #expect(first.above == 0 && Int(first.y) >= caret.y + caret.height, "the rows alone fit under the line")
            window.show(composing, owner: owner, caret: caret)
            let up = window.state
            #expect(up.above == 1 && Int(up.y) + Int(up.height) <= caret.y, "with the candidates' line they don't: above")
            for (key, model) in [picked, composing, picked].enumerated() {
                window.show(model, owner: owner, caret: caret)
                let state = window.state
                #expect(state.above == 1 && Int(state.y) + Int(state.height) == Int(up.y) + Int(up.height), "key \(key + 1): still above")
            }
            window.move(owner: owner, caret: CaretRect(x: caret.x + 30, y: caret.y, width: 2, height: 22))
            #expect(window.state.above == 1, "the caret further along the line: still above")
            window.hide(owner: owner)
            window.show(picked, owner: owner, caret: caret)
            let again = window.state
            #expect(again.above == 0 && again.y == first.y, "decided again once hidden: below")
            window.hide(owner: owner)
        }
    }
}

extension OnTheDesktop {
    /// The window's own conversation: a row scrolled out of sight has no rectangle (a click can't pick it); the last one
    /// is there, and a click on it picks it.
    @Suite(.serialized)
    struct PanelConversationTests {
        @Test func aConversationsRowsOutOfSightAreNotClicked() throws {
            let window = try #require(CandidateWindow(), "no candidate window (no Direct2D here?)")
            final class Clicks: @unchecked Sendable {
                private let lock = NSLock()
                private var rows: [Int] = []
                func add(_ row: Int) { lock.lock(); rows.append(row); lock.unlock() }
                var all: [Int] { lock.lock(); defer { lock.unlock() }; return rows }
            }
            let clicks = Clicks()
            let owner = PanelOwner(pid: nil, choose: { clicks.add($0) })
            var model = PanelSamples.conversation(highlighted: nil)
            // Long enough to pass half of any monitor.
            model.rows += model.rows + model.rows + model.rows
            model.highlighted = model.rows.count - 1
            let work = workArea
            window.show(model, owner: owner, caret: CaretRect(x: Int(work.left) + 200, y: Int(work.top) + 100, width: 2, height: 22))
            let state = window.state
            #expect(state.visible == 1 && state.scrolled > 0)
            #expect(Int(state.height) <= Int(work.bottom - work.top) / 2 + 1)
            #expect(window.rowRect(0) == nil)
            let last = try #require(window.rowRect(model.rows.count - 1))
            let hwnd = try #require(window.window).assumingMemoryBound(to: HWND__.self)
            // Sent per-monitor aware: from a thread that isn't, Windows takes the point for logical pixels and scales it.
            _ = perMonitorAware {
                SendMessageW(hwnd, UINT(WM_LBUTTONUP), 0, LPARAM(Int32(last.y + last.height / 2) << 16 | Int32(last.x + last.width / 2)))
            }
            #expect(clicks.all == [model.rows.count - 1])
            window.hide(owner: owner)
        }
    }
}
#endif
