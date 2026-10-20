#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import AllInOneIMEWire
import Foundation
import Testing
import WinSDK

/// English words among pinyin's candidates in the engine, as on the Mac: the core's `EnglishWordsEngine` on each field's
/// librime session, with rime-ice's English dictionary from the rime-data librime runs on. The settings' words are
/// offered; letters put in as typed twice are learned into the settings file (`EnglishWords.learns`, the Mac's rule) and
/// offered at once; never where what is typed may be a password or goes to another computer.
@Suite(.serialized)
struct EnglishWordsEngineTests {
    static let chinese = #"{"inputLanguages": ["zh", "en"], "defaultInput": "zh"}"#
    static let notepad = WireField(app: "win:notepad.exe", process: "notepad.exe", scopes: [0], layout: "00000409")

    func client(_ json: String = chinese, field: WireField = notepad,
                configure: (inout EngineHost.Options) -> Void = { _ in }) throws -> (EngineClient, URL) {
        let folder = try temporaryFolder("english")
        let rime = try RimeFixture.rime.get()
        return (EngineClient(settings: try settingsFile(json, in: folder), rime: rime, field: field, configure: configure), folder)
    }

    /// The words the settings file has, once what was learned is written.
    func savedWords(_ client: EngineClient) -> [String] {
        client.host.flushLearnedWords()
        return (try? Config.load(from: client.host.settings.url))?.englishWords ?? []
    }

    /// `letters`, then Enter: the letters put in as typed.
    func putIn(_ letters: String, _ client: EngineClient) {
        client.type(letters)
        client.enter()
    }

    func shown(_ client: EngineClient) -> [String] { client.panel.model?.rows.map(\.text) ?? [] }

    @Test func theSettingsWordsAreAmongTheCandidates() throws {
        let (client, folder) = try client(#"{"inputLanguages": ["zh", "en"], "defaultInput": "zh", "englishWords": ["Frobnicate"]}"#)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(client.composer.engine is EnglishWordsEngine)
        client.type("frobn")
        let rows = shown(client)
        let place = try #require(rows.firstIndex(of: "Frobnicate"), "\(rows)")
        client.type(String(place + 1))
        #expect(client.committed == "Frobnicate")
        // The product words rime-ice lacks (`EnglishWords.curated`) too, first when all their letters are typed; pinyin
        // as before.
        client.type("bedrock")
        #expect(shown(client).first == "Bedrock", "\(shown(client))")
        client.space()
        client.type("nihao")
        client.space()
        #expect(client.committed == "FrobnicateBedrock你好")
    }

    @Test func lettersPutInAsTypedTwiceAreLearnedIntoTheSettingsFile() throws {
        let (client, folder) = try client()
        defer { try? FileManager.default.removeItem(at: folder) }
        putIn("frobnicate", client)
        #expect(client.committed == "frobnicate")
        #expect(savedWords(client).isEmpty)
        client.type("frobn")
        #expect(!shown(client).contains("frobnicate"), "the first time only remembered: \(shown(client))")
        client.escape()
        putIn("frobnicate", client)
        #expect(savedWords(client) == ["frobnicate"])
        client.type("frobn")
        // Offered at once: second, after librime's first candidate (its letters may go on as more than these), where the
        // end-to-end test picks it (2).
        #expect(shown(client).firstIndex(of: "frobnicate") == 1, "\(shown(client))")
        client.escape()
        // Pinyin, and what rime-ice has, aren't.
        for _ in 0..<2 {
            putIn("nihao", client)
            putIn("hello", client)
        }
        #expect(savedWords(client) == ["frobnicate"])
        #expect(client.committed == "frobnicatefrobnicatenihaohellonihaohello")
    }

    @Test func neverInAPasswordOrPrivateFieldATerminalOrARemoteDesktop() throws {
        let fields = [
            // A password's input scope, however the client said it (the DLL sends no keys from one), and a private
            // window's (IS_PRIVATE: a field an input method keeps nothing of).
            WireField(app: "win:notepad.exe", process: "notepad.exe", scopes: [31], layout: "00000409"),
            WireField(app: "win:msedge.exe", process: "msedge.exe", scopes: [61], layout: "00000409"),
            // Terminals, whose password prompts (sudo's, ssh's) are no password fields; PowerShell ISE's console.
            WireField(app: "win:windowsterminal.exe", process: "windowsterminal.exe", layout: "00000409"),
            WireField(app: "win:conhost.exe", process: "conhost.exe", layout: "00000409"),
            WireField(app: "win:powershell_ise.exe", process: "powershell_ise.exe", layout: "00000409"),
            // What is typed there goes to another computer: by the app, or by its program (Windows App's session).
            WireField(app: "win:mstsc.exe", process: "mstsc.exe", layout: "00000409"),
            WireField(app: "win:MicrosoftCorporationII.Windows365_8wekyb3d8bbwe!Windows365", process: "msrdc.exe", layout: "00000409"),
            WireField(app: "win:anydesk.exe", process: "anydesk.exe", layout: "00000409"),
        ]
        for field in fields {
            let (client, folder) = try client(field: field)
            defer { try? FileManager.default.removeItem(at: folder) }
            putIn("frobnicate", client)
            putIn("frobnicate", client)
            #expect(client.committed == "frobnicatefrobnicate" && savedWords(client).isEmpty, "\(field.app)")
        }
        // A terminal's window in another program (Visual Studio's terminal): the window typed in says so.
        let windows = Flag(false)
        let (client, folder) = try client(configure: { $0.terminalWindow = { _, _ in windows.value = true; return true } })
        defer { try? FileManager.default.removeItem(at: folder) }
        putIn("frobnicate", client)
        putIn("frobnicate", client)
        #expect(windows.value && savedWords(client).isEmpty)
    }

    @Test func notWithLearningOffNorInAnAppWithNoAI() throws {
        for json in [#"{"inputLanguages": ["zh", "en"], "defaultInput": "zh", "learnsEnglishWords": false}"#,
                     #"{"inputLanguages": ["zh", "en"], "defaultInput": "zh", "appProfiles": {"win:notepad.exe": {"noAI": true}}}"#] {
            let (client, folder) = try client(json)
            defer { try? FileManager.default.removeItem(at: folder) }
            putIn("frobnicate", client)
            putIn("frobnicate", client)
            #expect(client.committed == "frobnicatefrobnicate" && savedWords(client).isEmpty, "\(json)")
        }
    }

    @Test func learnedIntoAMissingSettingsFileWithWindowsOwnNewUser() throws {
        let folder = try temporaryFolder("english-fresh")
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = EngineSettings(url: folder.appendingPathComponent("config.json"))  // no file yet
        let client = EngineClient(settings: settings, rime: try RimeFixture.rime.get())
        client.tapShift()  // typing starts in English for a new user
        #expect(client.composer.inputLanguage == .chinese)
        putIn("frobnicate", client)
        putIn("frobnicate", client)
        #expect(savedWords(client) == ["frobnicate"])
        // Windows' new user (English, then Chinese: the pack comes with the installer), not the Mac's (English only).
        let saved = try Config.load(from: settings.url)
        #expect(saved.inputLanguages == [.english, .chinese])
    }

    @Test func visualStudiosTerminalIsATerminalsWindow() throws {
        // A window of the class Microsoft.Terminal.Wpf's terminal (Visual Studio's) has, and one inside it.
        let terminal = try TestWindow(className: "HwndTerminalClass")
        let inside = try TestWindow(className: "AllInOneIMETestChild", parent: terminal.hwnd)
        let other = try TestWindow(className: "AllInOneIMETestPlain")
        #expect(Foreground.isTerminalWindow(terminal.id))
        #expect(Foreground.isTerminalWindow(inside.id))
        #expect(!Foreground.isTerminalWindow(other.id))
    }
}

/// A window of its own class for a test, hidden, destroyed with it.
final class TestWindow {
    let hwnd: HWND
    var id: UInt64 { UInt64(UInt(bitPattern: hwnd)) }

    init(className: String, parent: HWND? = nil) throws {
        let instance = GetModuleHandleW(nil)
        let made: HWND? = className.withCString(encodedAs: UTF16.self) { name in
            var windowClass = WNDCLASSEXW()
            windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            windowClass.lpfnWndProc = { DefWindowProcW($0, $1, $2, $3) }
            windowClass.hInstance = instance
            windowClass.lpszClassName = name
            _ = RegisterClassExW(&windowClass)  // fails once registered: the class is there
            return CreateWindowExW(0, name, name, parent == nil ? DWORD(WS_OVERLAPPEDWINDOW) : DWORD(WS_CHILD), 0, 0, 100, 100, parent, nil,
                                   instance, nil)
        }
        guard let made else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "CreateWindowExW: \(GetLastError())"])
        }
        hwnd = made
    }

    deinit { DestroyWindow(hwnd) }
}
#endif
