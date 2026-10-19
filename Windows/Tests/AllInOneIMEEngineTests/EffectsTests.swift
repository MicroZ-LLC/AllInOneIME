#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import AllInOneIMEWire
import Foundation
import Testing

/// What the engine does for the Composer's other effects on Windows: the clipboard, opening, terminals, programs
/// through the Windows process launcher, `@js` in QuickJS in a child process of the engine, `@note` to a folder; what
/// only macOS has (Apple Notes, Reminders, Messages) says it isn't on Windows yet.
@Suite(.serialized)
struct EffectsTests {
    static let english = #"{"inputLanguages": ["en"], "outputLanguages": ["en"], "outputLanguage": "en"}"#

    func client(_ json: String = english, executable: String? = nil) throws -> (EngineClient, URL) {
        let folder = try temporaryFolder("effects")
        return (EngineClient(settings: try settingsFile(json, in: folder), rime: nil, executable: executable), folder)
    }

    @Test func copyAndOpenAndTerminals() throws {
        let (client, folder) = try client()
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try #require(client.host.liveSessions.first)
        client.host.perform(.copy("copied text"), in: session)
        #expect(client.wait { client.system.clipboard == "copied text" })
        client.host.perform(.open(path: #"C:\Users\Public"#), in: session)
        client.host.perform(.open(path: "https://example.com/"), in: session)
        client.host.perform(.openLink(URL(string: "https://example.com/search?q=a%20b")!), in: session)
        #expect(client.wait { client.system.opened.count == 3 })
        #expect(client.system.opened == [#"C:\Users\Public"#, "https://example.com/", "https://example.com/search?q=a%20b"])
        client.host.perform(.launchInTerminal(argv: ["git", "status"]), in: session)
        client.host.perform(.runInTerminal(prompt: "fix the bug"), in: session)
        client.host.perform(.continueInClaudeCode(prompt: "-the conversation"), in: session)
        #expect(client.wait { client.system.launched.count == 3 })
        // All of it on the engine's system thread, none on the session's queue.
        #expect(client.system.threads == [testSystemThread.threadId])
        let launched = client.system.launched
        #expect(launched.map(\.argv) == [["git", "status"], ["claude", "--"], ["claude", "--"]])
        // The prompt is the agent's first message, after "--": never read as an option.
        #expect(launched.map(\.prompt) == [nil, "fix the bug", "-the conversation"])
    }

    @Test func pasteReadsTheClipboardIntoTheDraft() throws {
        let (client, folder) = try client()
        defer { try? FileManager.default.removeItem(at: folder) }
        client.system.clipboard = "from the clipboard"
        client.type("@improve ")
        // Ctrl+V: the primary modifier on Windows (`ModifierRoles.windows`).
        // (The DLL's `textIgnoringModifiers` is the key's text with Ctrl and Alt cleared: "v".)
        client.press(vk: 0x56, scan: 0x2F, text: "\u{16}", ignoringModifiers: "v", modifiers: [.control, .leftControl])
        #expect(client.wait { client.composer.draft.contains("from the clipboard") })
    }

    @Test func appleOnlyCommandsSaySoAndNoteTextIsKept() throws {
        let (client, folder) = try client()
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try #require(client.host.liveSessions.first)
        // Apple Notes, the Mac's default destination: the text goes on the clipboard, so it isn't lost.
        client.host.perform(.saveNote(text: "a note to keep"), in: session)
        #expect(client.wait { client.system.clipboard == "a note to keep" })
        #expect(client.wait { !client.panel.notices.isEmpty })
        client.host.perform(.sendMessage(Recipient(name: "", handle: "+1 555 0100"), text: "hi", command: .imessage), in: session)
        #expect(client.panel.notices.last == client.host.notOnWindows)
        // @reminder: its preview fails with the reason, in the panel.
        client.type("@reminder call mom tomorrow")
        client.enter()
        #expect(client.wait {
            if case .failed = client.composer.phase { return true }
            return false
        })
        #expect(client.panel.model?.status == .error(client.host.notOnWindows))
    }

    @Test func noteToAFolderIsSavedThere() throws {
        let notes = try temporaryFolder("notes")
        defer { try? FileManager.default.removeItem(at: notes) }
        let json = #"{"inputLanguages": ["en"], "notes": {"destination": "folder", "folder": "\#(notes.path.replacingOccurrences(of: "\\", with: "/"))"}}"#
        let (client, folder) = try client(json)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try #require(client.host.liveSessions.first)
        client.host.perform(.saveNote(text: "Buy milk"), in: session)
        #expect(client.wait {
            ((try? FileManager.default.contentsOfDirectory(atPath: notes.path)) ?? []).contains { $0.hasSuffix(".md") }
        })
        let file = try #require(try FileManager.default.contentsOfDirectory(atPath: notes.path).first { $0.hasSuffix(".md") })
        #expect(try String(contentsOf: notes.appendingPathComponent(file), encoding: .utf8).contains("Buy milk"))
        #expect(client.wait { client.panel.notices.contains { $0.hasPrefix("Saved to") || $0.hasPrefix("已保存到") } })
    }

    /// `@js`: the code runs in QuickJS in a child process of the engine (`AllInOneIMEEngine --run-js`), started through
    /// the Windows process launcher; what it gives back is the answer, and 1 (or Return) puts it in.
    @Test func jsRunsInQuickJSInAChildProcessOfTheEngine() throws {
        let engine = packageRoot.appendingPathComponent(".build/debug/AllInOneIMEEngine.exe")
        try #require(FileManager.default.fileExists(atPath: engine.path), "build the engine first (swift build)")
        let (client, folder) = try client(executable: engine.path.replacingOccurrences(of: "/", with: "\\"))
        defer { try? FileManager.default.removeItem(at: folder) }
        client.type("@js 6*7")
        client.enter()
        #expect(client.wait(20) { client.composer.phase == .choosing })
        #expect(client.panel.model?.rows.contains { $0.text == "42" } == true)
        client.enter()
        #expect(client.committed == "42")
    }

    /// A custom `run` command: its program through the Windows process launcher (a job object), what it prints the
    /// answer.
    @Test func aCustomCommandRunsItsProgram() throws {
        let json = #"""
            {"inputLanguages": ["en"], "customCommands": [
              {"name": "shout", "type": "run", "argv": ["cmd.exe", "/d", "/c", "echo", "{input}!"], "ascii": true}]}
            """#
        let (client, folder) = try client(json)
        defer { try? FileManager.default.removeItem(at: folder) }
        client.type("@shout hello")
        client.enter()
        #expect(client.wait(20) { client.composer.phase == .choosing })
        client.enter()
        #expect(client.committed == "hello!")
    }

    @Test func settingsOpensTheFolderOfTheConfig() throws {
        let (client, folder) = try client()
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try #require(client.host.liveSessions.first)
        client.host.perform(.openSettings, in: session)
        #expect(client.wait { client.system.opened.count == 1 })
        #expect(client.panel.notices.last?.contains("config.json") == true)
    }

    @Test func atOpenFindsWhatWasTyped() throws {
        let (client, folder) = try client()
        defer { try? FileManager.default.removeItem(at: folder) }
        client.system.searchResults = [SearchResult(name: "Notepad", path: #"C:\Windows\notepad.exe"#)]
        client.type("@open notepad")
        client.enter()
        #expect(client.wait { client.composer.phase == .choosing })
        #expect(client.panel.model?.rows.first?.text == "Notepad")
        client.enter()
        #expect(client.wait { client.system.opened == [#"C:\Windows\notepad.exe"#] })
        #expect(client.committed == "")
    }

    /// A key's reply never waits on the system (§5.4): `@open`'s pick, Ctrl+C and Ctrl+V are answered while what they
    /// asked of the system (a share that is offline, a clipboard owner that doesn't answer) still hangs, and it goes on
    /// on the system's thread, its result coming back to the session afterwards.
    @Test(.timeLimit(.minutes(1))) func theKeysReplyNeverWaitsOnTheSystem() throws {
        let (client, folder) = try client()
        defer { try? FileManager.default.removeItem(at: folder) }
        let gate = DispatchSemaphore(value: 0)
        client.system.gate = gate
        client.system.searchResults = [SearchResult(name: "Share", path: #"\\offline\share"#)]
        client.type("@open share")
        client.enter()
        #expect(client.wait { client.composer.phase == .choosing })
        // The pick's key is answered at once, with the system still hanging.
        let answered = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            client.enter()
            answered.signal()
        }
        #expect(answered.wait(timeout: .now() + 5) == .success)
        #expect(client.system.opened.isEmpty)
        // Ctrl+V in a draft: answered too; the text comes in once the clipboard could be read.
        client.system.clipboard = "pasted"
        client.type("@improve ")
        let pasted = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            client.press(vk: 0x56, scan: 0x2F, text: "\u{16}", ignoringModifiers: "v", modifiers: [.control, .leftControl])
            pasted.signal()
        }
        #expect(pasted.wait(timeout: .now() + 5) == .success)
        #expect(!client.composer.draft.contains("pasted"))
        gate.signal()
        gate.signal()
        #expect(client.wait { client.system.opened == [#"\\offline\share"#] })
        #expect(client.wait { client.composer.draft.contains("pasted") })
        #expect(client.system.threads == [testSystemThread.threadId])
        client.system.gate = nil
    }

    @Test func fileSearchFindsAddressesAndPaths() {
        #expect(FileSearch.search("https://example.com").first?.path == "https://example.com")
        #expect(FileSearch.search("example.com").first?.path == "https://example.com")
        #expect(FileSearch.search(#"C:\Windows"#).first?.isFolder == true)
    }
}
#endif
