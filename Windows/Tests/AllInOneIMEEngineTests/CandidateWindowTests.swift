#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import CAllInOneIMEPanel
import Foundation
import Testing
import WinSDK

extension OnTheDesktop {
    /// The candidate window itself (M6): a layered, no-activate, topmost tool window that never takes the focus, placed
    /// under the caret on its monitor at that monitor's DPI, drawing the rows, the highlight and the footer, a click on
    /// a row going back to its owner.
    @Suite(.serialized)
    struct CandidateWindowTests {
        static let model = PanelModel(
            rows: [PanelModel.Row(label: "1", text: "你好", kind: .candidate),
                   PanelModel.Row(label: "2", text: "拟好👋", kind: .candidate),
                   PanelModel.Row(label: "3", text: "你号", comment: "comment", kind: .candidate)],
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
            // No process: drawn wherever the foreground is (the owner's process must own it otherwise, below).
            let owner = PanelOwner(pid: nil, choose: { clicks.add($0) })
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
            // Never activated: not its thread's active or focused window (as a window shown with SW_SHOW would be, in
            // any session), and the foreground, when there is one (a desktop session; under SSH there is none), is
            // where it was.
            var thread = GUITHREADINFO()
            thread.cbSize = DWORD(MemoryLayout<GUITHREADINFO>.size)
            #expect(GetGUIThreadInfo(GetWindowThreadProcessId(hwnd, nil), &thread))
            #expect(thread.hwndActive != hwnd && thread.hwndFocus != hwnd)
            #expect(GetActiveWindow() != hwnd)
            if foregroundBefore != nil { #expect(GetForegroundWindow() == foregroundBefore) }
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
            // No caret yet (§6: up to 50 ms for the first report): not drawn until it comes.
            window.show(Self.model, owner: owner, caret: nil)
            let first = window.state
            #expect(first.visible == 0 && first.draws == 0)
            window.move(owner: owner, caret: Self.caret)
            let drawn = window.state
            #expect(drawn.visible == 1 && drawn.draws == 1)
            #expect(Int(drawn.y) >= Self.caret.y + Self.caret.height)
            let at = window.state.x
            var moved = Self.caret
            moved.x += 120
            window.move(owner: owner, caret: moved)
            #expect(window.state.x == at + 120)
            window.hide(owner: owner)
        }

        /// No caret report within 50 ms (§6): drawn where the system says the caret is, or the foreground window, or the
        /// pointer (`FallbackCaret`).
        @Test func withNoReportItGoesWhereTheSystemSaysAfterAWait() throws {
            let window = try window()
            let owner = PanelOwner(pid: nil, choose: { _ in })
            window.show(Self.model, owner: owner, caret: nil)
            #expect(window.state.visible == 0)
            Thread.sleep(forTimeInterval: 0.3)
            let state = window.state
            #expect(state.visible == 1 && state.draws == 1 && state.rows == 3)
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

        /// §8: a session whose process doesn't own the foreground draws nothing, panel or notice (a background or
        /// sandboxed client can't put the engine's topmost window over another app), and takes nobody's panel down.
        @Test func aProcessWithoutTheForegroundDrawsNothing() throws {
            let window = try window()
            let background = GetCurrentProcessId()
            try #require(!Foreground.isOwned(by: background, trusted: true), "this test process has the foreground")
            let owner = PanelOwner(pid: background, choose: { _ in })
            window.show(Self.model, owner: owner, caret: Self.caret)
            var state = window.state
            #expect(state.visible == 0 && state.draws == 0)
            window.notice("中", owner: owner, caret: Self.caret)
            state = window.state
            #expect(state.visible == 0 && state.notice == 0 && state.draws == 0)
            // A panel up for a session in front stays up.
            let front = PanelOwner(pid: nil, choose: { _ in })
            window.show(Self.model, owner: front, caret: Self.caret)
            #expect(window.state.visible == 1)
            window.show(Self.model, owner: owner, caret: Self.caret)
            window.notice("中", owner: owner, caret: Self.caret)
            state = window.state
            #expect(state.visible == 1 && state.rows == 3 && state.notice == 0)
            window.hide(owner: front)
        }

        /// Another session's notice doesn't take over the panel up for the session being typed in.
        @Test func anotherSessionsNoticeLeavesThePanelAlone() throws {
            let window = try window()
            let owner = PanelOwner(pid: nil, choose: { _ in })
            let other = PanelOwner(pid: nil, choose: { _ in })
            window.show(Self.model, owner: owner, caret: Self.caret)
            let before = window.state
            window.notice("Saved to Notes", owner: other, caret: CaretRect(x: 0, y: 0, width: 1, height: 1))
            let after = window.state
            #expect(after.visible == 1 && after.owner == before.owner && after.rows == 3 && after.notice == 0)
            #expect(after.x == before.x && after.y == before.y)
            window.hide(owner: owner)
        }

        /// The scale of the monitor at (200, 150), where `aSystemCaretIsMappedFromTheAppsPixels` puts its window.
        static var scaleAtTheTestWindow: Double {
            var x: UINT = 96, y: UINT = 96
            // Its real DPI: a thread that isn't per-monitor aware is told 96.
            let previous = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
            defer { SetThreadDpiAwarenessContext(previous) }
            let monitor = MonitorFromPoint(POINT(x: 200, y: 150), DWORD(MONITOR_DEFAULTTONEAREST))
            guard GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &x, &y) == S_OK else { return 1 }
            return Double(x) / 96
        }

        /// A system caret, where the panel goes when the DLL reports none: in an app that isn't per-monitor aware its
        /// rectangle is in the app's logical pixels, mapped here to physical ones (on a monitor at 150%, 1.5 times as far
        /// from the window's corner). At 100% (an SSH session's desktop) the two are the same, so the old mapping passed
        /// too: run it in a desktop session on a scaled monitor (`tip/test/run-in-session.sh`).
        @Test(.enabled(if: scaleAtTheTestWindow != 1, "the monitor is at 100%, where logical and physical pixels are the same"))
        func aSystemCaretIsMappedFromTheAppsPixels() throws {
            // A window of an app that isn't DPI aware: made by this thread while it isn't.
            let previous = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_UNAWARE)
            let made = "STATIC".withCString(encodedAs: UTF16.self) {
                CreateWindowExW(0, $0, nil, DWORD(WS_POPUP), 200, 150, 400, 300, nil, nil, GetModuleHandleW(nil), nil)
            }
            SetThreadDpiAwarenessContext(previous)
            let window = try #require(made)
            defer { DestroyWindow(window) }
            #expect(AreDpiAwarenessContextsEqual(GetWindowDpiAwarenessContext(window), DPI_AWARENESS_CONTEXT_UNAWARE))
            // Its rectangle in physical pixels, as a per-monitor aware thread sees it, and the scale of its monitor.
            let aware = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
            var physical = RECT()
            GetWindowRect(window, &physical)
            SetThreadDpiAwarenessContext(aware)
            let scale = Double(physical.right - physical.left) / 400
            try #require(scale != 1, "the window is on a monitor at 100%: nothing to tell the two mappings apart")
            var caret = AioCaret()
            #expect(aio_client_rect_on_screen(UnsafeMutableRawPointer(window), 10, 20, 12, 44, &caret) != 0)
            #expect(abs(Int(caret.x) - (Int(physical.left) + Int((10 * scale).rounded()))) <= 1)
            #expect(abs(Int(caret.y) - (Int(physical.top) + Int((20 * scale).rounded()))) <= 1)
            #expect(abs(Int(caret.height) - Int((24 * scale).rounded())) <= 1)
        }

        /// Where a caret report may put the panel (`Foreground.caretBounds`): inside the window it names, if that is the
        /// client's process's; never another process's window, nor a window that isn't there.
        @Test func aCaretsBoundsAreTheClientsOwnWindow() throws {
            let window = try #require("STATIC".withCString(encodedAs: UTF16.self) {
                CreateWindowExW(0, $0, nil, DWORD(WS_POPUP), 120, 130, 300, 200, nil, nil, GetModuleHandleW(nil), nil)
            })
            defer { DestroyWindow(window) }
            let hwnd = UInt64(UInt(bitPattern: window))
            let pid = GetCurrentProcessId()
            var rect = RECT()
            GetWindowRect(window, &rect)
            let bounds = try #require(Foreground.caretBounds(hwnd: hwnd, pid: pid, trusted: true))
            #expect(bounds == CaretRect(x: Int(rect.left), y: Int(rect.top), width: Int(rect.right - rect.left),
                                        height: Int(rect.bottom - rect.top)))
            #expect(bounds.width == 300 && bounds.height == 200)
            // Another process's window, a window that isn't there, another process for this window.
            let desktop = UInt64(UInt(bitPattern: GetDesktopWindow()))
            #expect(Foreground.caretBounds(hwnd: desktop, pid: pid, trusted: true) == nil)
            #expect(Foreground.caretBounds(hwnd: 0x7FFF_FFF0, pid: pid, trusted: true) == nil)
            #expect(Foreground.caretBounds(hwnd: hwnd, pid: pid + 4, trusted: true) == nil)
            #expect(Foreground.caretBounds(hwnd: hwnd, pid: nil, trusted: true) == nil)
            // No window: the foreground window's, if the client owns it (this test process doesn't).
            if !Foreground.isOwned(by: pid, trusted: true) { #expect(Foreground.caretBounds(hwnd: nil, pid: pid, trusted: true) == nil) }
        }
    }
}
#endif
