import AllInOneIMECore
import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    /// Settings → AI Provider with the API key field focused (`@config` when a provider needs a key).
    static let allInOneIMEFocusAPIKey = Notification.Name("AllInOneIMEFocusAPIKey")
}

/// `@config` in the input controller (`AIConfig`): the request on the on-device model first (`AIConfigService`), its
/// answer checked against the settings as they are and shown to confirm, then applied through the config file (as the
/// input menu and Settings save), with undo for ten minutes. Test Connection runs after the provider changed, and Settings
/// opens at the key field when a provider needs a key: keys never go through the AI.
@MainActor
enum AIConfigSession {
    /// The config file the changes go to (the self-test's own).
    static var url = Config.defaultURL
    static var service = AIConfigService()
    /// What undoes the last changes, kept for every text field of this process.
    static var lastApplied: AIConfig.Applied?
    static var now: () -> Date = Date.init
    /// What the checks need, for what the user typed (the self-test gives its own). Built off the main thread where it
    /// reads the keychain items' attributes, the login shell's variables or the apps on disk.
    static var environment: (_ typed: String) async -> AIConfig.Environment = { await liveEnvironment(typed: $0) }
    /// Settings → AI Provider with `provider`'s key field focused (shown there even when another provider is in use; the
    /// self-test records it).
    static var openKeyField: (Provider) -> Void = { provider in
        SettingsWindow.shared.show(page: .provider)
        // Once the page is up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: .allInOneIMEFocusAPIKey, object: nil, userInfo: ["provider": provider.rawValue])
        }
    }
    private static var prewarmed: Date?

    /// As `@config` or `@doctor` is written ("@co" in the list, or picked): the on-device model loaded and the checks'
    /// view of this Mac (the apps, the keychain's attributes) read ahead, at most once a minute, so the request that
    /// follows doesn't wait for them. Nothing is sent.
    static func prewarmIfDue() {
        guard prewarmed.map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return }
        prewarmed = Date()
        service.prewarm()
        Task { @MainActor in _ = await environment("") }
    }

    /// Test Connection, as Settings runs it, on the config file as it is now: what it said, and whether it worked.
    static var testConnection: (URL) async -> (ok: Bool, line: String) = { url in await runSettingsTest(url) }

    /// The checks' view of this Mac: the language packs installed, the apps, the AWS profiles (names only, read when
    /// asked), the models Settings offers, the providers offered and which have a key (from the keychain item's
    /// attributes: no key is read, nothing asked), the hosts of the services Settings offers, and what the user typed.
    static func liveEnvironment(typed: String) async -> AIConfig.Environment {
        // What the app's own objects hold, here on the main thread.
        let installed = Set(Language.allCases.filter { LanguagePackManager.shared.isUsable($0) })
        let models = knownModels()
        let offered = Provider.offered
        let chinese = UIText.chinese
        let hosts = AIConfig.compatibleHosts.union(CompatibleService.all.compactMap { URL(string: $0.baseURL)?.host?.lowercased() })
        let others = RecentApps.apps + Array(((try? Config.load(from: url)) ?? .default).appProfiles.keys)
        let cached = cachedApps.flatMap { Date().timeIntervalSince($0.date) < 60 ? $0.catalog : nil }
        // Off it: the keychain items' attributes and the login shell's variables (`APIKeys.source`), the apps on disk.
        let (keyed, apps) = await Task.detached(priority: .userInitiated) {
            (Set(Provider.allCases.filter { APIKeys.source($0) != .none }), cached ?? scanApps(adding: others))
        }.value
        if cached == nil { cachedApps = (Date(), apps) }
        return AIConfig.Environment(
            packInstalled: { installed.contains($0) }, apps: apps, awsProfiles: { AIConfig.awsProfiles().map(\.name) },
            knownModels: { models[$0] ?? [] }, offeredProviders: offered, hasKey: { keyed.contains($0) }, chinese: chinese,
            typedText: typed, knownHosts: hosts)
    }

    /// The models Settings offers for each provider (and the OpenAI-compatible services' own, where it names one).
    static func knownModels() -> [Provider: [String]] {
        var models: [Provider: [String]] = [:]
        for provider in [Provider.bedrock, .anthropic, .gemini, .openai] {
            models[provider] = SuggestedModel.suggested(for: provider).map(\.id)
        }
        models[.openai, default: []] += CompatibleService.all.compactMap(\.model).filter { !(models[.openai] ?? []).contains($0) }
        return models
    }

    private static var cachedApps: (date: Date, catalog: AIConfig.AppCatalog)?

    /// The apps in /Applications (and its Utilities), /System/Applications and ~/Applications, and `others` (typed in
    /// lately, with settings of their own), each with its names (as Finder shows it, its bundle's, in Chinese where the
    /// app has one: 微信). Off the main thread; kept for a minute.
    nonisolated static func scanApps(adding others: [String]) -> AIConfig.AppCatalog {
        var apps: [AIConfig.AppCatalog.App] = []
        var seen = Set<String>()
        let fm = FileManager.default
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                       fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        for folder in folders {
            for name in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, seen.insert(id.lowercased()).inserted else { continue }
                apps.append(AIConfig.AppCatalog.App(bundleID: id, names: names(of: bundle, at: url)))
            }
        }
        for id in others where seen.insert(id.lowercased()).inserted {
            // Elsewhere on the Mac (or not installed): by its bundle's names where macOS knows it, else its id.
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let names = url.flatMap { url in Bundle(url: url).map { names(of: $0, at: url) } } ?? [id]
            apps.append(AIConfig.AppCatalog.App(bundleID: id, names: names))
        }
        return AIConfig.AppCatalog(apps: apps)
    }

    /// An app's names: as Finder shows it, its bundle's display name and name, and its Chinese name if it has one.
    nonisolated static func names(of bundle: Bundle, at url: URL) -> [String] {
        var names = [FileManager.default.displayName(atPath: url.path), url.deletingPathExtension().lastPathComponent]
        let info = bundle.infoDictionary ?? [:]
        names += [info["CFBundleDisplayName"], info["CFBundleName"]].compactMap { $0 as? String }
        for lproj in ["zh-Hans", "zh_CN", "zh-CN", "zh_Hans", "zh"] {
            let strings = url.appendingPathComponent("Contents/Resources/\(lproj).lproj/InfoPlist.strings")
            if let table = NSDictionary(contentsOf: strings) as? [String: Any] {
                names += [table["CFBundleDisplayName"], table["CFBundleName"]].compactMap { $0 as? String }
            }
        }
        var seen = Set<String>()
        return names.map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The lookups the on-device model may call: apps by name, the AWS profiles and their regions (read when it asks:
    /// names and regions only, never a credential), the language packs.
    static func tools(_ env: AIConfig.Environment) -> AIConfigService.Tools {
        let apps = env.apps
        let packs = Language.allCases.map { language in
            "\(language.rawValue) (\(language.englishName)): " + (LanguagePack.for(language) == nil ? "built in"
                : env.packInstalled(language) ? "installed" : "not installed")
        }.joined(separator: "\n")
        return AIConfigService.Tools(
            findApps: { query in
                let found = apps.search(query)
                return found.isEmpty ? "No app found for \"\(query)\"." : found.map { "\($0.name): \($0.bundleID)" }.joined(separator: "\n")
            },
            awsProfiles: {
                let profiles = AIConfig.awsProfiles()
                return profiles.isEmpty ? "No AWS profiles in ~/.aws."
                    : profiles.map { "\($0.name) (region \($0.region ?? "-"))" }.joined(separator: "\n")
            },
            languagePacks: { packs })
    }

    /// Settings' own Test Connection on the config file at `url` (a model that saves nothing): its line once it's done.
    static func runSettingsTest(_ url: URL) async -> (ok: Bool, line: String) {
        let model = SettingsModel(configURL: url, persists: false)
        model.runTest()
        for await status in model.$testStatus.values {
            switch status {
            case let .passed(line): return (true, line.replacingOccurrences(of: "\n", with: " · "))
            case let .failed(line): return (false, line)
            case .idle, .running: continue
            }
        }
        return (false, "")
    }
}

extension AllInOneIMEInputController {
    /// Gets `@config` and `@doctor` ready while they are written: "@co", "@do" in the list, or the command picked.
    @MainActor
    func prewarmConfigIfWritten() {
        let query = composer.paletteQuery?.lowercased() ?? ""
        let writing = query.count >= 2 && ("config".hasPrefix(query) || "doctor".hasPrefix(query))
        guard writing || composer.draftCommand?.kind == .config || composer.draftCommand?.kind == .doctor else { return }
        AIConfigSession.prewarmIfDue()
    }

    /// The request for `@config <input>` (or a refine of its answer, `turns`): a key typed into it never goes out; the
    /// answer becomes the preview, or the one line that says why there is none.
    @MainActor
    func startConfigRequest(_ input: String, turns: [Refinement.Turn], id: Int) {
        conversionTask?.cancel()
        lastElapsed = nil
        lastFromCache = false
        lastHidden = 0
        let text = AIConfig.Text(chinese: UIText.chinese)
        // A key typed into the sentence, or into a refine's line, is dropped; with nothing else in what was typed last,
        // nothing is sent and the key field opens.
        let keys = AIConfig.droppingKeys(input)
        var sentTurns = turns
        for index in sentTurns.indices { sentTurns[index].instruction = AIConfig.droppingKeys(sentTurns[index].instruction).text }
        let latest = turns.last.map { AIConfig.droppingKeys($0.instruction) } ?? keys
        if latest.dropped, latest.text.filter(\.isLetter).count < 2 {
            log.notice("@config: a key typed into the text was dropped; nothing sent")
            perform(composer.endConfig(), client: nil)
            AIConfigSession.openKeyField(latest.provider ?? loadSettings().provider)
            showNotice(text.droppedKey, client: nil, long: true)
            return
        }
        let config = loadSettings()
        let models = AIConfigSession.knownModels()
        let service = AIConfigSession.service
        // What the user typed: a base URL's host must be in it (or be a service Settings offers).
        let typed = ([keys.text] + sentTurns.map(\.instruction)).joined(separator: "\n")
        // The AWS profiles' names go to a cloud provider only when the sentence is about AWS or Bedrock; the on-device
        // model gets them (from ~/.aws, names only) for its schema.
        let showsAWS = service.onDevice || AIConfig.mentionsAWS(typed)
        log.notice("@config \(id) started (\(keys.text.count) chars, step \(turns.count), \(service.onDevice ? "on device" : "provider", privacy: .public))")
        let started = Date()
        conversionTask = Task { @MainActor [weak self] in
            // Built off the main thread where it reads the keychain's attributes, the shell's variables, the apps on disk.
            let env = await AIConfigSession.environment(typed)
            let profiles = showsAWS ? await Task.detached { env.awsProfiles() }.value : []
            let context = AIConfigPrompt.Context(
                config: config, knownModels: models, awsProfiles: profiles, offeredProviders: env.offeredProviders,
                installedPacks: Set(Language.allCases.filter(env.packInstalled)), showsAWSProfile: showsAWS)
            let tools = AIConfigSession.tools(env)
            guard !Task.isCancelled else { return }
            do {
                let answer = try await service.ask(keys.text, turns: sentTurns, context: context, tools: tools)
                guard let self, !Task.isCancelled else { return }
                self.lastElapsed = Date().timeIntervalSince(started)
                self.lastFromCache = answer.fromCache
                self.lastHidden = answer.hidden
                self.showConfigAnswer(answer.text, id: id, env: env, droppedKey: (latest.dropped, latest.provider))
            } catch {
                guard let self, !Task.isCancelled else { return }
                log.error("@config \(id) failed: \(Self.errorKind(error), privacy: .public)")
                self.perform(self.composer.fail(UIText.describe(error) + tr("（可以试试 @doctor）", " (try @doctor)"), id: id), client: nil)
            }
        }
    }

    /// The answer read and checked against the settings as they are now: the preview, or the line that says why not.
    @MainActor
    func showConfigAnswer(_ answer: String, id: Int, env: AIConfig.Environment, droppedKey: (dropped: Bool, provider: Provider?)) {
        let text = AIConfig.Text(chinese: env.chinese)
        let outcome: Result<AIConfig.Preview, AIConfig.Failure>
        let proposal = try? AIConfig.parse(answer)
        if let proposal {
            outcome = AIConfig.preview(proposal, config: loadSettings(), environment: env, droppedKey: droppedKey)
        } else {
            log.notice("@config \(id): the answer wasn't readable")
            outcome = .failure(.notUnderstood)
        }
        switch outcome {
        case let .success(preview):
            log.notice("@config \(id): \(preview.rows.count) rows, \(preview.edits.count) to apply")
            perform(composer.receiveConfig(preview, lines: preview.rows.map { $0.text(chinese: env.chinese) }, answer: answer, id: id),
                    client: nil)
        case let .failure(failure):
            _ = text
            // Said in the log too (no rows to show): what the real-app test waits for, and what a report needs.
            log.notice("@config \(id): no preview (\(String(describing: failure), privacy: .public))")
            let line = AIConfig.failureLine(failure, proposal: proposal, config: loadSettings(), environment: env)
            perform(composer.fail(line, id: id), client: nil)
        }
    }

    /// ⏎ on the preview: the changes written to the config file (the input method and Settings read it from there), the
    /// confirmation shown with ⌘Z to undo; Settings opens at the key field when a provider needs one, and Test Connection
    /// runs after the provider changed.
    @MainActor
    func applyConfig(_ preview: AIConfig.Preview) {
        let text = AIConfig.Text(chinese: UIText.chinese)
        if !preview.edits.isEmpty {
            do {
                let applied = try AIConfig.applying(preview.edits, at: AIConfigSession.url, now: AIConfigSession.now())
                AIConfigSession.lastApplied = applied
                log.notice("@config: \(applied.count) changes applied")
            } catch {
                log.error("@config: couldn't write the settings: \(String(describing: error), privacy: .public)")
                perform(composer.configNotApplied(tr("没有保存：", "Not saved: ") + UIText.describe(error)), client: nil)
                return
            }
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            applySettings()
        }
        // @doctor's fixes besides the settings: a pack downloaded, a pane opened, the input method enabled again.
        for action in preview.actions { DoctorSession.perform(action) }
        if let provider = preview.needsKey {
            // The key is entered in Settings, never here: the panel closes as the window opens.
            perform(composer.endConfig(), client: nil)
            AIConfigSession.openKeyField(provider)
            if !preview.edits.isEmpty { showNotice(text.applied(preview.edits.count) + tr("。⌘Z 不行了，用 @config undo 撤销", ". Undo with @config undo"), client: nil) }
            return
        }
        let done = preview.edits.isEmpty ? tr("已完成：", "Done: ") + preview.rows.filter { $0.action != nil }.map(\.label).joined(separator: tr("；", "; "))
            : text.applied(preview.edits.count)
        perform(composer.configApplied(done), client: nil)
        guard preview.changesProvider else { return }
        perform(composer.configStatus(tr("正在测试连接…", "Testing the connection…")), client: nil)
        let url = AIConfigSession.url
        Task { @MainActor [weak self] in
            let (ok, line) = await AIConfigSession.testConnection(url)
            guard let self else { return }
            let status = ok ? tr("✓ 连接正常：", "✓ Connection works: ") + line
                : tr("✗ 连接失败：", "✗ Connection failed: ") + line + tr("（可以试试 @doctor）", " (try @doctor)")
            self.perform(self.composer.configStatus(status), client: nil)
        }
    }

    /// `@config undo`, or ⌘Z on the confirmation: the values the last changes replaced, back (within ten minutes).
    @MainActor
    func undoConfig() {
        let text = AIConfig.Text(chinese: UIText.chinese)
        guard let applied = AIConfigSession.lastApplied else {
            showNotice(text.nothingToUndo, client: nil)
            return
        }
        do {
            guard let report = try AIConfig.undoing(applied, at: AIConfigSession.url, now: AIConfigSession.now()) else {
                AIConfigSession.lastApplied = nil
                showNotice(text.nothingToUndo, client: nil)
                return
            }
            AIConfigSession.lastApplied = nil
            log.notice("@config: \(report.undone) changes undone, \(report.skipped.count) changed since and left as they are")
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            applySettings()
            // A key changed since @config wrote it (in Settings, by hand) is left as it is, and named.
            showNotice(text.undone(skipped: report.skipped), client: nil, long: !report.skipped.isEmpty)
        } catch {
            showNotice(tr("没能撤销：", "Couldn't undo: ") + UIText.describe(error), client: nil)
        }
    }
}

extension AllInOneIMEInputController {
    /// Under "@doctor " with nothing after it: what ⏎ does, and that a question can be asked.
    var doctorHint: String {
        tr("⏎ 检查设置（只在这台 Mac 上）；也可以问：@doctor 为什么翻译不了",
           "⏎ checks the setup (on this Mac only); or ask: @doctor why doesn't translate work")
    }

    /// Under "@config " with nothing after it yet: what can be written.
    var configHint: String {
        tr("说说想怎么改设置，比如：翻译成英语和法语 · 微信里用中文 · 候选竖排",
           "Describe a change, e.g. “output languages English and French” · “use Chinese in WeChat” · “candidates in a column”")
    }

    /// The panel of `@config`'s preview (its rows are the choices) or confirmation: the model's note or the key warning
    /// over it, what the keys do under it.
    @MainActor
    func configPanel(_ model: inout CandidateView.Model) {
        let state = composer.configState
        if state.applied != nil {
            // ⌘Z only when this wrote settings (`@doctor`'s fixes that only open a pane or start a download don't).
            model.footer = state.writesSettings
                ? tr("⌘Z 撤销 · Esc 关闭（10 分钟内也可以用 @config undo 撤销）", "⌘Z undo · Esc close (or @config undo within 10 minutes)")
                : tr("Esc 关闭", "Esc close")
            model.highlighted = nil
            return
        }
        guard let shown = composer.configPreview else { return }
        let text = AIConfig.Text(chinese: UIText.chinese)
        if shown.preview.droppedKey {
            model.status = .error(text.droppedKeyPreview)
        } else if let note = shown.preview.note {
            model.status = .hint(note)
        }
        if let error = composer.refineError { model.status = .error(error) }
        model.highlighted = nil
        let apply = shown.preview.edits.isEmpty ? tr("⏎ / 1 打开设置填密钥", "⏎ / 1 open Settings for the key")
            : shown.preview.needsKey != nil ? tr("⏎ / 1 应用并打开设置填密钥", "⏎ / 1 apply, then enter the key in Settings")
            : tr("⏎ / 1 全部应用", "⏎ / 1 apply all")
        model.footer = composer.activeCommand?.kind == .doctor ? apply + tr(" · Esc 回到检查结果", " · Esc back to the results")
            : composer.refineLine != nil ? tr("⇧⏎ 修改 · ⏎ 全部应用 · Esc 清除", "⇧⏎ refine · ⏎ apply · Esc clear")
            : apply + tr(" · 打字后 ⇧⏎ 修改 · Esc 取消", " · type, then ⇧⏎ to refine · Esc cancel")
        guard composer.activeCommand?.kind == .config else { return }  // @doctor's fixes asked no AI
        model.detail = AIConfigSession.service.onDevice ? tr("本机", "on device")
            : lastFromCache ? tr("缓存", "cached") : lastElapsed.map { String(format: "%.1fs", $0) }
    }
}

extension Provider {
    /// One whose requests need an API key the user enters (or, for the hosted service, a sign-in).
    var needsKey: Bool { self == .anthropic || self == .gemini || self == .openai }
}

/// The key field of a provider other than the one in use, on Settings → AI Provider: `@config` opened it for that
/// provider ("use Claude with my key"). Saved to the keychain as the provider's own field saves it.
struct ProviderKeyField: View {
    @ObservedObject var model: SettingsModel
    let provider: Provider
    var focus: FocusState<Provider?>.Binding
    @State private var key = ""

    var body: some View {
        LabeledContent(tr("API key（\(UIText.name(provider))）", "API key (\(UIText.name(provider)))")) {
            HStack {
                SecureField("API key", text: $key, prompt: Text(tr("粘贴新的 API key", "Paste a new API key")))
                    .focused(focus, equals: provider)
                    .onSubmit(save)
                Button(tr("保存", "Save"), action: save).disabled(key.isEmpty)
            }
        }
        Text(model.keyStatus(provider)).font(.caption).foregroundStyle(.secondary)
    }

    private func save() {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.saveKey(key, for: provider)
        key = ""
    }
}
