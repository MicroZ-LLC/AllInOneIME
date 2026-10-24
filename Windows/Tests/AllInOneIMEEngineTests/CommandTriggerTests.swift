#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import AllInOneIMEWire
import Foundation
import Testing

/// The command trigger the settings name (`Config.commandTrigger`, 0.6.7) in the Windows engine: the core's Composer
/// takes it from the settings file as it does on the Mac, as the DLL sends its key (what it types, Shift and all).
@Suite(.serialized)
struct CommandTriggerTests {
    /// Each of `text`'s characters as a US layout types it, the trigger tried here ("~") with its own key; the last
    /// one's outputs.
    @discardableResult
    static func type(_ client: EngineClient, _ text: String) -> [Output] {
        var last: [Output] = []
        for c in text {
            switch c {
            case "~": last = client.press(vk: 0xC0, scan: 0x29, text: "~", modifiers: [.shift, .leftShift])
            default: last = client.type(String(c))
            }
        }
        return last
    }

    @Test func anotherSymbolStartsACommandAndAtIsText() throws {
        let folder = try temporaryFolder("trigger")
        defer { try? FileManager.default.removeItem(at: folder) }
        let client = EngineClient(settings: try settingsFile(#"{"commandTrigger": "~", "inputLanguages": ["en"]}"#, in: folder),
                                  rime: nil)
        #expect(client.host.settings.current.commandTrigger == "~")
        Self.type(client, "~impro")
        let palette = try #require(client.panel.model)
        #expect(palette.rows.first?.text == "~improve")
        let outputs = Self.type(client, "ve hello")
        #expect(client.composer.draftCommand == .improve)
        // Shown without its trigger, as "@improve" is; as typed, with it, for the DLL to keep if it ends the composition.
        #expect(client.composition == "improve › hello")
        guard case let .composition(_, _, _, typed)? = outputs.first(where: { $0.op == "composition" }) else {
            Issue.record("no composition: \(outputs)")
            return
        }
        #expect(typed == "~improve hello")
        _ = client.escape()
        #expect(!client.composer.isComposing)
        // "@" is a symbol like any other now: it goes in, no command list.
        let committed = client.committed
        client.type("@")
        #expect(client.composer.draft.isEmpty)
        #expect(client.panel.model == nil)
        #expect(client.composition.isEmpty && client.committed == committed)
    }

    /// In Chinese the Composer takes the trigger before librime, which would type it as itself and "impro" as pinyin.
    /// ("/", rime-ice's key for its symbols, can't be the trigger since `Config.typingSymbols`: read as "@".)
    @Test func theTriggerComesBeforeLibrime() throws {
        let folder = try temporaryFolder("trigger-pinyin")
        defer { try? FileManager.default.removeItem(at: folder) }
        let rime = try RimeFixture.rime.get()
        let client = EngineClient(settings: try settingsFile(#"{"commandTrigger": "~", "inputLanguages": ["zh", "en"], "defaultInput": "zh"}"#,
                                                             in: folder), rime: rime)
        #expect(client.composer.inputLanguage == .chinese)
        Self.type(client, "~impro")
        let palette = try #require(client.panel.model)
        #expect(palette.rows.first?.text == "~improve")
        #expect(palette.rows.first?.label == "1")
        // The footer of pinyin's candidates names it too.
        _ = client.escape()
        client.type("ni")
        #expect(client.panel.model?.footer.contains("~") == true, "\(client.panel.model?.footer ?? "")")
    }

    /// Changed in the settings (the file, as the Settings app writes it): as every setting, from the field's next focus
    /// (back from the Settings window).
    @Test func aChangedTriggerAppliesAtTheNextFocus() throws {
        let folder = try temporaryFolder("trigger-change")
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = try settingsFile(#"{"inputLanguages": ["en"]}"#, in: folder)
        let client = EngineClient(settings: settings, rime: nil)
        client.type("@impro")
        #expect(client.panel.model?.rows.first?.text == "@improve")
        _ = client.escape()
        #expect(!client.composer.isComposing)
        try Data(#"{"inputLanguages": ["en"], "commandTrigger": "~"}"#.utf8).write(to: settings.url)
        // A new modification date (some file systems keep it to the second).
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: settings.url.path)
        client.send(.blur(sid: 1))
        client.send(.focus(sid: 1, focus: 2, field: nil))
        Self.type(client, "~impro")
        #expect(client.panel.model?.rows.first?.text == "~improve")
        _ = client.escape()
        client.type("@")
        #expect(client.composer.draft.isEmpty && client.panel.model == nil)
    }
}

extension WithKeys {
    /// `~improve ~translate hello`, Return, the versions from the stub provider on localhost, "1": as `@improve
    /// @translate` does, one request without the commands, as long as with "@".
    @Suite(.serialized)
    struct CommandTriggerAITests {
        @Test func anotherTriggersCommandGoesToTheProviderAsAtsDoes() throws {
            _ = memoryKeychain
            let folder = try temporaryFolder("trigger-ai")
            defer { try? FileManager.default.removeItem(at: folder) }
            let stub = try StubProvider(folder: folder)
            try APIKeys.save("stub-key", for: .anthropic, host: "127.0.0.1")
            func improve(_ trigger: String?) throws -> EngineClient {
                let sub = folder.appendingPathComponent(trigger ?? "default")
                try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
                let settings = try settingsFile("""
                    {"provider": "anthropic", "anthropic": {"baseURL": "\(stub.baseURL)", "model": "stub-model"},
                     "outputLanguages": ["en"], "outputLanguage": "en", "inputLanguages": ["en"], "rewriteStyles": [],
                     "timeoutSeconds": 10\(trigger.map { #", "commandTrigger": "\#($0)""# } ?? "")}
                    """, in: sub)
                let client = EngineClient(settings: settings, rime: nil)
                // Both writing commands: the second, inside the text, is taken out of it by its trigger (`WritingMode`).
                let t = trigger ?? "@"
                CommandTriggerTests.type(client, t + "improve " + t + "translate hello")
                _ = client.enter()
                #expect(client.wait { client.composer.phase == .choosing }, "\(stub.logText)")
                client.type("1")
                #expect(client.committed == "Hello there.")
                return client
            }
            _ = try improve("~")
            _ = try improve(nil)
            let requests = stub.requests
            #expect(requests.count == 2, "\(stub.logText)")
            #expect(requests.count == 2 && requests[0]["lastMessageLength"] as? Int == requests[1]["lastMessageLength"] as? Int,
                    "\(stub.logText)")
        }
    }
}
#endif
