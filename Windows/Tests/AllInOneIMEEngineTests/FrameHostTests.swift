#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing
import WinSDK

/// ApplicationFrameHost's frame, which a UWP app's window is put in, and inside which an untrusted client's window may be
/// in front (`Foreground.isInFront`): told by its process, System32's ApplicationFrameHost.exe, never by its class.
struct FrameHostTests {
    /// ApplicationFrameHost's frames in this session (`ApplicationFrameWindow`), each with the UWP app's window inside it
    /// (`Windows.UI.Core.CoreWindow`), if it has one, and that window's process.
    static func frames() -> [(frame: HWND, pid: DWORD?)] {
        final class Found { var frames: [(frame: HWND, pid: DWORD?)] = [] }
        let found = Found()
        "ApplicationFrameWindow".withCString(encodedAs: UTF16.self) { frameClass in
            "Windows.UI.Core.CoreWindow".withCString(encodedAs: UTF16.self) { coreClass in
                var after: HWND?
                while let frame = FindWindowExW(nil, after, frameClass, nil) {
                    after = frame
                    var pid: DWORD = 0
                    let core = FindWindowExW(frame, nil, coreClass, nil)
                    if let core { GetWindowThreadProcessId(core, &pid) }
                    found.frames.append((frame, pid == 0 ? nil : pid))
                }
            }
        }
        return found.frames
    }

    /// Whether ApplicationFrameHost has a frame here: a desktop session where a UWP app was opened (not SSH's).
    static var framesHere: Bool { !frames().isEmpty }

    @Test func aWindowOfTheFramesClassIsntApplicationFrameHosts() throws {
        let fake = try TestWindow(className: "ApplicationFrameWindow")
        #expect(!Foreground.isFrameHostWindow(fake.hwnd))
        #expect(!Foreground.isFrameHostWindow(nil))
        #expect(!Foreground.isFrameHostWindow(GetDesktopWindow()))
    }

    @Test(.enabled(if: framesHere, "ApplicationFrameHost has no frame in this session (SSH's, or no UWP app opened since logon)"))
    func applicationFrameHostsFramesAreAndTheAppsInsideAreInFront() throws {
        for (frame, pid) in Self.frames() {
            #expect(Foreground.isFrameHostWindow(frame))
            // The UWP app whose window is in it (in an AppContainer: an untrusted client) is in front when its frame is.
            if let pid { #expect(Foreground.isInFront(pid, foreground: frame, trusted: false)) }
        }
    }
}
#endif
