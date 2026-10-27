import AllInOneIMECore
import AppKit

/// api.github.com as the GitHub plugin's (Core/Plugins/github) `fetch` reaches it, a stand-in: recorded issues of a
/// made-up repository (octo-org/octo-repo; `issues` unless others are given), the list and each issue by number; every
/// request kept. Nothing leaves this Mac.
final class GitHubStandIn: PluginFetcher, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [String] = []
    var requests: [String] { lock.withLock { asked } }
    let listed: [(number: Int, title: String, state: String)]

    init(issues: [(number: Int, title: String, state: String)] = GitHubStandIn.issues) {
        listed = issues
    }

    static let repository = "octo-org/octo-repo"
    static let issues: [(number: Int, title: String, state: String)] = [
        (1234, "Fix login on the settings page", "open"), (1201, "Panel flickers on a second screen", "closed"),
        (12, "Candidate panel position", "open"), (7, "Docs: how to write a plugin", "open"),
        (17, "Return sends the message", "open"),
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
            if request.url.hasPrefix(base + "?") { return json(listed.map { Self.issue($0.number, $0.title, $0.state) }) }
            if request.url.hasPrefix(base + "/"), let number = Int(request.url.dropFirst(base.count + 1)) {
                guard let found = listed.first(where: { $0.number == number }) else { return PluginResponse(status: 404, text: "{}") }
                return json(Self.issue(found.number, found.title, found.state))
            }
            return PluginResponse(error: "not allowed: \(URL(string: request.url)?.host ?? request.url)")
        }
    }
}

extension SelfTest {
    /// Suggestions in a field of the self-test's own: nothing kept where the user's are (the lists' cache, the coding
    /// packs; the rows picked are `LearnedShared`'s, in memory while it runs), no plugin of the user's run. Before the
    /// controller's session is made (it takes them).
    @MainActor
    static func isolateSuggestions(in directory: URL) {
        SuggestionsShared.store = SuggestionsStore()
        SuggestionsShared.cacheFolder = directory.appendingPathComponent("suggestions-cache", isDirectory: true)
        SuggestionsShared.packs = CodingPackStore(directory: directory.appendingPathComponent("coding-packs", isDirectory: true))
        SuggestionsShared.runtime = PluginCompletionRuntime(mode: .inProcess(fetcher: { _ in GitHubStandIn() }))
        CodingPackManager.shared.library = CodingPackLibrary(store: SuggestionsShared.packs)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("suggestions-cache"))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("coding-packs"))
    }

    /// The GitHub plugin (Core/Plugins/github) copied into `folder` with its issues enabled in `controller`, its script
    /// run here with a stand-in for api.github.com (`GitHubStandIn`, with `issues`): what enabled them, to give the
    /// settings again with another Insert. Nil: it didn't load (a failed check says so).
    static func useGitHubPlugin(_ controller: AllInOneIMEInputController, in folder: URL,
                                issues listed: [(number: Int, title: String, state: String)] = GitHubStandIn.issues) -> CompletionSourceApproval? {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = coreFolder.appendingPathComponent("Plugins/github", isDirectory: true)
        guard (try? FileManager.default.copyItem(at: source, to: folder.appendingPathComponent("github"))) != nil,
              let github = PluginStore.load(from: folder).plugins.first(where: { $0.name == "github" }),
              let issues = github.manifest.completions.first, let approval = CompletionSourceApproval(enabling: issues, of: github) else {
            check(false, "the GitHub plugin from \(source.path), with its issues source")
            return nil
        }
        let standIn = GitHubStandIn(issues: listed)
        var services = controller.services.suggestions
        services.store = SuggestionsStore()
        services.runtime = PluginCompletionRuntime(mode: .inProcess(fetcher: { _ in standIn }))
        services.cacheFolder = nil
        services.settings = { SuggestionsSettings(enabled: [approval]) }
        services.preferences = { _ in ["repos": GitHubStandIn.repository] }
        controller.services.suggestions = services
        controller.services.plugins = { _ in [github] }
        return approval
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
    /// follow "#"), the first chosen from the start (decision 31), Tab inserts what wasn't typed of it; in Slack (a chat
    /// app) Return inserts the issue with its address too, and after → Return is Slack's. The child process a completion
    /// script runs in (`--run-plugin … --completion load`). Code (decision 22): a tap
    /// of Shift after the languages, its Python pack's rows (Core/CodingPacks), Return taking one at once, a snippet's
    /// caret, the menu bar icon's mark, the long press saying Translate as You Type isn't available there, an app that
    /// starts in it. Everything left as it was found.
    static func testSuggestions(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("Suggestions: the GitHub plugin's issues and Code (a stand-in for api.github.com)", needs: .composing)
        let saved = (services: controller.services.suggestions, plugins: controller.services.plugins, settings: settings,
                     shiftHeld: TranslateModeShared.shiftHeld, pointer: TranslateModeShared.pointer, stickyKeys: TranslateModeShared.stickyKeys)
        let folder = snapshotDirectory.appendingPathComponent("suggestions-plugins", isDirectory: true)
        defer {
            (controller.services.suggestions, controller.services.plugins, settings) = (saved.services, saved.plugins, saved.settings)
            (TranslateModeShared.shiftHeld, TranslateModeShared.pointer, TranslateModeShared.stickyKeys) = (saved.shiftHeld, saved.pointer, saved.stickyKeys)
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

        // "#1": the list's rows; no query yet (one character after "#"). The "1" key down handed over a second time, the
        // same event (the owner's "#17" had the session's token a "1" longer than the field): answered as the first,
        // nothing else done with it.
        type("#", controller, client)
        let one = event("1", code: keyCodes["1"] ?? 0)
        let first = controller.handle(one, client: client)
        let again = controller.handle(one, client: client)
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
        check(again == first && !standIn.requests.contains { $0.hasSuffix("/issues/112") },
              "\"1\" handed over twice (the same key down): the copy answered as the first (\(again)) and dropped, the token \"#12\" (\(standIn.requests.count) request(s))")
        snapshot("suggestions-rows", in: snapshotDirectory)
        check(CandidatePanel.shared.isShowing && CandidatePanel.shared.view.model.rows.count == model.rows.count,
              "…drawn in the candidate panel")
        let enter = Platform.current.terms.enter
        let footer = tr("Tab 或 \(enter) 插入 · ↑↓ 选择 · → 或 Esc 隐藏", "Tab or \(enter) inserts · ↑↓ to pick · → or Esc hides")
        check(model.highlighted == 0 && model.footer == footer,
              "…the first row chosen, drawn selected from the start (decision 31: \(String(describing: model.highlighted))), the footer \"\(model.footer)\"")
        // Tab: what wasn't typed of the first row, as the plugin's default template has it here ("{arg} {title}").
        check(press(controller, client, "\t", code: VirtualKey.tab) && client.inserted.last == "34 Fix login on the settings page",
              "Tab inserts what wasn't typed of the first row, with its title: \"\(client.inserted.last ?? "")\"")
        check(controller.session.panelModel().rows.isEmpty, "…and the rows go")
        check(!press(controller, client, "\t", code: VirtualKey.tab), "…no rows: Tab is the app's")

        // Slack (a chat app): the same keys (decision 31). Return inserts the chosen row, the issue with its title and
        // address (the plugin's chat template); after → hid the rows, Return is Slack's (it sends "#12" as typed).
        controller.commitComposition(client)
        client.bundleIDOverride = "com.tinyspeck.slackmacgap"
        controller.activateServer(client)
        controller.composer.setInputMode(.english)
        type("#12", controller, client)
        let slackRows = pump(timeout: 5) { !controller.session.panelModel().rows.isEmpty }
        check(slackRows && press(controller, client, "\r", code: VirtualKey.returnKey)
              && client.inserted.last == "34 Fix login on the settings page https://github.com/\(GitHubStandIn.repository)/issues/1234",
              "Slack: Return inserts \"{arg} {title} {url}\" of the chosen row: \"\(client.inserted.last ?? "")\"")
        _ = space(controller, client)
        client.inserted.removeAll()
        type("#12", controller, client)
        let slackAgain = pump(timeout: 5) { !controller.session.panelModel().rows.isEmpty }
        let hidden = press(controller, client, "", code: VirtualKey.right) && controller.session.panelModel().rows.isEmpty
        check(slackAgain && hidden && !press(controller, client, "\r", code: VirtualKey.returnKey) && client.inserted.isEmpty,
              "…→ hides the rows, then Return is Slack's: \"#12\" sent as typed (\(client.inserted))")

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

        // Code: an input after the languages, the Python pack's rows, Return picking one at once; the word typed held as
        // marked text until then (decision 33), a snippet going in its place with its caret at its first tab stop ($0 in
        // print's); Code's mark on the menu bar icon.
        controller.commitComposition(client)
        client.bundleIDOverride = "com.example.editor"
        controller.activateServer(client)
        if let pack = try? Data(contentsOf: coreFolder.appendingPathComponent("CodingPacks/python.json")),
           (try? SuggestionsShared.packs.keep(pack, language: "python")) != nil {
            SuggestionsShared.packsChanged()
            controller.services.suggestions.codingPacks = { SuggestionsShared.codingPacks }
            settings.codingLanguage = "python"
            controller.activateServer(client)
            controller.composer.setInputMode(.chinese)
            let code = tr("代码（Python）", "Code (Python)")
            tapShift(controller, client)
            let english = controller.composer.input == .language(.english) && MenuBarIcon.shared.code == nil
            tapShift(controller, client)
            check(english && controller.composer.input == .code && controller.composer.inputLanguage == .english
                  && controller.notice == code && MenuBarIcon.shared.code == code,
                  "a tap of Shift: 中 → English → Code, said (\(controller.notice ?? "-")), Code's mark on the menu bar icon")
            // "de" while that's said: its rows take the candidate panel, the notice on its footer's right, and no other
            // window of ours is where they are (a notice, autocomplete's gray text, Translate as You Type's chip).
            type("de", controller, client)
            let rowsShown = pump(timeout: 2) { !controller.session.panelModel().rows.isEmpty && CandidatePanel.shared.isShowing }
            let others = CandidatePanel.shared.overlapping
            check(rowsShown && others.isEmpty && CandidatePanel.shared.view.model.detail == code,
                  "Code: \"de\"'s rows in the candidate panel, the notice on its footer (\(CandidatePanel.shared.view.model.detail ?? "-")), "
                      + "no other window of ours where they are (\(others.map { "\(Swift.type(of: $0)) \(NSStringFromRect($0.frame))" }))")
            _ = space(controller, client)  // the token ends: "de" goes in as typed, the space the app's
            check(client.inserted == ["de"] && client.marked.isEmpty, "…a space puts the word in as typed (\(client.inserted))")
            client.inserted.removeAll()
            type("pr", controller, client)
            let coded = pump(timeout: 2) { controller.session.panelModel().rows.contains { $0.text == "print" } }
            check(coded && client.marked == "pr" && client.inserted.isEmpty,
                  "Code: \"pr\" held as marked text (\(client.marked)) offers the pack's print (\(controller.session.panelModel().rows.map(\.text)))")
            // ↓ and ↑ are the rows', the word still marked (Chromium's pages hand them to the page when nothing is).
            let down = press(controller, client, "", code: VirtualKey.down), moved = controller.session.panelModel().highlighted
            let up = press(controller, client, "", code: VirtualKey.up)
            check(down && up && moved == 1 && controller.session.panelModel().highlighted == 0 && client.marked == "pr",
                  "…↓ and ↑ move the chosen row with the word still marked (\(client.marked))")
            snapshot("suggestions-code", in: snapshotDirectory)
            let panel = controller.session.panelModel()
            check(panel.highlighted == 0 && !panel.rows.contains { $0.comment.contains("Python") },
                  "…the first row chosen, drawn selected (⏎ takes it), no row naming the language (\(panel.rows.map(\.comment)))")
            if let index = panel.rows.firstIndex(where: { $0.text == "print" && $0.comment != tr("关键字", "keyword") }) {
                for _ in 0..<index { press(controller, client, "", code: VirtualKey.down) }
                press(controller, client, "\r", code: VirtualKey.returnKey)
            }
            check(client.inserted.last == "print()" && client.marked.isEmpty,
                  "…⏎ puts the snippet in as \"print()\" in place of the word held (\(client.inserted.last ?? "-"))")

            // The long press of Shift in Code: Translate as You Type isn't available there, and nothing changes.
            (TranslateModeShared.shiftHeld, TranslateModeShared.pointer, TranslateModeShared.stickyKeys) = ({ true }, { .zero }, { false })
            _ = controller.handle(event("", code: VirtualKey.leftShift, flags: .shift, type: .flagsChanged), client: client)
            let refused = pump(timeout: 1.5) { controller.notice == tr("代码输入里不能边打边译", "Translate as You Type isn't available in Code") }
            _ = controller.handle(event("", code: VirtualKey.leftShift, flags: [], type: .flagsChanged), client: client)
            check(refused && !TranslateModeShared.state.isOn && controller.composer.input == .code,
                  "a long press of Shift in Code: \(controller.notice ?? "-"), the input still Code")
            (TranslateModeShared.shiftHeld, TranslateModeShared.pointer, TranslateModeShared.stickyKeys) = (saved.shiftHeld, saved.pointer, saved.stickyKeys)
            tapShift(controller, client)
            check(controller.composer.input == .language(.chinese) && MenuBarIcon.shared.code == nil,
                  "…a tap of Shift: back to Chinese, the menu bar icon as before")

            // An app that starts in Code (Settings → Apps); another doesn't.
            controller.commitComposition(client)
            settings.appProfiles["com.example.code"] = AppProfile()
            settings.appProfiles["com.example.code"]?.startingInput = .code
            client.bundleIDOverride = "com.example.code"
            controller.activateServer(client)
            let started = controller.composer.input == .code && MenuBarIcon.shared.code == code
            controller.commitComposition(client)
            client.bundleIDOverride = "com.example.editor"
            controller.activateServer(client)
            check(started && controller.composer.input == .language(.chinese) && MenuBarIcon.shared.code == nil,
                  "an app set to start in Code starts there, another in Chinese (\(controller.composer.input))")
            try? SuggestionsShared.packs.remove("python")
            SuggestionsShared.packsChanged()
        } else {
            check(false, "the Python pack from Core/CodingPacks")
        }
    }
}

extension SelfTest {
    /// Suggestion rows scroll (0.6.7.3), in the fake field with the candidate panel: the GitHub plugin's 23 issues
    /// "#7001" … "#7023" (a stand-in for api.github.com), "#70" typed. The panel shows 5 of them, the first chosen, its
    /// footer's right saying which ("1–5 / 23", as the command list says it); ↓ past the fifth chooses the sixth and moves
    /// the rows shown by one, the panel as high; the wheel over the panel moves the choice as ↓ and ↑ do, the rows shown
    /// following it, as the command list's wheel does (it stops at the last and the first, never around); Return puts in
    /// the row chosen, one shown; in the next token's rows, a click puts in the row clicked. Snapshots:
    /// suggestions-scrolled (after ↓), suggestions-wheel.
    static func testRowsScroll(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("Suggestions: 5 rows shown of up to 100, ↓ and the wheel move the choice through them", needs: .composing)
        let saved = (services: controller.services.suggestions, plugins: controller.services.plugins)
        let folder = snapshotDirectory.appendingPathComponent("suggestions-scroll", isDirectory: true)
        defer {
            (controller.services.suggestions, controller.services.plugins) = (saved.services, saved.plugins)
            try? FileManager.default.removeItem(at: folder)
            controller.commitComposition(client)
            client.bundleIDOverride = nil
            controller.activateServer(client)
            controller.composer.setInputMode(settings.defaultInput)
            client.inserted.removeAll()
            if let notice = controller.notice { controller.endNotice(notice) }
        }
        let issues = (7001...7023).map { (number: $0, title: "Issue \($0)", state: "open") }
        guard let approval = useGitHubPlugin(controller, in: folder, issues: issues) else { return }
        controller.services.suggestions.settings = { SuggestionsSettings(enabled: [approval], insert: .id) }
        controller.commitComposition(client)
        client.bundleIDOverride = "com.example.editor"
        controller.activateServer(client)
        controller.composer.setInputMode(.english)
        client.inserted.removeAll()
        let panel = CandidatePanel.shared
        /// The issues the panel shows, by number, the one drawn selected among them, and its footer's right.
        func shown() -> (rows: [String], highlighted: Int?, detail: String) {
            let model = panel.view.model
            return (model.rows.map { String($0.text.prefix(5)) }, model.highlighted, model.detail ?? "")
        }
        func numbers(_ range: ClosedRange<Int>) -> [String] { range.map { "#\($0)" } }
        type("#70", controller, client)
        let listed = pump(timeout: 5) { shown().rows == numbers(7001...7005) }
        let first = shown(), height = panel.frame.height
        check(listed && first.highlighted == 0 && first.detail.hasSuffix("1–5 / 23"),
              "\"#70\": 5 rows shown of 23 (\(first.rows)), the first chosen, the footer's right \"\(first.detail)\"")
        for _ in 1...5 { press(controller, client, "", code: VirtualKey.down) }
        let moved = shown()
        snapshot("suggestions-scrolled", in: snapshotDirectory)
        check(moved.rows == numbers(7002...7006) && moved.highlighted == 4 && moved.detail.hasSuffix("2–6 / 23") && panel.frame.height == height,
              "↓ past the fifth: the sixth chosen, the rows shown moved by one (\(moved.rows), \"\(moved.detail)\"), the panel as high "
              + "(\(Int(panel.frame.height)) pt)")
        /// The wheel over the panel, `lines` notches down (a mouse's wheel).
        func wheel(_ lines: Int32) {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -lines, wheel2: 0, wheel3: 0)
                .flatMap(NSEvent.init(cgEvent:)) else { return }
            panel.view.scrollWheel(with: event)
        }
        wheel(3)
        let wheeled = shown()
        wheel(100)
        let last = shown()
        snapshot("suggestions-wheel", in: snapshotDirectory)
        check(wheeled.rows == numbers(7005...7009) && wheeled.highlighted == 4 && wheeled.detail.hasSuffix("5–9 / 23")
              && last.rows == numbers(7019...7023) && last.highlighted == 4 && last.detail.hasSuffix("19–23 / 23") && panel.frame.height == height,
              "the wheel moves the choice as ↓ does, the rows shown following it (#7009: \(wheeled.rows), \(String(describing: wheeled.highlighted)), "
              + "\"\(wheeled.detail)\"), stopping at the last (\(last.rows), \(String(describing: last.highlighted)), \"\(last.detail)\")")
        wheel(-100)
        let top = shown()
        wheel(-1)
        let still = shown()
        check(top.rows == numbers(7001...7005) && top.highlighted == 0 && top.detail.hasSuffix("1–5 / 23") && still == top,
              "the wheel up stops at the first, never around to the last (\(top.rows), \(String(describing: top.highlighted)), \"\(top.detail)\"; "
              + "once more: \(still.rows), \(String(describing: still.highlighted)))")
        wheel(20)
        let chosen = shown()
        let entered = press(controller, client, "\r", code: VirtualKey.returnKey)
        check(chosen.rows == numbers(7017...7021) && chosen.highlighted == 4 && entered && client.inserted.last == "21"
              && controller.session.panelModel().rows.isEmpty,
              "Return after the wheel puts in the row chosen, shown (\(chosen.rows), \(String(describing: chosen.highlighted)): "
              + "\(client.inserted.last.map { "\"\($0)\"" } ?? "nothing")), the rows go")
        type(" #70", controller, client)
        let again = pump(timeout: 5) { shown().rows == numbers(7001...7005) }
        wheel(7)
        let clicked = shown()
        panel.view.onSelect?(1)
        _ = pump(timeout: 0.2) { false }
        check(again && clicked.rows == numbers(7004...7008) && client.inserted.last == "05" && controller.session.panelModel().rows.isEmpty,
              "\" #70\", the wheel to #7008 (\(clicked.rows)), a click on the second row shown puts #7005 in "
              + "(\(client.inserted.last.map { "\"\($0)\"" } ?? "nothing")), the rows go")
    }
}

extension SelfTest {
    /// A custom command of type Suggestions end to end (spec Suggestions v1, decision 24), in the fake field with the
    /// candidate panel: a temporary sh script of the self-test's own as its program (lines "match⇥title⇥url" with no
    /// argument; with one, a query's answer), run as `run` commands run (`CommandCompletionRunner`). "tk-1" shows its
    /// list's rows, "tk-12" asks it with "12" as its one argument, Tab inserts the row with its title; in Code its rows
    /// take the same keys as every row (decision 31: the first chosen from the start, Return takes it); "@tk" only says
    /// what it is. Nothing of the user's is run; everything left as it was found.
    static func testCustomSuggestions(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("Suggestions: a custom command's program as a source (a temporary sh script)", needs: .composing)
        let saved = (services: controller.services.suggestions, settings: settings)
        let folder = snapshotDirectory.appendingPathComponent("suggestions-command", isDirectory: true)
        defer {
            (controller.services.suggestions, settings) = (saved.services, saved.settings)
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
        let script = folder.appendingPathComponent("tickets")
        let log = folder.appendingPathComponent("calls.log")
        let program = """
            #!/bin/sh
            printf '%s\\n' "$#:$*" >> '\(log.path)'
            if [ $# -eq 0 ]; then
              printf 'tk-12\\tFix login\\thttps://tickets.example.com/tk-12\\n'
              printf 'tk-123\\tSlow search\\thttps://tickets.example.com/tk-123\\n'
            else
              printf 'tk-%s9\\tFound for %s\\n' "$1" "$1"
            fi
            """
        guard (try? Data(program.utf8).write(to: script)) != nil,
              (try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)) != nil else {
            return check(false, "the self-test's program at \(script.path)")
        }
        let command = CustomCommand(name: "tk", type: .suggestions, summary: "Tickets", argv: [script.path], prefix: "tk-",
                                    query: true, queryMinChars: 2, insert: CustomCommand.InsertPreset.title.insert)
        check(command.isValid && command.problem(among: []) == nil, "the command is a source (\(String(describing: command.suggestionSource)))")
        var services = saved.services
        services.store = SuggestionsStore()
        services.cacheFolder = nil
        services.commandRuntime = CommandCompletionRunner()
        services.settings = { SuggestionsSettings(commands: [command]) }
        controller.services.suggestions = services
        settings.customCommands = [command]
        controller.commitComposition(client)
        client.bundleIDOverride = "com.example.editor"
        controller.activateServer(client)
        controller.composer.setInputMode(.english)
        client.inserted.removeAll()
        func calls() -> [String] { ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }

        // "tk-1": the list's rows, the program run once with no argument.
        type("tk-1", controller, client)
        let listed = pump(timeout: 5) { controller.session.panelModel().rows.map(\.text).starts(with: ["tk-12", "tk-123"]) }
        check(listed && calls() == ["0:"], "\"tk-1\": the program's list as rows (\(controller.session.panelModel().rows.map(\.text))), run with no argument (\(calls()))")
        // "tk-12": the query, "12" its one argument; its answer after the list's.
        type("2", controller, client)
        let queried = pump(timeout: 5) { controller.session.panelModel().rows.map(\.text) == ["tk-12", "tk-123", "tk-129"] }
        let model = controller.session.panelModel()
        check(queried && calls().contains("1:12") && (model.footer + " " + (model.detail ?? "")).contains("Tickets"),
              "\"tk-12\": the query's row too (\(model.rows.map(\.text))), asked with \"12\" (\(calls())), the footer naming it")
        snapshot("suggestions-command", in: snapshotDirectory)
        check(CandidatePanel.shared.isShowing && CandidatePanel.shared.view.model.rows.count == model.rows.count, "…drawn in the candidate panel")
        // Tab: the rest of the first row, with its title ("With its title").
        check(press(controller, client, "\t", code: VirtualKey.tab) && client.inserted.last == " Fix login",
              "Tab inserts what wasn't typed of \"tk-12 Fix login\": \"\(client.inserted.last ?? "")\"")

        // Code (its Python pack from Core/CodingPacks for the while): its rows with the same keys as everywhere (decision
        // 31): the first chosen from the start, Return puts it in.
        if let pack = try? Data(contentsOf: coreFolder.appendingPathComponent("CodingPacks/python.json")),
           (try? SuggestionsShared.packs.keep(pack, language: "python")) != nil {
            SuggestionsShared.packsChanged()
            controller.services.suggestions.codingPacks = { SuggestionsShared.codingPacks }
            settings.codingLanguage = "python"
            controller.commitComposition(client)
            controller.activateServer(client)
            controller.composer.setInput(.code)
            client.inserted.removeAll()
            type("tk-1", controller, client)
            let coded = pump(timeout: 5) { controller.session.panelModel().rows.map(\.text).starts(with: ["tk-12", "tk-123"]) }
            let codeModel = controller.session.panelModel()
            check(coded && controller.composer.input == .code && codeModel.highlighted == 0,
                  "Code: \"tk-1\" shows its rows (\(codeModel.rows.map(\.text))), the first chosen and drawn selected")
            check(press(controller, client, "\r", code: VirtualKey.returnKey) && client.inserted.last == "2 Fix login",
                  "…and Return puts it in, with its title (\(client.inserted))")
            controller.commitComposition(client)
            settings.codingLanguage = saved.settings.codingLanguage
            try? SuggestionsShared.packs.remove("python")
            SuggestionsShared.packsChanged()
        } else {
            check(false, "the Python pack from Core/CodingPacks")
        }

        // "@tk": a source, not an action: what it is said, nothing runs, nothing goes in.
        controller.commitComposition(client)
        controller.activateServer(client)
        controller.composer.setInputMode(.english)
        client.inserted.removeAll()
        let before = calls().count
        _ = press(controller, client, "@", code: 0x13, flags: .shift)
        type("tk", controller, client)
        press(controller, client, "\r", code: VirtualKey.returnKey)
        press(controller, client, "\r", code: VirtualKey.returnKey)
        let said = controller.panelModel().detail ?? controller.notice ?? ""
        check(said.contains("tk-") && client.inserted.isEmpty && calls().count == before,
              "\"@tk\" ⏎ only says what it is: \"\(said)\", nothing inserted (\(client.inserted)), nothing run")
        for _ in 0..<3 { press(controller, client, "\u{1B}", code: VirtualKey.escape) }
    }
}
