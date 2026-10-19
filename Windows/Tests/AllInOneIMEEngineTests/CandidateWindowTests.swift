#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing
import WinSDK

/// The candidate window itself (M6): a layered, no-activate, topmost tool window that never takes the focus, placed
/// under the caret on its monitor at that monitor's DPI, drawing the rows, the highlight and the footer, a click on a
/// row going back to its owner.
@Suite(.serialized)
struct CandidateWindowTests {
    static let model = PanelModel(
        rows: [PanelModel.Row(label: "1", text: "你好"), PanelModel.Row(label: "2", text: "拟好👋"),
               PanelModel.Row(label: "3", text: "你号", comment: "comment")],
        highlighted: 0, footer: "空格 选词 · 数字 选择", detail: "第 1 页")

    /// A caret near the top left of the primary monitor's work area.
    static var caret: CaretRect {
        var work = RECT()
        SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &work, 0)
        return CaretRect(x: Int(work.left) + 200, y: Int(work.top) + 150, width: 2, height: 22)
    }

    final class Clicks: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [Int] = []
        func add(_ row: Int) { lock.lock(); rows.append(row); lock.unlock() }
        var all: [Int] { lock.lock(); defer { lock.unlock() }; return rows }
    }

    func window() throws -> CandidateWindow {
        try #require(CandidateWindow(), "no candidate window (no Direct2D here?)")
    }

    @Test func itShowsTheRowsUnderTheCaretWithoutTakingTheFocus() throws {
        let window = try window()
        let clicks = Clicks()
        let owner = PanelOwner(pid: GetCurrentProcessId(), choose: { clicks.add($0) })
        let foregroundBefore = GetForegroundWindow()
        window.show(Self.model, owner: owner, caret: Self.caret)
        let state = window.state
        #expect(state.visible == 1)
        #expect(state.rows == 3)
        #expect(state.highlighted == 0)
        #expect(state.draws >= 1)
        #expect(state.width > 100 && state.height > 60)
        // Below the caret's line, on its monitor.
        #expect(Int(state.y) >= Self.caret.y + Self.caret.height)
        #expect(Int(state.dpi) >= 96)
        let hwnd = try #require(window.window).assumingMemoryBound(to: HWND__.self)
        let style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
        for flag in [WS_EX_LAYERED, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST] {
            #expect(style & LONG_PTR(flag) != 0)
        }
        // Shown (WS_VISIBLE: `IsWindowVisible` also asks whether the desktop is, which an SSH session's isn't).
        #expect(GetWindowLongPtrW(hwnd, GWL_STYLE) & LONG_PTR(WS_VISIBLE) != 0)
        // Never activated: the foreground is where it was.
        #expect(GetForegroundWindow() == foregroundBefore)
        #expect(GetForegroundWindow() != hwnd)
        // A click on row 2 (its middle, in the window's pixels) is a pick of row 2 by the owner.
        let row = try #require(window.rowRect(1))
        let point = LPARAM(Int32(row.y + row.height / 2) << 16 | Int32(row.x + row.width / 2))
        // WM_MOUSEACTIVATE first, as a real click sends it: never activated.
        #expect(SendMessageW(hwnd, UINT(WM_MOUSEACTIVATE), 0, 0) == LRESULT(MA_NOACTIVATE))
        SendMessageW(hwnd, UINT(WM_LBUTTONUP), 0, point)
        #expect(clicks.all == [1])
        // Another session's hide leaves it up; its owner's takes it down.
        window.hide(owner: PanelOwner(pid: nil, choose: { _ in }))
        #expect(window.state.visible == 1)
        window.hide(owner: owner)
        #expect(window.state.visible == 0)
        #expect(GetWindowLongPtrW(hwnd, GWL_STYLE) & LONG_PTR(WS_VISIBLE) == 0)
    }

    @Test func itDrawsAPNGOfWhatItShows() throws {
        let window = try window()
        let folder = try temporaryFolder("panel-png")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = PanelOwner(pid: nil, choose: { _ in })
        var model = Self.model
        model.status = .hint("回车 → 英文润色")
        window.show(model, owner: owner, caret: Self.caret)
        #expect(window.state.visible == 1)
        let png = folder.appendingPathComponent("panel.png")
        #expect(window.savePNG(to: png))
        let data = try Data(contentsOf: png)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(data.count > 500)
        // For a look at it: ALLINONEIME_PANEL_PNG names a file to copy it to.
        if let keep = ProcessInfo.processInfo.environment["ALLINONEIME_PANEL_PNG"] {
            try? FileManager.default.removeItem(atPath: keep)
            try FileManager.default.copyItem(at: png, to: URL(fileURLWithPath: keep))
        }
        window.hide(owner: owner)
    }

    @Test func nearTheBottomItGoesAboveTheCaret() throws {
        let window = try window()
        var work = RECT()
        SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &work, 0)
        let caret = CaretRect(x: Int(work.left) + 300, y: Int(work.bottom) - 30, width: 2, height: 22)
        let owner = PanelOwner(pid: nil, choose: { _ in })
        window.show(Self.model, owner: owner, caret: caret)
        let state = window.state
        #expect(state.visible == 1)
        #expect(Int(state.y) + Int(state.height) <= caret.y)
        #expect(Int(state.y) >= Int(work.top))
        window.hide(owner: owner)
    }

    @Test func itFollowsTheCaretAndWaitsForItsFirstReport() throws {
        let window = try window()
        let owner = PanelOwner(pid: nil, choose: { _ in })
        // No caret yet (§6: up to 50 ms for the first report): not drawn until it comes, or the wait ends.
        window.show(Self.model, owner: owner, caret: nil)
        let first = window.state
        #expect(first.draws == 0 || first.visible == 1)
        window.move(owner: owner, caret: Self.caret)
        #expect(window.state.visible == 1)
        let at = window.state.x
        var moved = Self.caret
        moved.x += 120
        window.move(owner: owner, caret: moved)
        #expect(window.state.x == at + 120)
        window.hide(owner: owner)
    }

    @Test func aNoticeOnItsOwnGoesAfterAMoment() throws {
        let window = try window()
        window.noticeDuration = 300
        let owner = PanelOwner(pid: nil, choose: { _ in })
        window.notice("中", owner: owner, caret: Self.caret)
        let state = window.state
        #expect(state.visible == 1)
        #expect(state.notice == 1)
        #expect(state.rows == 0)
        Thread.sleep(forTimeInterval: 0.6)
        #expect(window.state.visible == 0)
    }

    @Test func aNoticeBesideThePanelLeavesItUp() throws {
        let window = try window()
        window.noticeDuration = 300
        let owner = PanelOwner(pid: nil, choose: { _ in })
        window.show(Self.model, owner: owner, caret: Self.caret)
        window.notice("已复制", owner: owner, caret: nil)
        #expect(window.state.notice == 1)
        #expect(window.state.rows == 3)
        Thread.sleep(forTimeInterval: 0.6)
        let state = window.state
        #expect(state.visible == 1)
        #expect(state.notice == 0)
        window.hide(owner: owner)
    }
}
#endif
