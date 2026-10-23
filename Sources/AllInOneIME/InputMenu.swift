import AllInOneIMECore
import AllInOneIMERime
import AppKit
import InputMethodKit

/// The input menu (the menu bar's input source menu while a field has the focus): the settings, the model, the languages,
/// the rewrite styles, this app's own settings (AppProfiles.swift), the Rime folder, a report, updates. Its actions write
/// the config file and tell the field's session (`applySettings`).
extension AllInOneIMEInputController {
    @MainActor
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let config = LiveConfig.currentIfValid
        UIText.choice = services.loadSettings().uiLanguage  // the menu can open before any text field in this process
        let settings = NSMenuItem(title: tr("设置…", "Settings…"), action: #selector(showPreferences(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let model = config.map { tr("模型：", "Model: ") + ($0.settings(for: $0.provider).model ?? "") } ?? tr("配置文件有误", "The config file has an error")
        let info = NSMenuItem(title: model, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        menu.addItem(.separator())
        // Output and input languages in submenus like the styles: each lists only the languages the user
        // added (a new user has one), with "Add Languages…" opening the settings.
        let current = config ?? .default
        // @translate writes in every language added, in this order (one picked here moves to the front).
        let outputItem = NSMenuItem(title: tr("翻译成：", "Translate to: ") + current.outputLanguages.map(UIText.name).joined(separator: tr("、", ", ")),
                                    action: nil, keyEquivalent: "")
        let outputs = NSMenu()
        for language in current.outputLanguages {
            let item = NSMenuItem(title: UIText.name(language), action: #selector(setOutputLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.code
            item.state = .on
            item.isEnabled = config != nil  // don't overwrite a config file that failed to parse
            outputs.addItem(item)
        }
        outputs.addItem(.separator())
        let addOutput = NSMenuItem(title: tr("添加 / 排序语言…", "Add or Reorder Languages…"), action: #selector(showPreferences(_:)), keyEquivalent: "")
        addOutput.target = self
        addOutput.representedObject = SettingsPage.writing.rawValue
        outputs.addItem(addOutput)
        outputItem.submenu = outputs
        menu.addItem(outputItem)

        let inputNames = current.inputLanguages.map { SessionText.inputName($0, language: UIText.language) }
        let inputItem = NSMenuItem(title: tr("输入：", "Input: ") + inputNames.joined(separator: " + "),
                                   action: nil, keyEquivalent: "")
        let inputs = NSMenu()
        // The added input languages, the default one checked (a new text field starts in it).
        for language in current.inputLanguages {
            // One whose pack isn't there yet can't be typed: shown, greyed, with why.
            let usable = LanguagePackManager.shared.isUsable(language)
            let title = SessionText.inputName(language, language: UIText.language) + (usable ? "" : tr("（还没有语言包）", " (no language pack yet)"))
            let item = NSMenuItem(title: title, action: #selector(setDefaultInput(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = current.defaultInput == language ? .on : .off
            item.isEnabled = config != nil && usable
            inputs.addItem(item)
        }
        inputs.addItem(.separator())
        if current.inputLanguages.count > 1 {
            let shiftNote = NSMenuItem(title: tr("✓ 是默认；Shift 切换", "✓ is the default; Shift switches"), action: nil, keyEquivalent: "")
            shiftNote.isEnabled = false
            inputs.addItem(shiftNote)
        }
        let addInput = NSMenuItem(title: tr("添加语言…", "Add Languages…"), action: #selector(showPreferences(_:)), keyEquivalent: "")
        addInput.target = self
        addInput.representedObject = SettingsPage.input.rawValue
        inputs.addItem(addInput)
        inputItem.submenu = inputs
        menu.addItem(inputItem)

        // The styles in a submenu: six rows with summaries made the menu too long. Its title says which
        // are on, so the menu still shows the state without opening it.
        let enabledStyles = RewriteStyle.resolve(config?.rewriteStyles ?? Config.default.rewriteStyles)
        let enabled = Set(enabledStyles.map(\.name))
        let on = enabledStyles.map(UIText.name).joined(separator: tr("、", ", "))
        let stylesItem = NSMenuItem(title: tr("改写风格", "Rewrite Styles") + tr("：", ": ") + (on.isEmpty ? tr("无", "none") : on),
                                    action: nil, keyEquivalent: "")
        let styles = NSMenu()
        for style in RewriteStyle.catalog {
            let item = NSMenuItem(title: UIText.name(style) + tr("　", "  ") + UIText.summary(style),
                                  action: #selector(toggleStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.name
            item.state = enabled.contains(style.name) ? .on : .off
            item.isEnabled = config != nil  // don't overwrite a config file that failed to parse
            styles.addItem(item)
        }
        stylesItem.submenu = styles
        menu.addItem(stylesItem)
        let improveTranslates = NSMenuItem(title: tr("@improve 同时翻译", "@improve Also Translates")
                                                .replacingOccurrences(of: "@", with: config?.commandTrigger ?? "@"),
                                           action: #selector(toggleImproveTranslates(_:)), keyEquivalent: "")
        improveTranslates.target = self
        improveTranslates.state = current.improveTranslates ? .on : .off
        improveTranslates.isEnabled = config != nil
        menu.addItem(improveTranslates)
        // The app being typed in: no AI, typing out, the language it starts in (`AppProfile`).
        if let appItem = appMenuItem(config: config, app: activeApp ?? appID) { menu.addItem(appItem) }
        menu.addItem(.separator())
        let rimeDir = NSMenuItem(title: tr("打开 Rime 用户目录", "Open Rime User Folder"), action: #selector(openRimeDirectory(_:)),
                                 keyEquivalent: "")
        rimeDir.target = self
        menu.addItem(rimeDir)
        let deploy = NSMenuItem(title: tr("重新部署词库", "Redeploy Dictionaries"), action: #selector(redeploy(_:)), keyEquivalent: "")
        deploy.target = self
        menu.addItem(deploy)
        menu.addItem(.separator())
        // GitHub's page for a new issue, with the versions and settings that help (`IssueReport`).
        let report = NSMenuItem(title: tr("报告问题…", "Report an Issue…"), action: #selector(reportIssue(_:)), keyEquivalent: "")
        report.target = self
        menu.addItem(report)
        // Settings → About, checking there (or, with a new version known, offering it).
        let newer = UpdateController.shared.available?.version
        let update = NSMenuItem(title: newer.map { tr("更新到 \($0)…", "Update to \($0)…") } ?? tr("检查更新…", "Check for Updates…"),
                                action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        return menu
    }

    /// IMK hands menu actions an info dictionary holding the chosen item (a plain NSMenuItem when
    /// called directly).
    static func menuItem(from sender: Any?) -> NSMenuItem? {
        if let item = sender as? NSMenuItem { return item }
        guard let info = sender as? NSDictionary else { return nil }
        return info[kIMKCommandMenuItemName as Any] as? NSMenuItem
    }

    @objc func toggleStyle(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard let name = Self.menuItem(from: sender)?.representedObject as? String else {
                log.error("style menu action without a style")
                return
            }
            do {
                var config = try Config.load()
                config.rewriteStyles = SessionText.toggled(name, in: config.rewriteStyles)
                try config.write()
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                log.notice("rewrite styles now \(config.rewriteStyles.joined(separator: ","), privacy: .public)")
            } catch {
                log.error("could not update rewrite styles: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Turns a preset on or off, keeping the user's order (`SessionText.toggled`).
    static func toggled(_ name: String, in current: [String]) -> [String] { SessionText.toggled(name, in: current) }

    @objc func setOutputLanguage(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard let raw = Self.menuItem(from: sender)?.representedObject as? String else {
                log.error("output menu action without a language")
                return
            }
            do {
                var config = try Config.load()
                config.outputLanguage = OutputLanguage(raw)
                config.normalizeLanguages()
                try config.write()
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                log.notice("output language now \(raw, privacy: .public)")
            } catch {
                log.error("could not update the output language: \(String(describing: error), privacy: .public)")
            }
        }
    }


    @objc func toggleImproveTranslates(_ sender: Any?) {
        MainActor.assumeIsolated {
            do {
                var config = try Config.load()
                config.improveTranslates.toggle()
                try config.write()
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                log.notice("@improve also translates: \(config.improveTranslates, privacy: .public)")
            } catch {
                log.error("could not update @improve: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Makes an added input language the default: a new text field starts in it.
    @objc func setDefaultInput(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard let raw = Self.menuItem(from: sender)?.representedObject as? String, let language = Language(rawValue: raw) else {
                log.error("input menu action without a language")
                return
            }
            do {
                var config = try Config.load()
                config.defaultInput = language
                config.normalizeLanguages()
                try config.write()
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
                log.notice("default input now \(config.defaultInput.rawValue, privacy: .public)")
                applySettings()
            } catch {
                log.error("could not update the default input: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// `languages` with `language` removed, or added at the end; the last one stays (`SessionText.toggled`).
    static func toggled(_ language: Language, in languages: [Language]) -> [Language] { SessionText.toggled(language, in: languages) }

    @objc func openConfig(_ sender: Any?) {
        MainActor.assumeIsolated { Self.openConfigFile() }
    }

    override func showPreferences(_ sender: Any!) {
        MainActor.assumeIsolated {
            perform(composer.commitAll(), client: nil)  // the window takes focus from the text field
            // "Add Languages…" opens the page with the languages; Settings… opens on Assistant.
            if let page = (Self.menuItem(from: sender)?.representedObject as? String).flatMap(SettingsPage.init(rawValue:)) {
                SettingsWindow.shared.show(page: page)
            } else {
                SettingsWindow.shared.show()
            }
        }
    }

    /// The input menu's "Check for Updates…": Settings → About, which checks (or shows the update already found).
    @objc func checkForUpdates(_ sender: Any?) {
        MainActor.assumeIsolated {
            perform(composer.commitAll(), client: nil)  // the window takes focus from the text field
            SettingsWindow.shared.show(page: .about)
            if UpdateController.shared.available == nil { UpdateController.shared.check(userInitiated: true) }
        }
    }

    /// The input menu's "Report an Issue…": the new-issue page in the browser (the browser takes the focus).
    @objc func reportIssue(_ sender: Any?) {
        MainActor.assumeIsolated {
            perform(composer.commitAll(), client: nil)
            let config = services.loadSettings()
            NSWorkspace.shared.open(IssueReport(title: "", diagnostics: IssueReporting.diagnostics(
                config: config, plugins: LivePlugins.current().count, extensions: services.loadExtensions(config, false).commands.count)).url)
        }
    }

    @objc func openRimeDirectory(_ sender: Any?) {
        MainActor.assumeIsolated {
            if let dir = RimeService.shared.userDataDir { NSWorkspace.shared.open(dir) }
        }
    }

    @objc func redeploy(_ sender: Any?) {
        MainActor.assumeIsolated {
            perform(composer.commitAll(), client: nil)
            session.dropEngine()
            RimeService.shared.redeploy()
        }
    }

    @MainActor
    static func openConfigFile() {
        let url = Config.defaultURL
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try Config.default.write(to: url)
            } catch {
                log.error("could not create config: \(String(describing: error), privacy: .public)")
            }
        }
        if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
