import Foundation

// Compiled-source test children for ReviewUI076AcceptanceTests, following StartWindowMacTests and Settings161MacTests:
// Sources/AllInOneIME and Sources/AllInOneIMEInstaller are executable targets and cannot be imported by the test target,
// so each is compiled once with SourceCompiler (its main.swift dispatch replaced by a harness) and run in an isolated
// temporary home with an in-memory keychain and stubbed Apple on-device model.

enum ReviewUI076AppChild {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static let report: Result<[String: String], Error> = Result { try run() }

    static func run() throws -> [String: String] {
        let executable = try compile()
        let result = try ReviewUI076Process.run(executable, [], repository: repository, timeout: 120)
        guard result.status == 0 else {
            throw Failure(description: "ReviewUI076 app child failed (exit \(result.status)):\n\(result.output)")
        }
        return ReviewUI076Process.values(result.output)
    }

    private static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("review076-app-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else {
            throw Failure(description: "main.swift: dispatch marker not found")
        }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try ("import SwiftUI\n" + String(main[..<cut.upperBound]) + ReviewUI076AppHarness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let executable = scratch.appendingPathComponent("review076-app")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else {
            let errors = swift.output.split(separator: "\n").filter { $0.contains("error:") }
            let detail = errors.isEmpty ? swift.output : errors.joined(separator: "\n")
            throw Failure(description: "compiling Sources/AllInOneIME with ReviewUI076 harness:\n\(detail)")
        }
        return executable
    }
}

enum ReviewUI076InstallerChild {
    static let repository = ReviewUI076AppChild.repository
    static let compiled: Result<URL, Error> = Result { try compile() }

    static func run(interface: String) throws -> [String: String] {
        let executable = try compiled.get()
        let result = try ReviewUI076Process.run(executable, [], repository: repository, timeout: 60) { home in
            let folder = home.appendingPathComponent(".config/allinoneime", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("{\"uiLanguage\": \"\(interface)\"}".utf8).write(to: folder.appendingPathComponent("config.json"))
        }
        guard result.status == 0 else {
            throw ReviewUI076AppChild.Failure(description: "ReviewUI076 installer child failed (exit \(result.status)):\n\(result.output)")
        }
        return ReviewUI076Process.values(result.output)
    }

    private static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("review076-installer-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIMEInstaller")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        guard let cut = main.range(of: "\n// MARK: Start\n", options: .backwards)
                ?? main.range(of: "\nswitch CommandLine.arguments", options: .backwards) else {
            throw ReviewUI076AppChild.Failure(description: "installer main.swift: start marker not found")
        }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.lowerBound]) + "\n" + harness).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let executable = scratch.appendingPathComponent("review076-installer")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else {
            throw ReviewUI076AppChild.Failure(description: "compiling Sources/AllInOneIMEInstaller:\n\(swift.output)")
        }
        return executable
    }

    private static let harness = #"""
func emit(_ key: String, _ value: String) {
    print("KV\t\(key)\t" + Data(value.utf8).base64EncodedString())
}
emit("PROBE", tr("取消", "Cancel"))
emit("ARGS_FRESH", Installer.settingsAppArguments(fresh: true).joined(separator: ","))
emit("ARGS_UPDATE", Installer.settingsAppArguments(fresh: false).joined(separator: ","))
emit("ADD_IN_START", Installer.addInStart)
emit("MANUAL_ADD_HINT", manualAddHint)
emit("INSTALLED_AT", Installer.installedDetails(trigger: "@"))
fflush(stdout)
exit(0)
"""#
}

enum ReviewUI076Process {
    static func values(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, fields[0] == "KV",
                  let decoded = Data(base64Encoded: fields[2]) else { continue }
            result[fields[1]] = String(decoding: decoded, as: UTF8.self)
        }
        return result
    }

    static func run(_ executable: URL, _ arguments: [String], repository: URL, timeout: TimeInterval,
                    prepare: (URL) throws -> Void = { _ in }) throws -> (status: Int32, output: String) {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("review076-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        try prepare(home)
        let log = fm.temporaryDirectory.appendingPathComponent("review076-\(UUID().uuidString).log")
        fm.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? fm.removeItem(at: log)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.environment = ProcessInfo.processInfo.environment.merging([
            "CFFIXED_USER_HOME": home.path,
            "HOME": home.path,
            "AWS_CONFIG_FILE": "/nonexistent",
            "AWS_SHARED_CREDENTIALS_FILE": "/nonexistent",
        ]) { $1 }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw ReviewUI076AppChild.Failure(description: "timed out: \(executable.lastPathComponent)\n"
                                              + ((try? String(contentsOf: log, encoding: .utf8)) ?? ""))
        }
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }
}

private enum ReviewUI076AppHarness {
    static let swift = #"""

// MARK: - ReviewUI076AcceptanceTests child (in place of main.swift's dispatch)

struct StubAppleModel: AppleModelBackend {
    var availability: AppleModelAvailability
    var contextSize: Int { 4096 }
    var supportedLanguages: Set<String> { ["en", "zh"] }
    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

Platform.current.secrets = .inMemory()
Platform.current.onDeviceModel = StubAppleModel(availability: .appleIntelligenceNotEnabled)
MainActor.assumeIsolated { SettingsModel.looksUpKeys = false }

@MainActor
enum ReviewUI076Child {
    static func emit(_ key: String, _ value: String) {
        print("KV\t\(key)\t" + Data(value.utf8).base64EncodedString())
        fflush(stdout)
    }

    static func pump(_ seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func views<T: NSView>(_ type: T.Type, in view: NSView?) -> [T] {
        guard let view else { return [] }
        return ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
    }

    static func allMenuItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(allMenuItems) ?? []) }
    }

    static func host<V: View>(_ view: V, size: NSSize) -> (NSWindow, NSView) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = host
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        pump(0.15)
        host.layoutSubtreeIfNeeded()
        return (window, host)
    }

    static func ax(_ node: NSObject, _ key: String) -> Any? {
        node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil
    }

    static func axNodes(_ root: NSObject) -> [NSObject] {
        var result: [NSObject] = []
        var seen: Set<ObjectIdentifier> = []
        func walk(_ node: NSObject, depth: Int) {
            guard depth < 40, seen.insert(ObjectIdentifier(node)).inserted else { return }
            result.append(node)
            let children = ((ax(node, "accessibilityChildren") as? [NSObject]) ?? [])
                + ((ax(node, "accessibilityRows") as? [NSObject]) ?? [])
            for child in children { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return result
    }

    static func texts(in window: NSWindow) -> [String] {
        var found = views(NSTextField.self, in: window.contentView).map(\.stringValue).filter { !$0.isEmpty }
        for node in axNodes(window) {
            for key in ["accessibilityValue", "accessibilityTitle", "accessibilityLabel"] {
                if let text = ax(node, key) as? String, !text.isEmpty { found.append(text) }
            }
        }
        return found
    }

    static func buttons(in window: NSWindow) -> [String] {
        let appKit = views(NSButton.self, in: window.contentView).compactMap { button -> String? in
            let title = button.title.isEmpty ? (button.accessibilityLabel() ?? button.accessibilityTitle() ?? "") : button.title
            return title.isEmpty ? nil : title
        }
        if !appKit.isEmpty { return appKit }
        return axNodes(window).compactMap { node -> String? in
            guard (ax(node, "accessibilityRole") as? String) == NSAccessibility.Role.button.rawValue else { return nil }
            let subrole = ax(node, "accessibilitySubrole") as? String
            if subrole == NSAccessibility.Subrole.closeButton.rawValue
                || subrole == NSAccessibility.Subrole.minimizeButton.rawValue
                || subrole == NSAccessibility.Subrole.zoomButton.rawValue
                || subrole == NSAccessibility.Subrole.fullScreenButton.rawValue {
                return nil
            }
            let title = (ax(node, "accessibilityTitle") as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (ax(node, "accessibilityLabel") as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? ""
            return title.isEmpty ? nil : title
        }
    }

    static func switches(in view: NSView) -> [NSControl] {
        let nsSwitches: [NSControl] = views(NSSwitch.self, in: view)
        if !nsSwitches.isEmpty { return nsSwitches }
        return views(NSButton.self, in: view).filter {
            $0.cell?.isKind(of: NSButtonCell.self) == true && ($0.title.isEmpty || $0.title == SettingsSpot.autocomplete.title)
        }
    }

    static func run() {
        let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
        guard !home.isEmpty,
              URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
                  .hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
            print("FAIL home outside test dir: \(NSHomeDirectory())")
            exit(3)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        _ = app.perform(Selector(("accessibilitySetValue:forAttribute:")), with: true as NSNumber, with: "AXEnhancedUserInterface")

        let homeURL = URL(fileURLWithPath: home, isDirectory: true)
        checkItem21(home: homeURL)
        checkItem22(home: homeURL)
        checkItem23(home: homeURL)
        checkItem24(home: homeURL)
        fflush(stdout)
        _exit(0)
    }

    static var configRevision = 0

    static func writeConfig(_ config: Config, to url: URL) {
        configRevision += 1
        Config.selfTestURL = url
        try? config.write(to: url)
        try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(configRevision))], ofItemAtPath: url.path)
    }

    static func freshDefaults(in home: URL) -> UserDefaults {
        UserDefaults(suiteName: home.appendingPathComponent("defaults-\(UUID().uuidString)").path) ?? .standard
    }

    // MARK: Item 21 — Input menu language links & SettingsSpot.page

    static func checkItem21(home: URL) {
        emit("21_OUTPUT_PAGE", SettingsSpot.outputLanguages.page.rawValue)
        emit("21_INPUT_PAGE", SettingsSpot.inputLanguages.page.rawValue)
        emit("21_COMMON_HAS_OUTPUT", SettingsPage.common.spots.contains(.outputLanguages) ? "1" : "0")
        emit("21_AI_HAS_OUTPUT", SettingsPage.ai.spots.contains(.outputLanguages) ? "1" : "0")
        emit("21_COMMON_HAS_INPUT", SettingsPage.common.spots.contains(.inputLanguages) ? "1" : "0")

        let controller = AllInOneIMEInputController(server: nil, delegate: nil, client: nil) ?? AllInOneIMEInputController()
        controller.clientOverride = FakeTextClient()
        let url = home.appendingPathComponent("item21-config.json")
        for (lang, addOutputTitle, addInputTitle, settingsTitle) in [
            ("en", "Add or Reorder Languages…", "Add Languages…", "Settings…"),
            ("zh", "添加 / 排序语言…", "添加语言…", "设置…"),
        ] {
            var config = Config.default
            config.uiLanguage = lang
            writeConfig(config, to: url)
            UIText.choice = lang
            let menu = controller.makeMenu()
            let items = allMenuItems(menu)
            if let addOutput = items.first(where: { $0.title == addOutputTitle }) {
                emit("21_\(lang)_ADD_OUTPUT_ACTION", addOutput.action.map(NSStringFromSelector) ?? "")
                emit("21_\(lang)_ADD_OUTPUT_OBJ", (addOutput.representedObject as? String) ?? "")
                let resolved = (addOutput.representedObject as? String).flatMap(SettingsSpot.init(rawValue:))
                emit("21_\(lang)_ADD_OUTPUT_RESOLVED_PAGE", resolved?.page.rawValue ?? "")
                let direct = AllInOneIMEInputController.menuItem(from: addOutput) === addOutput
                let wrapped = AllInOneIMEInputController.menuItem(from: [kIMKCommandMenuItemName: addOutput] as NSDictionary) === addOutput
                emit("21_\(lang)_UNWRAP_OK", (direct && wrapped) ? "1" : "0")
            }
            if let addInput = items.first(where: { $0.title == addInputTitle }) {
                emit("21_\(lang)_ADD_INPUT_ACTION", addInput.action.map(NSStringFromSelector) ?? "")
                emit("21_\(lang)_ADD_INPUT_OBJ", (addInput.representedObject as? String) ?? "")
                let resolved = (addInput.representedObject as? String).flatMap(SettingsSpot.init(rawValue:))
                emit("21_\(lang)_ADD_INPUT_RESOLVED_PAGE", resolved?.page.rawValue ?? "")
            }
            if let settings = items.first(where: { $0.title == settingsTitle }) {
                emit("21_\(lang)_SETTINGS_OBJ_NIL", settings.representedObject == nil ? "1" : "0")
            }
        }

        // Exercise showPreferences(_:) end-to-end with the menu items produced by makeMenu().
        var config = Config.default
        config.uiLanguage = "en"
        writeConfig(config, to: url)
        UIText.choice = "en"
        let menu = controller.makeMenu()
        let items = allMenuItems(menu)
        var shownPages: [String] = []
        let observer = NotificationCenter.default.addObserver(forName: .allInOneIMEShowSettingsPage, object: nil, queue: .main) { note in
            if let page = note.userInfo?["page"] as? String { shownPages.append(page) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        if let addOutput = items.first(where: { $0.title == "Add or Reorder Languages…" }) {
            shownPages = []
            controller.showPreferences([kIMKCommandMenuItemName: addOutput] as NSDictionary)
            emit("21_SHOW_OUTPUT_PAGE", shownPages.last ?? "")
            emit("21_SHOW_OUTPUT_SPOT", SettingsWindow.shared.spot?.rawValue ?? "")
        }
        if let addInput = items.first(where: { $0.title == "Add Languages…" }) {
            shownPages = []
            controller.showPreferences(addInput)
            emit("21_SHOW_INPUT_PAGE", shownPages.last ?? "")
            emit("21_SHOW_INPUT_SPOT", SettingsWindow.shared.spot?.rawValue ?? "")
        }
    }

    // MARK: Item 22 — Start step 2 UI & StartModel.aiReady transitions

    static func checkItem22(home: URL) {
        emit("22_GOOGLE_ENABLED", HostedService.googleEnabled ? "1" : "0")
        let ours = InputSourceRegistrar.sourceID
        let url = home.appendingPathComponent("item22-config.json")

        for (lang, googleTitle, emailTitle, ownTitle, laterTitle) in [
            ("en", "Sign in with Google", "Sign in / Sign up with Email", "Use My Own AI…", "Later"),
            ("zh", "用 Google 登录", "用邮箱登录 / 注册", "使用我自己的 AI…", "稍后再说"),
        ] {
            var config = Config.default
            config.uiLanguage = lang
            writeConfig(config, to: url)
            UIText.choice = lang
            let model = StartModel(defaults: freshDefaults(in: home), ourSourceID: ours)
            model.start(currentSourceID: ours) // step 2
            let settings = SettingsModel(configURL: url, persists: false)
            let (window, _) = host(StartView(model: model, settings: settings), size: NSSize(width: 560, height: 440))
            let titles = buttons(in: window)
            emit("22_\(lang)_BUTTONS", titles.joined(separator: "|"))
            emit("22_\(lang)_GOOGLE_COUNT", "\(titles.filter { $0 == googleTitle }.count)")
            emit("22_\(lang)_EMAIL_COUNT", "\(titles.filter { $0 == emailTitle }.count)")
            emit("22_\(lang)_OWN_COUNT", "\(titles.filter { $0 == ownTitle }.count)")
            emit("22_\(lang)_LATER_COUNT", "\(titles.filter { $0 == laterTitle }.count)")
            window.close()
        }

        // Direct StartModel.aiReady transitions at step 1, step 2, step 3.
        func trace(_ block: (StartModel) -> Void) -> Int {
            let model = StartModel(defaults: freshDefaults(in: home), ourSourceID: ours)
            block(model)
            return model.step
        }
        emit("22_STEP1_AIREADY_TRUE", "\(trace { $0.start(currentSourceID: "com.apple.keylayout.ABC"); $0.aiReady(true) })")
        emit("22_STEP2_AIREADY_FALSE", "\(trace { $0.start(currentSourceID: ours); $0.aiReady(false) })")
        emit("22_STEP2_AIREADY_TRUE", "\(trace { $0.start(currentSourceID: ours); $0.aiReady(true) })")
        emit("22_STEP3_AIREADY_FALSE", "\(trace { $0.start(currentSourceID: ours); $0.later(); $0.aiReady(false) })")

        // Exercise AIFacts.status(config.ai, config: config).isReady -> StartModel.aiReady for every AI type.
        func stepAfter(choice: AIChoice, facts: AIFacts, awsProfile: String = "default") -> Int {
            var config = Config.default
            config.awsProfile = awsProfile
            config.ai = choice
            let model = StartModel(defaults: freshDefaults(in: home), ourSourceID: ours)
            model.start(currentSourceID: ours)
            model.aiReady(facts.status(config.ai, config: config).isReady)
            return model.step
        }

        for agent in SessionAgent.allCases {
            emit("22_CLI_\(agent.rawValue)_READY", "\(stepAfter(choice: .cli(agent), facts: AIFacts(sessions: [agent: .ready])))")
            emit("22_CLI_\(agent.rawValue)_SIGNEDOUT", "\(stepAfter(choice: .cli(agent), facts: AIFacts(sessions: [agent: .signedOut])))")
            emit("22_CLI_\(agent.rawValue)_UNKNOWN", "\(stepAfter(choice: .cli(agent), facts: AIFacts(sessions: [agent: .unknown])))")
            emit("22_CLI_\(agent.rawValue)_NOTINSTALLED", "\(stepAfter(choice: .cli(agent), facts: AIFacts(sessions: [agent: .notInstalled])))")
        }
        for provider in [Provider.anthropic, .openai, .gemini] {
            emit("22_KEY_\(provider.rawValue)_SAVED", "\(stepAfter(choice: .provider(provider), facts: AIFacts(keys: [provider: .saved(ending: "1234")])))")
            emit("22_KEY_\(provider.rawValue)_SHELL", "\(stepAfter(choice: .provider(provider), facts: AIFacts(keys: [provider: .shell("API_KEY")])))")
            emit("22_KEY_\(provider.rawValue)_NONE", "\(stepAfter(choice: .provider(provider), facts: AIFacts(keys: [provider: .missing])))")
        }
        emit("22_APPLE_AVAILABLE", "\(stepAfter(choice: .provider(.apple), facts: AIFacts(apple: .available)))")
        emit("22_APPLE_NOTENABLED", "\(stepAfter(choice: .provider(.apple), facts: AIFacts(apple: .appleIntelligenceNotEnabled)))")
        emit("22_AWS_READY", "\(stepAfter(choice: .provider(.bedrock), facts: AIFacts(awsProfiles: [AWSProfileSummary(name: "default", region: "us-west-2", kind: .staticKeys)])))")
        emit("22_AWS_NOCREDS", "\(stepAfter(choice: .provider(.bedrock), facts: AIFacts(awsProfiles: [AWSProfileSummary(name: "default", region: "us-west-2", kind: .noCredentials)])))")
        emit("22_AWS_MISSING", "\(stepAfter(choice: .provider(.bedrock), facts: AIFacts(awsProfiles: [])))")
        emit("22_HOSTED_READY", "\(stepAfter(choice: .provider(.hosted), facts: AIFacts(hostedSignedIn: true)))")
        emit("22_HOSTED_SIGNEDOUT", "\(stepAfter(choice: .provider(.hosted), facts: AIFacts(hostedSignedIn: false)))")
    }

    // MARK: Item 23 — Start step 1 updates when input source is added

    static func checkItem23(home: URL) {
        emit("23_KEYBOARD_URL", StartView.keyboardSettings?.absoluteString ?? "")
        let ours = InputSourceRegistrar.sourceID
        let url = home.appendingPathComponent("item23-config.json")

        for (lang, keyboardBtn, addHeading, switchHeading) in [
            ("en", "Open Keyboard Settings", "Add AllInOneIME first", "Switch to AllInOneIME"),
            ("zh", "打开键盘设置", "先添加 AllInOneIME", "先切到 AllInOneIME"),
        ] {
            var config = Config.default
            config.uiLanguage = lang
            writeConfig(config, to: url)
            UIText.choice = lang
            let model = StartModel(defaults: freshDefaults(in: home), ourSourceID: ours)
            model.start(currentSourceID: "com.apple.keylayout.ABC")
            model.showSourceName("ABC")
            model.inputSourceAdded(false)
            emit("23_\(lang)_NOT_ADDED_STATE", "\(model.step):\(model.sourceAdded ? 1 : 0)")

            let settings = SettingsModel(configURL: url, persists: false)
            let (window, view) = host(StartView(model: model, settings: settings), size: NSSize(width: 560, height: 440))
            let beforeButtons = buttons(in: window)
            let beforeTexts = texts(in: window)
            emit("23_\(lang)_BEFORE_HAS_KB_BTN", beforeButtons.contains(keyboardBtn) ? "1" : "0")
            emit("23_\(lang)_BEFORE_HAS_ADD_TITLE", beforeTexts.contains(addHeading) ? "1" : "0")
            emit("23_\(lang)_BEFORE_HAS_SWITCH_TITLE", beforeTexts.contains(switchHeading) ? "1" : "0")

            model.inputSourceAdded(true)
            pump(0.15)
            view.layoutSubtreeIfNeeded()
            emit("23_\(lang)_ADDED_STATE", "\(model.step):\(model.sourceAdded ? 1 : 0)")
            let afterButtons = buttons(in: window)
            let afterTexts = texts(in: window)
            emit("23_\(lang)_AFTER_HAS_KB_BTN", afterButtons.contains(keyboardBtn) ? "1" : "0")
            emit("23_\(lang)_AFTER_HAS_SWITCH_TITLE", afterTexts.contains(switchHeading) ? "1" : "0")
            emit("23_\(lang)_AFTER_HAS_ADD_TITLE", afterTexts.contains(addHeading) ? "1" : "0")

            model.inputSourceAdded(false)
            model.inputSourceChanged(to: ours)
            emit("23_\(lang)_SWITCHED_STATE", "\(model.step):\(model.sourceAdded ? 1 : 0)")
            window.close()
        }
    }

    // MARK: Item 24 — CLI Autocomplete state & provider note in both languages

    static func checkItem24(home: URL) {
        let url = home.appendingPathComponent("item24-config.json")

        // 1. Provider note via tr in both languages and with custom trigger.
        for lang in ["en", "zh"] {
            UIText.choice = lang
            UIText.commandTrigger = "@"
            emit("24_\(lang)_NOTE_CLI_AT", SettingsSpot.providerNote(cli: true))
            emit("24_\(lang)_NOTE_PROVIDER", SettingsSpot.providerNote(cli: false))
            UIText.commandTrigger = "~"
            emit("24_\(lang)_NOTE_CLI_TILDE", SettingsSpot.providerNote(cli: true))
        }
        UIText.commandTrigger = "@"

        // 2. Settings → Common Autocomplete switch with CLI chosen & no faster AI, and with faster AI.
        for lang in ["en", "zh"] {
            Platform.current.onDeviceModel = StubAppleModel(availability: .appleIntelligenceNotEnabled)
            var config = Config.default
            config.uiLanguage = lang
            config.provider = .openai
            config.ai = .cli(.claude)
            config.autocomplete = true
            writeConfig(config, to: url)
            UIText.choice = lang

            let model = SettingsModel(configURL: url, persists: true)
            model.refreshKeys()
            emit("24_\(lang)_NOFAST_FASTCONFIG_NIL", model.fastConfig == nil ? "1" : "0")

            let (window, view) = host(
                Form { SettingsView(model: model, page: .common).autocompleteSection }.formStyle(.grouped),
                size: NSSize(width: 600, height: 260)
            )
            let toggle = switches(in: view).first
            let isOn: Bool = {
                if let sw = toggle as? NSSwitch { return sw.state == .on }
                if let btn = toggle as? NSButton { return btn.state == .on }
                return true
            }()
            let isEnabled = toggle?.isEnabled ?? true
            emit("24_\(lang)_NOFAST_FOUND_TOGGLE", toggle != nil ? "1" : "0")
            emit("24_\(lang)_NOFAST_TOGGLE_ON", isOn ? "1" : "0")
            emit("24_\(lang)_NOFAST_TOGGLE_ENABLED", isEnabled ? "1" : "0")
            emit("24_\(lang)_NOFAST_CONFIG_KEPT", model.config.autocomplete ? "1" : "0")
            let disk = (try? Config.load(from: url))?.autocomplete ?? false
            emit("24_\(lang)_NOFAST_DISK_KEPT", disk ? "1" : "0")
            let allTexts = texts(in: window).joined(separator: "\n")
            emit("24_\(lang)_NOFAST_TEXT", allTexts)
            window.close()

            // With a faster AI available (Apple Intelligence available), the same saved autocomplete setting shows on & enabled.
            Platform.current.onDeviceModel = StubAppleModel(availability: .available)
            let modelFast = SettingsModel(configURL: url, persists: false)
            emit("24_\(lang)_WITHFAST_FASTCONFIG_PROVIDER", modelFast.fastConfig?.provider.rawValue ?? "")
            let (fastWindow, fastView) = host(
                Form { SettingsView(model: modelFast, page: .common).autocompleteSection }.formStyle(.grouped),
                size: NSSize(width: 600, height: 260)
            )
            let fastToggle = switches(in: fastView).first
            let fastOn: Bool = {
                if let sw = fastToggle as? NSSwitch { return sw.state == .on }
                if let btn = fastToggle as? NSButton { return btn.state == .on }
                return false
            }()
            emit("24_\(lang)_WITHFAST_TOGGLE_ON", fastOn ? "1" : "0")
            emit("24_\(lang)_WITHFAST_TOGGLE_ENABLED", (fastToggle?.isEnabled ?? false) ? "1" : "0")
            fastWindow.close()

            // Rendered Settings → AI providerSection displays the CLI note beside the AI cards.
            Platform.current.onDeviceModel = StubAppleModel(availability: .appleIntelligenceNotEnabled)
            let (aiWindow, aiView) = host(
                Form { SettingsView(model: model, page: .ai).providerSection }.formStyle(.grouped),
                size: NSSize(width: 720, height: 600)
            )
            emit("24_\(lang)_AI_HEADER_TEXT", texts(in: aiWindow).joined(separator: "\n"))
            aiWindow.close()
        }

        // 3. Input menu autocomplete agreement with Settings → Common when a CLI is chosen and there is no faster AI.
        Platform.current.onDeviceModel = StubAppleModel(availability: .appleIntelligenceNotEnabled)
        AutocompleteSwitch.recentAvailability = RecentAvailability()
        var cliConfig = Config.default
        cliConfig.uiLanguage = "en"
        cliConfig.provider = .openai
        cliConfig.ai = .cli(.claude)
        cliConfig.autocomplete = true
        writeConfig(cliConfig, to: url)
        UIText.choice = "en"
        let controller = AllInOneIMEInputController(server: nil, delegate: nil, client: nil) ?? AllInOneIMEInputController()
        controller.clientOverride = FakeTextClient()
        let fullMenu = controller.addingAutocomplete(to: controller.makeMenu())
        if let item = allMenuItems(fullMenu).first(where: { $0.action == #selector(AllInOneIMEInputController.toggleAutocomplete(_:)) }) {
            emit("24_MENU_AUTOCOMPLETE_FOUND", "1")
            emit("24_MENU_AUTOCOMPLETE_ON", item.state == .on ? "1" : "0")
            emit("24_MENU_AUTOCOMPLETE_ENABLED", item.isEnabled ? "1" : "0")
            emit("24_MENU_AUTOCOMPLETE_TITLE", item.title)
        }
    }
}

DispatchQueue.main.async { MainActor.assumeIsolated { ReviewUI076Child.run() } }
NSApplication.shared.run()
exit(0)
"""#
}
