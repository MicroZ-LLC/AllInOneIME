import AllInOneIMECore
import AppKit

extension SelfTest {
    /// `@translate` with nothing to translate into but the sentence's own language (a new user whose Mac has no other
    /// language), through the fake field: no request, and nothing opens by itself; the notice names the page where
    /// languages are added, offers ⏎, and stays. ⏎ on it puts the sentence in as typed (never "@translate …") and opens
    /// Settings on Translate & Rewrite pointing at the languages; in Chinese too, and Space opens it as well. Then with the
    /// real settings window, on a config of its own (English and Chinese typed, English out): ⏎ opens it on that page in
    /// front, from closed, from another page behind a window of the self-test's, and from the Dock (English alone then);
    /// its Add… menu offers every other language (Chinese, typed, too), and one picked is saved at once: ⏎ on `@translate`
    /// then sends it, into that language, without a restart (the page as it arrives: settings-no-translation-target*.png).
    /// Translate as You Type with English alone doesn't turn on, and says where to add one. Nothing is sent off the Mac (a
    /// canned on-device stand-in answers), so secure input held by another app (the lock screen) doesn't stop it: the
    /// controller is told it's off.
    static func testNothingToTranslateInto(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, in directory: URL) {
        section("@translate with nothing to translate into", needs: SecureInput.ownerPID() == -1 ? .composing : [])
        let saved = (settings: settings, load: controller.loadSettings, open: controller.openSettings, converter: controller.converter,
                     secure: controller.secureInputActive, url: Config.selfTestURL, choice: UIText.choice)
        let scratch = directory.appendingPathComponent("no-target-config.json")
        defer {
            controller.commitComposition(client)
            NSApp.windows.filter { $0.title == SettingsWindow.title && ($0.isVisible || $0.isMiniaturized) }.forEach { $0.close() }
            (settings, controller.loadSettings, controller.openSettings, controller.converter) = (saved.settings, saved.load, saved.open, saved.converter)
            (controller.secureInputActive, Config.selfTestURL, UIText.choice) = (saved.secure, saved.url, saved.choice)
            try? FileManager.default.removeItem(at: scratch)
            controller.applySettings()
            controller.composer.setInputMode(settings.defaultInput)
        }
        controller.secureInputActive = { false }
        let model = CannedTranslationModel(answers: [:])
        controller.converter = Converter(loadConfig: {
            var config = controller.loadSettings()
            config.provider = .apple  // the canned model's place
            return config
        }, appleModel: model)
        func translate(_ text: String) {
            controller.commitComposition(client)
            controller.composer.setInputMode(.english)
            press(controller, client, "@", code: 0x13, flags: .shift)
            type("t", controller, client)
            press(controller, client, "\t", code: VirtualKey.tab)
            type(text, controller, client)
            _ = enter(controller, client)
        }

        // The notice and ⏎ on it, the settings recorded.
        var opened: [String] = []
        controller.openSettings = { page, spot in opened.append(page.rawValue + (spot.map { "/" + $0.rawValue } ?? "")) }
        settings = (try? Config.load()) ?? .default
        (settings.typeOut, settings.typeOutMistakes) = (false, false)  // inserted at once, no typos
        settings.setOrder([Language.english])
        settings.setOrder([OutputLanguage.english])
        controller.loadSettings = { SelfTest.settings }
        for (ui, key) in [("en", "⏎"), ("zh", "Space")] {
            settings.uiLanguage = ui
            controller.applySettings()
            opened.removeAll()
            let before = (client.inserted, model.requests.count)
            translate("good morning")
            let page = SettingsPage.writing.title
            _ = pump(timeout: 2.5) { !opened.isEmpty }  // the notice up a while: nothing opens meanwhile
            let shown = controller.panelModel()
            let line = "\(shown.status)"
            check(opened.isEmpty && model.requests.count == before.1 && client.inserted == before.0 && client.marked.contains("good morning"),
                  "[\(ui)] ⏎: nothing sent and nothing opens by itself; the draft stays as it is (\(opened), marked '\(client.marked)')")
            check(line.contains(page) && line.contains("⏎") && line.contains(tr("还没有要翻译成的语言", "No language to translate into yet"))
                  && shown.footer.hasPrefix(tr("空格 / ⏎ 打开设置", "Space / ⏎ open the settings")),
                  "[\(ui)] …the notice, still up, names the page and offers ⏎ (\(line) | \(shown.footer))")
            if key == "⏎" { _ = enter(controller, client) } else { _ = space(controller, client) }
            check(opened == ["writing/outputLanguages"] && client.inserted.last == "good morning" && client.marked.isEmpty
                  && controller.composer.phase == .idle,
                  "[\(ui)] \(key) on it opens Settings on \(page) at the languages; the sentence goes in as typed (\(opened), \(client.inserted.last ?? "-"))")
        }

        // The real settings window, on a config of its own.
        var own = Config.default
        own.provider = .apple
        own.typeOut = false
        own.setOrder([Language.english, .chinese])
        own.setOrder([OutputLanguage.english])
        own.uiLanguage = "en"
        guard (try? own.write(to: scratch)) != nil else { return check(false, "the settings window's own config at \(scratch.path)") }
        Config.selfTestURL = scratch
        controller.loadSettings = {
            var config = LiveConfig.current
            config.typeOut = false
            return config
        }
        controller.openSettings = { page, spot in
            opened.append(page.rawValue + (spot.map { "/" + $0.rawValue } ?? ""))
            SettingsWindow.shared.show(page: page, spot: spot)
        }
        UIText.choice = "en"
        controller.applySettings()
        let front = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        front.title = "AllInOneIME self-test (in front)"
        front.isReleasedWhenClosed = false
        defer { front.close() }
        func settingsWindow() -> NSWindow? { NSApp.windows.first { $0.title == SettingsWindow.title && $0.isVisible } }
        func popups(_ view: NSView) -> [NSPopUpButton] { ((view as? NSPopUpButton).map { [$0] } ?? []) + view.subviews.flatMap(popups) }
        /// The page's first Add… (Translate & Rewrite's languages there).
        func firstAdd() -> NSPopUpButton? {
            let all = settingsWindow()?.contentView.map(popups) ?? []
            return all.filter { $0.title == tr("添加…", "Add…") }.max { $0.convert($0.bounds, to: nil).maxY < $1.convert($1.bounds, to: nil).maxY }
        }
        /// What the page's first Add… lists, opened as a click opens it (read while it shows); `pick` chosen from it.
        func addMenu(picking pick: String? = nil) -> [String] {
            guard let add = firstAdd() else { return [] }
            var listed: [String] = []
            let tracking = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
                MainActor.assumeIsolated {
                    guard let menu = note.object as? NSMenu else { return }
                    let read = Timer(timeInterval: 0.3, repeats: false) { _ in
                        MainActor.assumeIsolated {
                            listed = menu.items.map(\.title).filter { !$0.isEmpty }
                            menu.cancelTracking()
                            if let pick, let index = menu.items.firstIndex(where: { $0.title == pick }) { menu.performActionForItem(at: index) }
                        }
                    }
                    RunLoop.main.add(read, forMode: .common)
                }
            }
            let giveUp = Timer(timeInterval: 5, repeats: false) { _ in MainActor.assumeIsolated { add.menu?.cancelTracking() } }
            RunLoop.main.add(giveUp, forMode: .common)
            add.performClick(nil)
            giveUp.invalidate()
            NotificationCenter.default.removeObserver(tracking)
            _ = pump(timeout: 0.3) { false }
            return listed
        }
        /// The window frontmost among the windows on screen at the normal level, other apps' too (focused or not).
        func inFront(_ window: NSWindow) -> Bool {
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            let first = list.first { ($0[kCGWindowLayer as String] as? Int) == 0 }
            return (first?[kCGWindowNumber as String] as? Int) == window.windowNumber
        }
        let others = OutputLanguage.catalog.filter { $0 != .english }.map(UIText.name)
        for start in ["closed", "on General, behind another window", "in the Dock"] {
            if start != "closed" {
                SettingsWindow.shared.show(page: .general)
                _ = pump(timeout: 0.8) { false }
                if start == "in the Dock" {
                    settingsWindow()?.miniaturize(nil)
                    _ = pump(timeout: 2) { settingsWindow() == nil }
                }
            }
            front.orderFrontRegardless()
            _ = pump(timeout: 0.3) { false }
            let shownBefore = settingsWindow() != nil
            opened.removeAll()
            translate("good morning")
            _ = pump(timeout: 0.5) { false }
            let early = settingsWindow() != nil && !shownBefore
            _ = enter(controller, client)
            _ = pump(timeout: 1.5) { firstAdd() != nil && settingsWindow().map(inFront) == true }
            let window = settingsWindow()
            check(window.map(inFront) == true && window.flatMap { NSApp.orderedWindows.firstIndex(of: $0) } == 0 && !early
                  && opened == ["writing/outputLanguages"],
                  "settings \(start): only ⏎ on the notice shows them, in front of every window on screen (key: "
                      + "\(window?.isKeyWindow ?? false), active: \(NSApp.isActive))")
            let spot = SettingsWindow.shared.spot
            if start != "on General, behind another window", let view = window?.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                // The page as it arrives, outlined: settings-no-translation-target(-english-alone).png.
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = directory.appendingPathComponent("settings-no-translation-target\(start == "closed" ? "" : "-english-alone").png")
                if (try? rep.representation(using: .png, properties: [:])?.write(to: url)) != nil { print("  snapshot \(url.path)") }
            }
            let pick = start == "closed" ? UIText.name(OutputLanguage("fr")) : nil
            let listed = addMenu(picking: pick)
            check(spot == .outputLanguages && listed == others,
                  "…on Translate & Rewrite, its Add… outlined, listing the \(others.count) other languages"
                      + (start == "closed" ? ", Chinese (typed here) too " : " ")
                      + "(\(spot?.rawValue ?? "no outline"); \(listed.count): \(listed.prefix(3))…)")
            if pick != nil {
                let added = pump(timeout: 2) { (try? Config.load(from: scratch))?.outputLanguages == [.english, OutputLanguage("fr")] }
                check(added && SettingsWindow.shared.spot == nil, "French picked there is saved at once, the outline gone "
                      + "(\((try? Config.load(from: scratch))?.outputLanguages.map(\.code) ?? []))")
                // @translate now: sent, into French, no restart.
                opened.removeAll()
                let asked = model.requests.count
                translate("good morning")
                _ = pump(timeout: 5) { model.requests.count > asked }
                let request = model.requests.dropFirst(asked).first
                check(opened.isEmpty && controller.composer.failureFixedIn == nil && request?.instructions.contains("French") == true,
                      "…and ⏎ on @translate then asks for French at once, no restart (\(model.requests.count - asked) request)")
                _ = escape(controller, client)
                _ = escape(controller, client)
                controller.commitComposition(client)
                // English alone, typed and translated into, for the next ways in: the page says to add another.
                own.setOrder([Language.english])
                own.setOrder([OutputLanguage.english])
                try? own.write(to: scratch)
            }
            settingsWindow()?.close()
            _ = pump(timeout: 0.3) { false }
        }

        // Translate as You Type with English alone: it doesn't turn on, and says where to add a language.
        var alone = own
        alone.setOrder([Language.english])
        try? alone.write(to: scratch)
        controller.applySettings()
        defer {
            TranslateModeShared.state = TranslateMode.State()
            controller.perform(controller.composer.setTranslateMode(nil), client: client)
            MenuBarIcon.shared.setTranslating(false)
            if let notice = controller.notice { controller.endNotice(notice) }
        }
        controller.toggleTranslateMode()
        let notice = controller.notice ?? "-"
        check(!TranslateModeShared.state.isOn && controller.composer.translateMode == nil && notice.contains(SettingsPage.writing.title),
              "Translate as You Type with English alone stays off, and says where to add one (\(notice))")
    }
}
