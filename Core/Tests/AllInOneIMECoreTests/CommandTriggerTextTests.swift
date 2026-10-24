import Foundation
import Testing
@testable import AllInOneIMECore

/// The interface's text names commands with the command trigger, not "@": the panel's and the notices' (`UIText`, as the
/// session sets it), the settings document's (as its config has it), and a snippet expanded inside a text. Each in a
/// scope of its own (`UIText.scopedCommandTrigger`): the process's trigger stays @ for the other tests.
@Suite(MemorySecrets())
struct CommandTriggerTextTests {
    func tilde<T>(_ body: () throws -> T) rethrows -> T {
        try UIText.$scopedCommandTrigger.withValue("~") { try UIText.$scopedLanguage.withValue("en", operation: body) }
    }

    @Test func thePanelAndTheNoticesNameCommandsWithIt() throws {
        tilde {
            #expect(UIText.summary(.translate) == "Translate into your languages; with ~improve, both")
            #expect(UIText.describe(ScriptCommand.Problem.nameTaken("improve", by: .builtIn), file: URL(fileURLWithPath: "/x"))
                == "~improve is a built-in command")
            #expect(UIText.describe(CommandPipelineError.inner("read", "timed out")) == "~read: timed out")
            #expect(CommandPipelineError.inner("stock", "no such symbol").errorDescription == "~stock: no such symbol")
            #expect(UIText.describe(WebSearch.SearchError.emptyQuery) == "Type what to search for after ~search")
            #expect(SessionText.shortName(.atAgent, picked: .claude, language: "en").hasPrefix("~agent's agent"))
            for key in [ActionKey.enter, .optionTap, .optionSpace, .space] {
                for terms in [PlatformTerms.mac, .windows] {
                    let note = UIText.actionKeyNote(key, terms: terms)
                    #expect(note.contains("~") && !note.contains("@"), "\(key): \(note)")
                }
            }
        }
        // As the session left it: @.
        #expect(UIText.summary(.translate).contains("@improve"))
    }

    /// What the user (or a plugin's author) gave goes in as it is: its own "@" (a custom agent's program, a version, an
    /// address) is no command's, and the trigger doesn't take its place.
    @Test func whatTheUserGaveKeepsItsOwnAt() {
        tilde {
            #expect(SessionText.shortName(.atAgent, picked: .custom, custom: ["/opt/tools/team@agent", "--run"], language: "en")
                == "~agent's agent (team@agent)")
            #expect(UIText.triggered("Install @\(UIText.verbatim("stock")) \(UIText.verbatim("1.0@beta"))?") == "Install ~stock 1.0@beta?")
        }
        // With @ itself the text is as it is, and nothing stands in for an argument's @ any more.
        let atAgent = SessionText.shortName(.atAgent, picked: .custom, custom: ["/opt/tools/team@agent"], language: "en")
        #expect(atAgent == "@agent's agent (team@agent)" && !atAgent.unicodeScalars.contains { $0.properties.isNoncharacterCodePoint })
    }

    @Test func aPluginsOutputIsLabelledWithIt() {
        let manifest = PluginManifest(name: "acmeweather", version: "1.0.0", type: .script, script: "main.js")
        let plugin = InstalledPlugin(manifest: manifest, directory: URL(fileURLWithPath: "/nowhere/acmeweather"), isLocal: true)
        let weather = Command(name: plugin.name, kind: .run, plugin: plugin)  // as the catalog makes it
        tilde { #expect(UIText.answerLabel(weather) == "~acmeweather") }
    }

    /// Every text of the settings document (both platforms') that names a command names it with the config's trigger.
    @Test(arguments: [SettingsPlatform.mac, .windows])
    func theSettingsDocumentNamesCommandsWithIt(_ platform: SettingsPlatform) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trigger-text-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"commandTrigger": "~", "uiLanguage": "en", "customCommands": [{"name": "py", "type": "run", "argv": ["python3"]}]}"#.utf8)
            .write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        let document = SettingsService(store: SettingsStore(configURL: url), platform: platform, library: library).document()
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document))
        var texts: [String] = []
        func collect(_ value: Any, key: String?) {
            switch value {
            case let object as [String: Any]:
                // Ids and values are the settings' own (and the trigger's placeholder, its default, is @).
                for (key, value) in object where !["id", "value", "placeholder"].contains(key) { collect(value, key: key) }
            case let array as [Any]: for value in array { collect(value, key: key) }
            case let text as String: texts.append(text)
            default: break
            }
        }
        collect(json, key: nil)
        // An address's @ isn't a command's, nor the trigger field's example of one.
        let named = texts.filter { $0.contains("@") && !$0.contains("git@") && !$0.contains("such as @ or ~") }
        #expect(named.isEmpty, "\(named)")
        #expect(texts.contains { $0.contains("~improve") } && texts.contains("~py"), "\(texts.filter { $0.contains("~") })")
    }

    @Test func aSnippetInsideATextIsFoundByIt() {
        let zoom = Command.catalog([CustomCommand(name: "zoom", type: .snippet, text: "https://zoom.us/j/1")]).filter { $0.kind == .snippet }
        let values = SnippetValues()
        #expect(SnippetTemplate.expandInner("会议链接 ~zoom 见", commands: zoom, values: values, trigger: "~") == "会议链接 https://zoom.us/j/1 见")
        #expect(SnippetTemplate.expandInner("会议链接 @zoom 见", commands: zoom, values: values, trigger: "~") == "会议链接 @zoom 见")
        #expect(SnippetTemplate.expandInner("会议链接 @zoom 见", commands: zoom, values: values) == "会议链接 https://zoom.us/j/1 见")
    }
}
