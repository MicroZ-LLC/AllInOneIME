#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing
import WinSDK

/// ApplicationFrameHost's frame, which a UWP app's window is put in, and inside which an untrusted client's window may be
/// in front (`Foreground.isInFront`): told by its process, System32's ApplicationFrameHost.exe, never by its class.
struct FrameHostTests {
    /// The top-level windows of the frame's class (`ApplicationFrameWindow`) in this session: ApplicationFrameHost's, and
    /// others' (Windows 11's shell, explorer.exe, has some), each with its process's program and the window inside it of
    /// a UWP app (`Windows.UI.Core.CoreWindow`) and its process, if there is one.
    static func frames() -> [(frame: HWND, program: String, app: DWORD?)] {
        final class Found { var frames: [(frame: HWND, program: String, app: DWORD?)] = [] }
        let found = Found()
        "ApplicationFrameWindow".withCString(encodedAs: UTF16.self) { frameClass in
            "Windows.UI.Core.CoreWindow".withCString(encodedAs: UTF16.self) { coreClass in
                var after: HWND?
                while let frame = FindWindowExW(nil, after, frameClass, nil) {
                    after = frame
                    var owner: DWORD = 0, app: DWORD = 0
                    GetWindowThreadProcessId(frame, &owner)
                    if let core = FindWindowExW(frame, nil, coreClass, nil) { GetWindowThreadProcessId(core, &app) }
                    found.frames.append((frame, program(of: owner), app == 0 ? nil : app))
                }
            }
        }
        return found.frames
    }

    /// Process `pid`'s program's file name, lowercased ("" when it can't be read).
    static func program(of pid: DWORD) -> String {
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else { return "" }
        defer { CloseHandle(process) }
        var path = [WCHAR](repeating: 0, count: 1024)
        var size = DWORD(path.count)
        guard QueryFullProcessImageNameW(process, 0, &path, &size) else { return "" }
        return String(decoding: path[..<Int(size)], as: UTF16.self).split(separator: "\\").last.map { $0.lowercased() } ?? ""
    }

    static var frameHosts: [(frame: HWND, program: String, app: DWORD?)] {
        frames().filter { $0.program == "applicationframehost.exe" }
    }

    /// Whether ApplicationFrameHost has a frame here: a desktop session with a UWP app open (not SSH's).
    static var frameHostsHere: Bool { !frameHosts.isEmpty }

    @Test func aWindowOfTheFramesClassThatIsntApplicationFrameHostsIsNoFrame() throws {
        let fake = try TestWindow(className: "ApplicationFrameWindow")
        #expect(!Foreground.isFrameHostWindow(fake.hwnd))
        #expect(!Foreground.isFrameHostWindow(nil))
        #expect(!Foreground.isFrameHostWindow(GetDesktopWindow()))
        // Others' of that class in this session (explorer.exe's, in a desktop session) neither.
        for (frame, program, _) in Self.frames() where program != "applicationframehost.exe" {
            #expect(!Foreground.isFrameHostWindow(frame), "\(program)")
        }
    }

    @Test(.enabled(if: frameHostsHere, "ApplicationFrameHost has no frame in this session (SSH's, or no UWP app open)"))
    func applicationFrameHostsFramesAreAndTheAppsInsideAreInFront() throws {
        for (frame, _, app) in Self.frameHosts {
            #expect(Foreground.isFrameHostWindow(frame))
            // The UWP app whose window is in it (in an AppContainer: an untrusted client) is in front when its frame is.
            if let app { #expect(Foreground.isInFront(app, foreground: frame, trusted: false)) }
        }
    }
}
#endif
