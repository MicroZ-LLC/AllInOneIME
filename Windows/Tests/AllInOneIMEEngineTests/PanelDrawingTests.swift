#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import CAllInOneIMEPanel
import Foundation
import Testing
import WinSDK

/// The candidate window draws the core's `PanelModel` as it is meant (input-session.md, "The Windows engine", step 4):
/// the input's prompt, text and caret (in UTF-16, where DirectWrite puts it), the header's lines, the hand-off's chips, a
/// list under its hint, the rows' icons (Segoe Fluent Icons, an emoji, an image), and a conversation no taller than its
/// limit, scrolled to its last row. Drawn without a window (`aio_panel_render_png`), as `--render-panel` draws the
/// samples.
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
        model.rows[1].icon = IconToken(.question, color: .blue)
        CandidateWindow.withModel(model) { flat in
            let m = flat.pointee
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
    }

    func render(_ model: PanelModel, dpi: Int = 96, dark: Bool = false, maxHeight: Int = 0) throws -> AioPanelState {
        let folder = try temporaryFolder("panel-render")
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = folder.appendingPathComponent("panel.png")
        let state = try #require(CandidateWindow.renderPNG(model, dpi: dpi, dark: dark, maxHeight: maxHeight, to: png))
        let data = try Data(contentsOf: png)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]) && data.count > 300)
        return state
    }

    @Test func everySampleIsDrawn() throws {
        for sample in PanelSamples.all() {
            for (dpi, dark) in [(96, false), (144, true)] {
                let state = try render(sample.model, dpi: dpi, dark: dark, maxHeight: sample.maxHeight * dpi / 96)
                #expect(state.width > 40 && state.height > 20 && state.dpi == Int32(dpi), "\(sample.name) at \(dpi)")
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
