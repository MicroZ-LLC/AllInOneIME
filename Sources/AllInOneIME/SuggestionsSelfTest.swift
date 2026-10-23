import AllInOneIMECore
import AppKit

/// api.github.com as the GitHub plugin's (Core/Plugins/github) `fetch` reaches it, a stand-in: recorded issues of a
/// made-up repository (octo-org/octo-repo), the list and each issue by number; every request kept. Nothing leaves this
/// Mac.
final class GitHubStandIn: PluginFetcher, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [String] = []
    var requests: [String] { lock.withLock { asked } }

    static let repository = "octo-org/octo-repo"
    static let issues: [(number: Int, title: String, state: String)] = [
        (1234, "Fix login on the settings page", "open"), (1201, "Panel flickers on a second screen", "closed"),
        (12, "Candidate panel position", "open"), (7, "Docs: how to write a plugin", "open"),
    ]

    static func issue(_ number: Int, _ title: String, _ state: String) -> [String: Any] {
        ["number": number, "title": title, "state": state, "updated_at": "2026-10-20T08:00:00Z",
         "html_url": "https://github.com/\(repository)/issues/\(number)"]
    }

    func fetch(_ requests: [PluginRequest]) -> [PluginResponse] {
        lock.withLock { asked += requests.map(\.url) }
        return requests.map { request in
            let base = "https://api.github.com/repos/\(Self.repository)/issues"
            func json(_ value: Any) -> PluginResponse {
                PluginResponse(status: 200, text: String(decoding: (try? JSONSerialization.data(withJSONObject: value)) ?? Data(), as: UTF8.self))
            }
            if request.url.hasPrefix(base + "?") { return json(Self.issues.map { Self.issue($0.number, $0.title, $0.state) }) }
            if request.url.hasPrefix(base + "/"), let number = Int(request.url.dropFirst(base.count + 1)) {
                guard let found = Self.issues.first(where: { $0.number == number }) else { return PluginResponse(status: 404, text: "{}") }
                return json(Self.issue(found.number, found.title, found.state))
            }
            return PluginResponse(error: "not allowed: \(URL(string: request.url)?.host ?? request.url)")
        }
    }
}

extension SelfTest {
    /// Whether the session's chooser (a long press of Shift: Translate as You Type, coding mode) is the panel now.
    @MainActor
    static func chooserIsOpen(_ controller: AllInOneIMEInputController) -> Bool {
        let rows = controller.session.panelModel().rows
        return rows.count == 2 && rows[0].text == tr("边打边译", "Translate as You Type") && rows[1].text == tr("编码模式", "Coding mode")
    }

    /// Suggestions in a field of the self-test's own: nothing kept where the user's are (the lists' cache, the rows
    /// picked, the coding packs), no plugin of the user's run. Before the controller's session is made (it takes them).
    @MainActor
    static func isolateSuggestions(in directory: URL) {
        SuggestionsShared.store = SuggestionsStore()
        SuggestionsShared.cacheFolder = directory.appendingPathComponent("suggestions-cache", isDirectory: true)
        SuggestionsShared.packs = CodingPackStore(directory: directory.appendingPathComponent("coding-packs", isDirectory: true))
        SuggestionsShared.picks = SuggestionPicks(url: directory.appendingPathComponent("suggestion-picks.json"))
        SuggestionsShared.picks.clear()
        SuggestionsShared.runtime = PluginCompletionRuntime(mode: .inProcess(fetcher: { _ in GitHubStandIn() }))
        SuggestionsShared.codingMode = false
        CodingPackManager.shared.library = CodingPackLibrary(store: SuggestionsShared.packs)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("suggestions-cache"))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("coding-packs"))
    }

    /// Where the repository keeps what the app's source ships with (Core/), from this file's place in it: the self-test
    /// runs from a build of it.
    static var coreFolder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Core", isDirectory: true)
    }

    /// Suggestions v1 end to end, in the fake field with the candidate panel: the GitHub plugin (Core/Plugins/github)
    /// installed in the self-test's folder and its issues enabled, its script run here with a stand-in for
    /// api.github.com (`GitHubStandIn`). "#12" shows its rows (the list's, then the live query, asked once 2 characters
    /// follow "#"), Tab inserts what wasn't typed of the first; in Slack (a chat app) Tab inserts the issue's address
    /// too. The child process a completion script runs in (`--run-plugin … --completion load`). Coding mode's rows from
    /// the Python pack (Core/CodingPacks), a snippet's caret. Everything left as it was found.
    static func testSuggestions(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("Suggestions: the GitHub plugin's issues and coding mode (a stand-in for api.github.com)", needs: .composing)
        let saved = (services: controller.services.suggestions, plugins: controller.services.plugins, settings: settings)
        let folder = snapshotDirectory.appendingPathComponent("suggestions-plugins", isDirectory: true)
        defer {
            (controller.services.suggestions, controller.services.plugins, settings) = (saved.services, saved.plugins, saved.settings)
            SuggestionsShared.codingMode = false
            try? FileManager.default.removeItem(at: folder)
            controller.commitComposition(client)
            client.bundleIDOverride = nil
            controller.activateServer(client)
            controller.composer.setInputMode(settings.defaultInput)
            client.inserted.removeAll()
            if let notice = controller.notice { controller.endNotice(notice) }
        }
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = coreFolder.appendingPathComponent("Plugins/github", isDirectory: true)
        guard (try? FileManager.default.copyItem(at: source, to: folder.appendingPathComponent("github"))) != nil,
              let github = PluginStore.load(from: folder).plugins.first(where: { $0.name == "github" }),
              let issues = github.manifest.completions.first else {
            return check(false, "the GitHub plugin from \(source.path), with its issues source")
        }
        check(issues.prefix == "#" && issues.list && issues.query && issues.queryMinChars == 2 && github.manifest.preferences.count == 2,
              "Core/Plugins/github: #, a list and a query from 2 characters, two preferences (\(github.manifest.completions.count) source)")
        let standIn = GitHubStandIn()
        var services = saved.services
        services.store = SuggestionsStore()
        services.runtime = PluginCompletionRuntime(mode: .inProcess(fetcher: { _ in standIn }))
        services.cacheFolder = nil
        let approval = CompletionSourceApproval(enabling: issues, of: github)
        services.settings = { SuggestionsSettings(enabled: approval.map { [$0] } ?? []) }
        services.preferences = { _ in ["repos": GitHubStandIn.repository] }
        controller.services.suggestions = services
        controller.services.plugins = { _ in [github] }
        settings.setOrder([Language.chinese, .english])
        controller.commitComposition(client)
        client.bundleIDOverride = "com.example.editor"
        controller.activateServer(client)
        controller.composer.setInputMode(.english)
        client.inserted.removeAll()

        // "#1": the list's rows; no query yet (one character after "#").
        type("#1", controller, client)
        let listed = pump(timeout: 5) { controller.session.panelModel().rows.contains { $0.text.hasPrefix("#1234") } }
        let rows = controller.session.panelModel().rows.map(\.text)
        check(listed && !standIn.requests.contains { $0.hasSuffix("/issues/1") },
              "\"#1\": the plugin's list as rows (\(rows)), no query yet: \(standIn.requests.count) request(s)")
        // "#12": filtered at once, the query asked for "12".
        type("2", controller, client)
        let queried = pump(timeout: 5) { standIn.requests.contains { $0.hasSuffix("/issues/12") } }
        let model = controller.session.panelModel()
        check(queried && model.rows.map(\.text).prefix(3) == ["#1234 Fix login on the settings page", "#1201 Panel flickers on a second screen", "#12 Candidate panel position"]
              && (model.footer + " " + (model.detail ?? "")).contains("GitHub"),
              "\"#12\": its rows (\(model.rows.map(\.text))), the query asked once 2 characters follow #, the footer naming the source")
        snapshot("suggestions-rows", in: snapshotDirectory)
        check(CandidatePanel.shared.isShowing && CandidatePanel.shared.view.model.rows.count == model.rows.count,
              "…drawn in the candidate panel")
        // Tab: what wasn't typed of the first row.
        check(press(controller, client, "\t", code: VirtualKey.tab) && client.inserted.last == "34",
              "Tab inserts what wasn't typed of the first row: \"\(client.inserted.last ?? "")\"")
        check(controller.session.panelModel().rows.isEmpty, "…and the rows go")
        check(!press(controller, client, "\t", code: VirtualKey.tab), "…no rows: Tab is the app's")

        // Slack (a chat app): Tab inserts the issue with its address (the chat template).
        controller.commitComposition(client)
        client.bundleIDOverride = "com.tinyspeck.slackmacgap"
        controller.activateServer(client)
        controller.composer.setInputMode(.english)
        type("#12", controller, client)
        let slackRows = pump(timeout: 5) { !controller.session.panelModel().rows.isEmpty }
        check(slackRows && press(controller, client, "\t", code: VirtualKey.tab)
              && client.inserted.last == "34 https://github.com/\(GitHubStandIn.repository)/issues/1234",
              "Slack: Tab inserts \"{arg} {url}\": \"\(client.inserted.last ?? "")\"")
        check(!press(controller, client, "\r", code: VirtualKey.returnKey), "…and Return stays Slack's")

        // The child process a completion script runs in: a plugin with its own list (no host to reach), loaded there.
        let local = folder.appendingPathComponent("accounts", isDirectory: true)
        try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try? Data(#"""
            { "name": "accounts", "version": "1.0.0", "type": "script", "script": "main.js", "hosts": [],
              "completions": [ { "name": "ids", "title": "Accounts", "compare": "exact", "list": true } ] }
            """#.utf8).write(to: local.appendingPathComponent("plugin.json"))
        try? Data(#"function load(ctx) { return { items: [ { match: "123456789012", title: ctx.language + " " + ctx.source } ] }; }"#.utf8)
            .write(to: local.appendingPathComponent("main.js"))
        if let plugin = PluginStore.load(from: folder).plugins.first(where: { $0.name == "accounts" }), let ids = plugin.manifest.completions.first {
            let call = CompletionCall(plugin: plugin, source: ids, context: CompletionContext(source: "ids", preferences: [:], language: .english),
                                      timeout: 10, scriptSHA256: plugin.scriptURL.flatMap(PluginStore.sha256(of:)))
            let output = runAsync(15) { try? await PluginCompletionRuntime().load(call) } ?? nil
            let list = output.flatMap { try? CompletionOutput.read($0).get() }
            check(list?.items.first?.match == "123456789012" && list?.items.first?.title == "en ids",
                  "a completion script's load in its child process (--run-plugin … --completion load): \(output.map { String(decoding: $0, as: UTF8.self) } ?? "nothing")")
        } else {
            check(false, "the local accounts plugin loads")
        }

        // Coding mode: the Python pack's rows; a snippet goes in with its caret at $0.
        controller.commitComposition(client)
        client.bundleIDOverride = "com.example.editor"
        controller.activateServer(client)
        if let pack = try? Data(contentsOf: coreFolder.appendingPathComponent("CodingPacks/python.json")),
           (try? SuggestionsShared.packs.keep(pack, language: "python")) != nil {
            SuggestionsShared.packsChanged()
            controller.services.suggestions.codingPacks = { SuggestionsShared.codingPacks }
            SuggestionsShared.codingMode = true
            controller.activateServer(client)
            check(controller.composer.inputLanguage == .english && MenuBarIcon.shared.coding,
                  "coding mode: the field starts in English, the menu bar icon shows it")
            client.inserted.removeAll()
            type("pr", controller, client)
            let coded = pump(timeout: 2) { controller.session.panelModel().rows.contains { $0.text == "print" } }
            check(coded, "coding mode: \"pr\" offers the pack's print (\(controller.session.panelModel().rows.map(\.text)))")
            snapshot("suggestions-coding", in: snapshotDirectory)
            let rows = controller.session.panelModel().rows
            if let index = rows.firstIndex(where: { $0.text == "print" && !$0.comment.isEmpty }) {
                for _ in 0..<index { press(controller, client, "", code: VirtualKey.down) }
                if index == 0 { press(controller, client, "\t", code: VirtualKey.tab) } else { press(controller, client, "\r", code: VirtualKey.returnKey) }
            }
            check(client.inserted.last == "int()", "…the snippet goes in as \"int()\" (\(client.inserted.last ?? "-"))")
            SuggestionsShared.codingMode = false
            try? SuggestionsShared.packs.remove("python")
            SuggestionsShared.packsChanged()
        } else {
            check(false, "the Python pack from Core/CodingPacks")
        }
    }
}
