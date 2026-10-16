import AllInOneIMECore
import AppKit
import Combine

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
    /// What the checks need (the self-test gives its own).
    static var environment: () -> AIConfig.Environment = { liveEnvironment() }
    /// Settings → AI Provider at the key field (the self-test records it).
    static var openKeyField: (Provider) -> Void = { _ in
        SettingsWindow.shared.show(page: .provider)
        // Once the page is up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: .allInOneIMEFocusAPIKey, object: nil)
        }
    }
    /// Test Connection, as Settings runs it, on the config file as it is now: what it said, and whether it worked.
    static var testConnection: (URL) async -> (ok: Bool, line: String) = { url in await runSettingsTest(url) }

    /// The checks' view of this Mac: the language packs installed, the apps, the AWS profiles, the models Settings offers,
    /// the providers offered and which have a key (from the keychain item's attributes: no key is read, nothing asked).
    static func liveEnvironment() -> AIConfig.Environment {
        let installed = Set(Language.allCases.filter { LanguagePackManager.shared.isUsable($0) })
        let models = knownModels()
        let keyed = Set(Provider.allCases.filter { APIKeys.source($0) != .none })
        return AIConfig.Environment(
            packInstalled: { installed.contains($0) }, apps: appCatalog(), awsProfiles: { AWSSharedConfig.profileNames() },
            knownModels: { models[$0] ?? [] }, offeredProviders: Provider.offered,
            hasKey: { keyed.contains($0) }, chinese: UIText.chinese)
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

    /// The apps in /Applications (and its Utilities), /System/Applications and ~/Applications, those typed in lately and
    /// those with settings of their own, each with its names (as Finder shows it, its bundle's, in Chinese where the app
    /// has one: 微信). Read again after a minute.
    static func appCatalog() -> AIConfig.AppCatalog {
        if let cachedApps, Date().timeIntervalSince(cachedApps.date) < 60 { return cachedApps.catalog }
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
        let config = (try? Config.load(from: url)) ?? .default
        for id in RecentApps.apps + Array(config.appProfiles.keys) where seen.insert(id.lowercased()).inserted {
            apps.append(AIConfig.AppCatalog.App(bundleID: id, names: [AppNames.name(for: id)]))
        }
        let catalog = AIConfig.AppCatalog(apps: apps)
        cachedApps = (Date(), catalog)
        return catalog
    }

    /// An app's names: as Finder shows it, its bundle's display name and name, and its Chinese name if it has one.
    static func names(of bundle: Bundle, at url: URL) -> [String] {
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

    /// The lookups the on-device model may call: apps by name, the AWS profiles and their regions (names only), the
    /// language packs.
    static func tools(_ env: AIConfig.Environment) -> AIConfigService.Tools {
        let apps = env.apps
        let profiles = AWSSharedConfig.profileNames()
        let regions = Dictionary(uniqueKeysWithValues: profiles.map { ($0, (try? AWSSharedConfig.load(profile: $0))?.region ?? "-") })
        let packs = Language.allCases.map { language in
            "\(language.rawValue) (\(language.englishName)): " + (LanguagePack.for(language) == nil ? "built in"
                : env.packInstalled(language) ? "installed" : "not installed")
        }.joined(separator: "\n")
        return AIConfigService.Tools(
            findApps: { query in
                let found = apps.search(query)
                return found.isEmpty ? "No app found for \"\(query)\"." : found.map { "\($0.name): \($0.bundleID)" }.joined(separator: "\n")
            },
            awsProfiles: { profiles.isEmpty ? "No AWS profiles in ~/.aws." : profiles.map { "\($0) (region \(regions[$0] ?? "-"))" }.joined(separator: "\n") },
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
    /// The request for `@config <input>` (or a refine of its answer, `turns`): a key typed into it never goes out; the
    /// answer becomes the preview, or the one line that says why there is none.
    @MainActor
    func startConfigRequest(_ input: String, turns: [Refinement.Turn], id: Int) {
        conversionTask?.cancel()
        lastElapsed = nil
        lastFromCache = false
        lastHidden = 0
        let text = AIConfig.Text(chinese: UIText.chinese)
        // A key typed into the sentence is dropped; with nothing else in it, nothing is sent and the key field opens.
        let keys = AIConfig.droppingKeys(input)
        if keys.dropped, keys.text.filter(\.isLetter).count < 2 {
            log.notice("@config: a key typed into the text was dropped; nothing sent")
            perform(composer.endConfig(), client: nil)
            AIConfigSession.openKeyField(keys.provider ?? loadSettings().provider)
            showNotice(text.droppedKey, client: nil, long: true)
            return
        }
        let env = AIConfigSession.environment()
        let config = loadSettings()
        let models = AIConfigSession.knownModels()
        let context = AIConfigPrompt.Context(
            config: config, knownModels: models, awsProfiles: env.awsProfiles(), offeredProviders: env.offeredProviders,
            installedPacks: Set(Language.allCases.filter(env.packInstalled)))
        let service = AIConfigSession.service, tools = AIConfigSession.tools(env)
        log.notice("@config \(id) started (\(keys.text.count) chars, step \(turns.count), \(service.onDevice ? "on device" : "provider", privacy: .public))")
        let started = Date()
        conversionTask = Task { @MainActor [weak self] in
            do {
                let answer = try await service.ask(keys.text, turns: turns, context: context, tools: tools)
                guard let self, !Task.isCancelled else { return }
                self.lastElapsed = Date().timeIntervalSince(started)
                self.lastFromCache = answer.fromCache
                self.lastHidden = answer.hidden
                self.showConfigAnswer(answer.text, id: id, env: env, droppedKey: (keys.dropped, keys.provider))
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
            guard try AIConfig.undo(applied, at: AIConfigSession.url, now: AIConfigSession.now()) else {
                AIConfigSession.lastApplied = nil
                showNotice(text.nothingToUndo, client: nil)
                return
            }
            AIConfigSession.lastApplied = nil
            log.notice("@config: \(applied.count) changes undone")
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            applySettings()
            showNotice(text.undone, client: nil)
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
            model.footer = tr("⌘Z 撤销 · Esc 关闭（10 分钟内也可以用 @config undo 撤销）",
                              "⌘Z undo · Esc close (or @config undo within 10 minutes)")
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
            : composer.refineLine != nil ? tr("⏎ 按这句修改 · ⌫ 删字 · Esc 清除", "⏎ refine · ⌫ delete · Esc clear")
            : apply + tr(" · 打字修改 · Esc 取消", " · type to refine · Esc cancel")
        guard composer.activeCommand?.kind == .config else { return }  // @doctor's fixes asked no AI
        model.detail = AIConfigSession.service.onDevice ? tr("本机", "on device")
            : lastFromCache ? tr("缓存", "cached") : lastElapsed.map { String(format: "%.1fs", $0) }
    }
}
