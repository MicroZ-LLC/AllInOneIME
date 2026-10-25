import AllInOneIMECore
import AppKit
import SwiftUI

/// `AllInOneIME --showcase OUT-DIR [dark] [zh]`: the menu bar panel as it looks on screen, for the release
/// notes and the wiki. The real panel with the self-test's sample data (English; `zh`: Chinese) drops down over a
/// colorful window, so its frosted glass has something to blur, and is captured with `screencapture`:
/// `panel.png` as it opens, `panel-swipe.png` with a task swiped open to its Remove button, and the candidate
/// panel under a line being typed: `candidates.png` in a column, `candidates-horizontal.png` in a row; then two
/// settings menus open (`captureLanguageMenu`): `language-menu.png` and `note-save-to-menu.png`. An
/// offscreen render can't show the glass (nothing is behind it). Needs the screen unlocked; the windows
/// are up for about four seconds. Nothing real is read: Notes, Reminders and Claude Code are stand-ins.
@MainActor
enum PanelShowcase {
    static let backdrop = CGRect(x: 120, y: 160, width: 760, height: 450)

    static func run(output: URL, dark: Bool, chinese: Bool) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        UIText.choice = chinese ? "zh" : "en"
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let back = NSWindow(contentRect: backdrop, styleMask: [.borderless], backing: .buffered, defer: false)
        back.contentView = NSHostingView(rootView: Backdrop(chinese: chinese))
        back.level = .normal
        back.orderFrontRegardless()

        let stand = PanelStandIns()
        stand.sample(chinese: chinese)
        let panel = FloatingPanel(sources: stand.sources)
        panel.prepareWindow = { $0.appearance = appearance }
        // Under an icon near the backdrop's top right, as from the menu bar.
        let anchor = CGRect(x: backdrop.maxX - 120, y: backdrop.maxY - 40, width: 22, height: 24)
        panel.show(below: anchor)

        func capture(_ name: String) {
            let height = NSScreen.screens[0].frame.height  // screencapture counts from the top
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-R", "\(Int(backdrop.minX)),\(Int(height - backdrop.maxY)),\(Int(backdrop.width)),\(Int(backdrop.height))",
                              output.appendingPathComponent(name).path]
            try? task.run()
            task.waitUntilExit()
            print("  \(output.appendingPathComponent(name).path)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated {
                capture("panel.png")
                // The candidate panel, as under a line being typed at the backdrop's left.
                panel.closeDropDown()
                let rows = (chinese ? ["哦", "噢", "喔", "欧", "偶"] : ["oh", "ok", "of", "on", "out"]).enumerated().map {
                    PanelModel.Row(label: "\($0.offset + 1)", text: $0.element, kind: .candidate)
                }
                let line = NSRect(x: backdrop.minX + 60, y: backdrop.maxY - 150, width: 2, height: 20)
                CandidatePanel.shared.appearance = appearance
                CandidatePanel.shared.show(PanelModel(rows: rows, highlighted: 0,
                                                      footer: chinese ? "空格 选词 · 开头打 @ 用命令" : "Space picks · @ for commands"),
                                           anchor: line)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            MainActor.assumeIsolated {
                capture("candidates.png")
                // The same in a row (`candidateLayout`), the second highlighted as → would.
                let rows = (chinese ? ["我们", "我门", "握们", "沃们", "卧"] : ["we", "well", "were", "went", "west"]).enumerated().map {
                    PanelModel.Row(label: "\($0.offset + 1)", text: $0.element, kind: .candidate)
                }
                let line = NSRect(x: backdrop.minX + 60, y: backdrop.maxY - 150, width: 2, height: 20)
                CandidatePanel.shared.show(PanelModel(rows: rows, highlighted: 1,
                                                      footer: chinese ? "空格 选词 · 开头打 @ 用命令" : "Space picks · @ for commands",
                                                      detail: chinese ? "第 1 页" : "page 1", horizontal: true),
                                           anchor: line)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            MainActor.assumeIsolated {
                capture("candidates-horizontal.png")
                CandidatePanel.shared.hide()
                panel.show(below: anchor)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) {
            MainActor.assumeIsolated {
                if case let .list(rows) = panel.tasks, let row = rows.first { panel.showSwiped(.task(row.id)) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    MainActor.assumeIsolated {
                        capture("panel-swipe.png")
                        panel.closeDropDown()
                        captureLanguageMenu(output: output, appearance: appearance)
                    }
                }
            }
        }
        app.run()
        exit(0)
    }

    /// A settings menu clicked open on screen and captured: Settings → General's interface language menu, each language
    /// in its own (`language-menu.png`), then Settings → Commands → Notes (@note)'s "Save to" (`note-save-to-menu.png`).
    /// The settings window from a config of its own (the defaults; nothing saved, no key looked up); run it with a
    /// sample home (CFFIXED_USER_HOME) so the Commands page lists no plugins of the user's. Exits when done.
    static func captureLanguageMenu(output: URL, appearance: NSAppearance?) {
        let config = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-showcase-\(UUID().uuidString).json")
        try? Config.default.write(to: config)
        SettingsModel.looksUpKeys = false
        // Each found by the item it shows (its menu is filled as it opens).
        let menus: [(page: SettingsPage, item: String, file: String, setUp: (SettingsModel) -> Void)] = [
            (.general, tr("跟随系统", "Follow the system"), "language-menu.png", { _ in }),
            (.commands, tr("文件夹（Obsidian 等）", "Folder (Obsidian or any)"), "note-save-to-menu.png",
             { $0.config.notes = NoteSettings(destination: .folder, folder: "~/Vault/Inbox") }),
        ]
        func capture(_ index: Int) {
            guard index < menus.count else {
                try? FileManager.default.removeItem(at: config)
                exit(0)
            }
            let menu = menus[index]
            let model = SettingsModel(configURL: config, persists: false)
            menu.setUp(model)
            let frame = NSRect(x: backdrop.minX, y: backdrop.minY + 10, width: 880, height: 640)
            // A plain backdrop under the window and the margin captured around it, wider below and on the right where
            // the menu may reach past the window: nothing else on the screen shows.
            let shot = NSRect(x: frame.minX - 24, y: frame.minY - 150, width: frame.width + 24 + 60, height: frame.height + 150 + 24)
            let plain = NSWindow(contentRect: shot, styleMask: [.borderless], backing: .buffered, defer: false)
            plain.backgroundColor = NSColor(calibratedWhite: appearance?.name == .darkAqua ? 0.16 : 0.93, alpha: 1)
            plain.isReleasedWhenClosed = false
            plain.orderFrontRegardless()
            let window = NSWindow(contentRect: frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = appearance
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model, page: menu.page))
            window.orderFrontRegardless()
            NSApp.activate()
            window.makeKey()
            func popUps(in view: NSView) -> [NSPopUpButton] {
                (view as? NSPopUpButton).map { [$0] } ?? view.subviews.flatMap(popUps)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                MainActor.assumeIsolated {
                    guard let view = window.contentView,
                          let button = popUps(in: view).first(where: { $0.title == menu.item }) else {
                        print("  no menu with \(menu.item) found")
                        window.close()
                        plain.close()
                        return capture(index + 1)
                    }
                    // Room under it for the menu, which drops from the item checked.
                    button.scrollToVisible(button.bounds.insetBy(dx: 0, dy: -60).offsetBy(dx: 0, dy: button.isFlipped ? 340 : -340)
                        .union(button.bounds))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        MainActor.assumeIsolated {
                            // The window and the plain margin around it; screencapture counts from the top.
                            let height = NSScreen.screens[0].frame.height
                            let path = output.appendingPathComponent(menu.file).path
                            let open = button.menu
                            Thread.detachNewThread {
                                Thread.sleep(forTimeInterval: 1.0)
                                let task = Process()
                                task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                                task.arguments = ["-x", "-R", "\(Int(shot.minX)),\(Int(height - shot.maxY)),\(Int(shot.width)),\(Int(shot.height))", path]
                                try? task.run()
                                task.waitUntilExit()
                                print("  \(path)")
                                RunLoop.main.perform(inModes: [.eventTracking, .common, .default]) { open?.cancelTracking() }
                            }
                            button.performClick(nil)  // tracks the menu until it's cancelled above
                            window.close()
                            plain.close()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { capture(index + 1) } }
                        }
                    }
                }
            }
        }
        capture(0)
    }

    /// A busy, colorful screen: the glass blurs it.
    private struct Backdrop: View {
        let chinese: Bool
        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(red: 0.98, green: 0.6, blue: 0.3), Color(red: 0.92, green: 0.3, blue: 0.45),
                                        Color(red: 0.6, green: 0.3, blue: 0.9), Color(red: 0.25, green: 0.55, blue: 0.95)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 14) {
                    Text(chinese ? "第四季度计划" : "Q4 Planning").font(.system(size: 44, weight: .heavy))
                    ForEach(chinese ? ["上线新手引导", "改版价格页", "招两位工程师", "用户访谈", "进入欧洲市场"]
                                    : ["Ship the onboarding flow", "Review the pricing page", "Hire two engineers",
                                       "Customer interviews", "Launch in Europe"], id: \.self) {
                        Text("• " + $0).font(.system(size: 24, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(40)
            }
            .frame(width: PanelShowcase.backdrop.width, height: PanelShowcase.backdrop.height)
        }
    }
}

/// `AllInOneIME --settings-image OUT-DIR [zh] [dark]`: every page of the settings window drawn offscreen,
/// `settings-<page>.png`, from the config file as it is (nothing is saved), with sample apps and hidden words.
@MainActor
enum SettingsPageImages {
    static func run(output: URL, chinese: Bool, dark: Bool, extensions: String? = nil, update: String? = nil,
                    agent: String? = nil, doctor: String? = nil) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        UIText.choice = chinese ? "zh" : "en"
        let model = SettingsModel(configURL: Config.defaultURL, persists: false)
        model.profileShownAs = "default"  // not the user's own profile name
        // AWS profiles: samples of every kind in a folder of their own, never the user's ~/.aws (`AWSProfileSamples`).
        AWSProfileSamples.use(in: model)
        // Fuzzy pinyin shown on, with its pairs (the model saves nothing).
        if !model.config.inputLanguages.contains(.chinese) { model.config.setOrder(model.config.inputLanguages + [.chinese]) }
        if model.config.fuzzyPinyin.isEmpty { model.config.fuzzyPinyin = SettingsModel.fuzzyDefaults }
        // Code shown added, in Python (the model saves nothing).
        if model.config.codingLanguage == nil { model.config.codingLanguage = "python" }
        // Sample apps (Insert's, Apps without AI, the previous per-app settings), never the user's own (the images go into
        // docs and release notes).
        model.config.appProfiles = AppProfileSamples.profiles
        // Hiding sensitive information shown on, with its switches and sample words, never the user's own.
        model.config.redaction = RedactionSettings(enabled: true, customWords: ["Project Atlas", "Phoenix"])
        // What is learned (Privacy → Learned…): samples, in memory, never the user's.
        let learnedSamples = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-learned-\(UUID().uuidString)")
        LearnedShared.store = LearnedSamples.store(in: learnedSamples)
        // Extension sources: samples, never the user's (their statuses only shown, never saved).
        model.config.extensionSources = ExtensionSourceSamples.sources
        for source in model.config.extensionSources { ExtensionSources.enable(source, in: &model.config) }
        ExtensionSourceController.shared.show(ExtensionSourceSamples.statuses())
        ExtensionSourcesSection.shownLoaded = ExtensionSourceSamples.loaded
        // Public examples rather than the user's own folders, when given (`extensions=<folder>[,<found folder>…]`:
        // the first as added, any others as if Spotlight had found them).
        if let extensions {
            let paths = extensions.split(separator: ",").map { ExtensionStore.abbreviated((String($0) as NSString).expandingTildeInPath) }
            model.config.extensionFolders = Array(paths.prefix(1))
            model.config.findRaycastScripts = paths.count > 1
            model.config.hiddenExtensionFolders = []
            LiveExtensions.shownFound = Array(paths.dropFirst())
            // Their completion sources shown turned on (`bookmarks`' `bm.`): the switch under the command, what it does.
            for command in LiveExtensions.load(model.config).commands {
                guard case let .success(source)? = command.completion else { continue }
                model.config.setCompletionSource(source, of: command, enabled: true)
            }
        }
        // `@agent` handing the text to another agent (`agent=gemini`, `agent=custom:muse --`).
        if let agent {
            let (kind, command) = agent.firstIndex(of: ":").map { (String(agent[..<$0]), String(agent[agent.index(after: $0)...])) }
                ?? (agent, "")
            model.config.agent = AgentKind(rawValue: kind) ?? .claude
            model.config.agentCommand = CustomCommand.arguments(fromCommandLine: command) ?? []
        }
        // Sync through iCloud shown on, synced a while ago (nothing is read or synced).
        model.config.iCloudSync = ICloudSyncSettings(enabled: true)
        // …with its "API keys and passwords" row as a build with the provisioning profile shows it, turned on.
        ICloudSyncSection.shownEntitled = true
        model.config.iCloudSync.keys = true
        ICloudSyncController.shared.show(status: .synced(Date().addingTimeInterval(-120)), lastSync: Date().addingTimeInterval(-120))
        // The Updates card in a state of its own (nothing is checked or downloaded).
        if let update {
            let updates = UpdateController.shared
            updates.lastChecked = Date().addingTimeInterval(-2 * 3600)
            updates.updatesInPlace = true  // as the installed copy shows it (Update, not Download)
            switch update {
            case "available": updates.state = .available(.sample())
            case "downloading": updates.state = .downloading(.sample(), 0.42)
            case "failed": updates.state = .failed(UpdateText.describe(UpdateError.hashMismatch), .sample())
            case "updated":
                updates.state = .upToDate
                updates.lastResult = UpdateResult(from: "0.6.2", to: AppVersion.string, ok: true)
            default: updates.state = .upToDate
            }
        }
        // The checks and the search's Change: a sample request and findings from stand-ins and a config file of their own
        // (no probe of this Mac, no AI, nothing of the user's): the pages with nothing wrong, then made-up problems (unless
        // `doctor=fine`) on a page's banner and in Troubleshoot (`doctor=open`: what is fine opened there).
        let samples = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-assistant-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        let rig = SelfTest.AssistantRig(samples, name: "config.json", config: SelfTest.assistantSampleConfig)
        let shownChecks = doctor?.split(separator: ",") ?? []
        let fine = SelfTest.sampleAssistant(rig, fine: true)
        fine.dismissPreview()
        func render(_ page: SettingsPage, _ name: String, assistant: AssistantModel = fine, query: String = "",
                    troubleshoot: Bool = false) {
            SettingsImage.render(model, page: page, assistant: assistant, query: query, troubleshoot: troubleshoot,
                                 to: output.appendingPathComponent("settings-\(name).png"),
                                 appearance: dark ? .darkAqua : .aqua) { RunLoop.main.run(until: Date().addingTimeInterval($0)) }
        }
        for page in SettingsPage.allCases { render(page, page.rawValue) }
        // Settings no longer shown, set otherwise than their default: their rows with Restore Default.
        let saved = model.config
        model.config.maxTokens = 3000
        model.config.redaction.phones = false
        model.config.suggestionsInsert = .id
        render(.ai, "restore-default")
        render(.privacy, "restore-default-privacy")
        render(.general, "restore-default-insert")
        // Insert set to Markdown link, everywhere (0.6.7.1).
        model.config = saved
        model.config.suggestionsInsert = .markdownLink
        render(.general, "insert-markdown-link")
        model.config = saved
        let troubled = SelfTest.sampleAssistant(rig, fine: shownChecks.contains("fine"))
        troubled.showsFine = shownChecks.contains("open")
        // The sample request's preview where the search's "Change: …" shows it, the search typed.
        render(.general, "search", assistant: troubled, query: troubled.request)
        troubled.dismissPreview()
        render(.ai, "problem", assistant: troubled)
        render(.about, "troubleshoot", assistant: troubled, troubleshoot: true)
        rig.restore()
        // Privacy → Learned…: the list with the samples, then empty (all forgotten, in memory).
        SettingsImage.render(model, page: .privacy, assistant: fine, learned: true, to: output.appendingPathComponent("settings-learned.png"),
                             appearance: dark ? .darkAqua : .aqua) { RunLoop.main.run(until: Date().addingTimeInterval($0)) }
        model.forgetAllLearned()
        SettingsImage.render(model, page: .privacy, assistant: fine, learned: true,
                             to: output.appendingPathComponent("settings-learned-empty.png"),
                             appearance: dark ? .darkAqua : .aqua) { RunLoop.main.run(until: Date().addingTimeInterval($0)) }
        try? FileManager.default.removeItem(at: learnedSamples)
        try? FileManager.default.removeItem(at: samples)
        // AI Provider's key row with a key saved (its last 4 shown) and without one, and the key sheet for another
        // provider: sample states, no keychain asked.
        let provider = model.config.provider
        model.showKeys([.openai: .keychain, .anthropic: .none, .gemini: .none], endings: [.openai: "a1b2"])
        for (shown, sheet, name) in [(Provider.openai, nil, "key-saved"), (.gemini, nil, "key-missing"), (.bedrock, Provider.gemini, "key-sheet")] {
            model.config.provider = shown
            SettingsImage.render(model, page: .ai, keySheet: sheet, to: output.appendingPathComponent("settings-provider-\(name).png"),
                                 appearance: dark ? .darkAqua : .aqua) { RunLoop.main.run(until: Date().addingTimeInterval($0)) }
        }
        model.config.provider = provider
        // Bedrock with a role, an SSO profile, and an SSO sign-in that expired.
        AWSProfileSamples.render(model, to: output, appearance: dark ? .darkAqua : .aqua)
        // Input with its options under the chips (each input's options under its name).
        for input in model.config.inputs {
            SettingsImage.render(model, page: .input, inputTab: input,
                                 to: output.appendingPathComponent("settings-input-\(input.rawValue).png"),
                                 appearance: dark ? .darkAqua : .aqua) { RunLoop.main.run(until: Date().addingTimeInterval($0)) }
        }
        exit(0)
    }
}
