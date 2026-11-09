import AllInOneIMECore
import Foundation
import Testing

// Issue #73: the French keyboard layout picked in Settings isn't saved or applied. Settings → Input → French's Keyboard
// layout picker sets only the window's settings (`model.config.keyboardLayouts`), and no save follows it (the window's
// save hooks have none for `keyboardLayouts`). The input method reads config.json for each field (`LiveConfig`, then
// `applyKeyboardLayout`), so French keeps typing AZERTY (`qwerty` comes out as `azerty`) until something else saves,
// the window closes or the input method quits; and if config.json is rewritten first (the Assistant's Apply, iCloud
// sync, a learned word), the window reads it again and the pick is gone: the picker shows AZERTY again. Expected: the
// pick is written at once and used from the next field, as every other picker's (SettingsModel: "Every change is written
// to the config file right away"; README: "after a change, the next translation uses the new settings").
//
// The input method's own code can't be imported here (it is an executable target): as Issue51Tests does it, all of
// Sources/AllInOneIME is compiled into a child process, with the Mac library, the core and librime, as the input method
// is built. Only main.swift's dispatch (what follows `let arguments = …`) is replaced: the child shows the real Settings
// window on the Input page, with French among the input languages and no layout picked for it (AZERTY, its default),
// opens French's Keyboard layout picker as VoiceOver presses it (SwiftUI draws it without an NSPopUpButton) and chooses
// ABC from the menu it shows, as TranslateTargetSelfTest chooses from Translate to's. Settings stays open. The child
// then reads the settings as the input method does for the next field (`LiveConfig.current`); or something else
// rewrites config.json first (another setting changed in it, as the Assistant's Apply does, which then tells the window
// to read it again) and the child says what the picker shows after. The child's home is a folder of the test's (the
// config file is never the user's), its keychain an in-memory one and the window looks up no keys
// (`SettingsModel.looksUpKeys`): nothing asks the user's keychain or the network.

@Suite(.serialized)
struct Issue73Tests {
    /// ABC picked for French, Settings left open: the next field's French types with ABC, as config.json has it.
    @Test func aLayoutPickedForFrenchIsUsedFromTheNextField() throws {
        let report = try Issue73Child.run(.pick)
        #expect(report.before == Issue73Child.azerty, "French's picker showed AZERTY (its default) before the pick: \(report)")
        #expect(report.shown == Issue73Child.abc, "French's picker shows ABC once picked: \(report)")
        #expect(report.typesWith == Issue73Child.abc,
                "ABC picked for French in Settings, and the input method still types French with \(report.typesWith ?? "nothing") in the next field: \(report)")
        #expect(report.saved?.keyboardLayout(for: .french) == Issue73Child.abc,
                "ABC picked for French in Settings isn't in config.json while Settings is open: \(report)")
    }

    /// ABC picked for French, then config.json rewritten by something else before anything in Settings saved (another
    /// setting changed in it, as the Assistant's Apply does) and the window told to read it again: the picker still shows
    /// ABC, and the input method types French with it.
    @Test func aLayoutPickedForFrenchIsKeptWhenConfigJSONIsRewritten() throws {
        let report = try Issue73Child.run(.rewritten)
        #expect(report.before == Issue73Child.azerty, "French's picker showed AZERTY (its default) before the pick: \(report)")
        #expect(report.rewrote == true, "config.json was rewritten by something else: \(report)")
        #expect(report.shown == Issue73Child.abc,
                "ABC picked for French, config.json rewritten elsewhere, and the picker shows \(report.shown ?? "nothing") again: \(report)")
        #expect(report.typesWith == Issue73Child.abc,
                "ABC picked for French, config.json rewritten elsewhere, and the input method types French with \(report.typesWith ?? "nothing"): \(report)")
        #expect(report.saved?.keyboardLayout(for: .french) == Issue73Child.abc, "config.json has ABC for French: \(report)")
        #expect(report.saved?.temperature == Issue73Child.temperature, "what was rewritten elsewhere stays: \(report)")
    }
}

enum Issue73Child {
    /// French's default layout (AZERTY), and the one the user picks.
    static let azerty = "com.apple.keylayout.French"
    static let abc = "com.apple.keylayout.ABC"
    /// What something else writes into config.json meanwhile.
    static let temperature = 0.25

    /// What happens once ABC is picked.
    enum Mode: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// Nothing more: the next field is typed in, Settings still open.
        case pick
        /// config.json rewritten elsewhere (another setting), and the window told to read it again.
        case rewritten
        var testDescription: String { rawValue }
    }

    struct Report: CustomStringConvertible {
        /// The layout French's picker showed before the pick (nil: no picker found).
        var before: String?
        /// The layout French's picker shows at the end.
        var shown: String?
        /// Whether config.json was rewritten elsewhere (nil: not asked).
        var rewrote: Bool?
        /// The layout the input method types French with, as it reads the settings for the next field.
        var typesWith: String?
        /// config.json once the child has ended.
        var saved: Config?
        var status: Int32
        var output: String
        var description: String {
            "picker showed \(before ?? "nothing") before, \(shown ?? "nothing") after; French types with \(typesWith ?? "nothing"); "
                + "config.json's layouts \(saved.map { "\($0.keyboardLayouts)" } ?? "unreadable") (the child exited \(status)):\n\(output)"
        }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static var thirdParty: URL {
        ProcessInfo.processInfo.environment["ALLINONEIME_THIRDPARTY"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("ThirdParty")
    }

    static func run(_ mode: Mode) throws -> Report {
        let executable = try compiled.get()
        let fm = FileManager.default
        // The child's home: its config.json there, never the user's.
        let home = fm.temporaryDirectory.appendingPathComponent("issue73-home-\(UUID().uuidString)", isDirectory: true)
        let file = home.appendingPathComponent(".config/allinoneime/config.json")
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.english, .french])
        config.keyboardLayouts = [:]
        try config.write(to: file)
        guard let written = try? Config.load(from: file), written.inputLanguages.contains(.french),
              written.keyboardLayout(for: .french) == azerty else {
            throw Failure(description: "config.json doesn't read back French with AZERTY")
        }

        let result = try command(executable, [mode.rawValue, azerty, abc, "\(temperature)"],
                                 environment: ["CFFIXED_USER_HOME": home.path, "HOME": home.path], timeout: 60)
        let lines = result.output.split(separator: "\n")
        func value(_ prefix: String) -> String? {
            lines.last(where: { $0.hasPrefix(prefix + " ") }).map { String($0.dropFirst(prefix.count + 1)) }
        }
        return Report(before: value("BEFORE"), shown: value("SHOWN"), rewrote: value("REWROTE").map { $0 == "true" },
                      typesWith: value("TYPES"), saved: try? Config.load(from: file), status: result.status, output: result.output)
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue73-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + Issue73Harness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        // The Mac library, the core and librime's wrapper, as `swift test` built them.
        let products = repository.appendingPathComponent(".build/debug")
        let modules = fm.fileExists(atPath: products.appendingPathComponent("Modules").path)
            ? products.appendingPathComponent("Modules") : products
        var objects: [String] = []
        for module in ["AllInOneIMEMac", "AllInOneIMECore", "AllInOneIMERime", "AllInOneIMEText", "AllInOneIMEScriptEngine",
                       "CQuickJS", "Crypto"] {
            let aggregate = products.appendingPathComponent(module + ".o")
            if fm.fileExists(atPath: aggregate.path) {
                objects.append(aggregate.path)
            } else if let files = try? fm.contentsOfDirectory(at: products.appendingPathComponent(module + ".build"), includingPropertiesForKeys: nil) {
                objects += files.filter { $0.pathExtension == "o" }.map(\.path)
            }
        }
        let rimeLib = thirdParty.appendingPathComponent("librime/dist/lib")
        let executable = scratch.appendingPathComponent("issue73")
        let arguments = ["swiftc", "-swift-version", "5", "-j", "\(max(2, ProcessInfo.processInfo.activeProcessorCount))",
                         "-I", modules.path, "-I", repository.appendingPathComponent("Core/Sources/CRime").path,
                         "-L", rimeLib.path, "-lrime", "-Xlinker", "-rpath", "-Xlinker", rimeLib.path,
                         "-framework", "AppKit", "-framework", "InputMethodKit", "-framework", "Carbon", "-framework", "AVFoundation",
                         "-framework", "Speech", "-framework", "EventKit", "-framework", "SwiftUI",
                         "-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels",
                         mainFile.path] + others + objects + ["-o", executable.path]
        let swift = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments, timeout: 900)
        guard swift.status == 0 else { throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n\(swift.output)") }
        return executable
    }

    private static func command(_ executable: URL, _ arguments: [String], environment: [String: String] = [:],
                                timeout: TimeInterval) throws -> (status: Int32, output: String) {
        // A file, not a pipe: a long compiler output never blocks the child.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue73-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: log)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw Failure(description: "timed out: \(executable.lastPathComponent) \(arguments.first ?? "")\n"
                          + ((try? String(contentsOf: log, encoding: .utf8)) ?? ""))
        }
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }
}

/// What follows main.swift's `let arguments = …` in the child: the Settings window on the Input page, ABC picked from
/// French's Keyboard layout menu, then what the mode says.
private enum Issue73Harness {
    static let swift = #"""

// MARK: - Issue #73's child (in place of main.swift's dispatch)

// Never the user's keychain: an in-memory one, and the window looks up no keys (as the self-test has it).
Platform.current.secrets = .inMemory()
MainActor.assumeIsolated { SettingsModel.looksUpKeys = false }

@MainActor
enum Issue73Child {
    static let mode = arguments.count > 0 ? arguments[0] : ""
    static let azerty = arguments.count > 1 ? arguments[1] : ""
    static let abc = arguments.count > 2 ? arguments[2] : ""
    static let temperature = arguments.count > 3 ? Double(arguments[3]) ?? 0 : 0
    /// The layouts' names, as the picker lists them.
    static var abcName = ""

    static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }

    static func fail(_ line: String) -> Never {
        say("FAIL " + line)
        exit(3)
    }

    /// A layout's id, from its name as the picker shows it.
    static func id(_ name: String?) -> String { KeyboardLayouts.latin.first { $0.name == name }?.id ?? name ?? "nothing" }

    static func start() {
        // Never the user's config: the test's home.
        let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
        guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
            fail("the config file isn't in the test's home: \(Config.defaultURL.path)")
        }
        guard let name = KeyboardLayouts.latin.first(where: { $0.id == abc })?.name else {
            fail("this Mac lists no \(abc): \(KeyboardLayouts.latin.map(\.id))")
        }
        abcName = name
        // SwiftUI builds the views' accessibility (their pop-up buttons) for an assistive app only, which says so with
        // `AXEnhancedUserInterface` on the app: set on this process's own, as AssistantSelfTest does.
        _ = NSApp.perform(Selector(("accessibilitySetValue:forAttribute:")), with: true as NSNumber, with: "AXEnhancedUserInterface")
        SettingsWindow.shared.show(page: .input)
        find(until: Date().addingTimeInterval(20))
    }

    /// SwiftUI's accessibility nodes answer the accessibility methods without declaring the protocol: asked by name,
    /// as AssistantSelfTest does.
    static func ax(_ node: NSObject, _ key: String) -> Any? { node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil }
    static func children(_ node: NSObject) -> [NSObject] { (ax(node, "accessibilityChildren") as? [NSObject]) ?? [] }
    static func role(_ node: NSObject) -> String? { ax(node, "accessibilityRole") as? String }
    static func value(_ node: NSObject) -> String? { ax(node, "accessibilityValue") as? String }

    static func nodes(_ node: NSObject, depth: Int = 0) -> [NSObject] {
        depth < 60 ? [node] + children(node).flatMap { nodes($0, depth: depth + 1) } : []
    }

    /// French's Keyboard layout picker: the pop-up button after the "Keyboard layout" title, in the section under French.
    static func layoutPicker() -> NSObject? {
        for window in NSApp.windows where window.isVisible {
            for node in nodes(window) {
                let row = children(node)
                guard let title = row.firstIndex(where: { role($0) == NSAccessibility.Role.staticText.rawValue && value($0) == "Keyboard layout" }) else { continue }
                if let picker = row[title...].first(where: { role($0) == NSAccessibility.Role.popUpButton.rawValue }) { return picker }
            }
        }
        return nil
    }

    static func shown() -> String { layoutPicker().flatMap(value).map { id($0) } ?? "nothing" }

    /// French's picker, once the page is laid out.
    static func find(until deadline: Date) {
        if let picker = layoutPicker() {
            pick(picker)
            return
        }
        guard Date() < deadline else {
            let found = NSApp.windows.filter(\.isVisible).flatMap { nodes($0) }.compactMap { node in role(node).map { "\($0) \(value(node) ?? "")" } }
            fail("no Keyboard layout picker on the Input page: \(found)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { MainActor.assumeIsolated { find(until: deadline) } }
    }

    /// The picker opened as a click (or VoiceOver's press) opens it, and ABC chosen from its menu; Settings stays open.
    static func pick(_ picker: NSObject) {
        say("BEFORE \(shown())")
        var picked = false
        var tracking: NSObjectProtocol?
        tracking = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            MainActor.assumeIsolated {
                guard !picked, let menu = note.object as? NSMenu else { return }
                picked = true
                let choose = Timer(timeInterval: 0.3, repeats: false) { _ in
                    MainActor.assumeIsolated {
                        menu.cancelTracking()
                        guard let index = menu.items.firstIndex(where: { $0.title == abcName }) else {
                            fail("the menu has no \(abcName): \(menu.items.map(\.title))")
                        }
                        menu.performActionForItem(at: index)
                        if let tracking { NotificationCenter.default.removeObserver(tracking) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { then() } }
                    }
                }
                RunLoop.main.add(choose, forMode: .common)
            }
        }
        _ = picker.perform(NSSelectorFromString("accessibilityPerformPress"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            MainActor.assumeIsolated { if !picked { fail("pressing French's Keyboard layout picker opened no menu") } }
        }
    }

    static func then() {
        switch mode {
        case "pick":
            finish()
        case "rewritten":
            // Something else rewrites config.json (another setting changed in it, as the Assistant's Apply, iCloud sync
            // or a learned word do) and the window is told to read it again, as the Assistant tells it.
            do {
                _ = try Config.change { $0.temperature = temperature }
                say("REWROTE true")
            } catch {
                fail("couldn't rewrite config.json: \(error)")
            }
            NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { finish() } }
        default:
            fail("unknown mode: \(mode)")
        }
    }

    /// What the picker shows, and the layout the input method types French with in the next field (the settings read as
    /// it reads them: `LiveConfig`); then the child ends without anything saving (no window closed, no termination).
    static func finish() {
        say("SHOWN \(shown())")
        say("TYPES \(LiveConfig.current.keyboardLayout(for: .french) ?? "the system's")")
        _exit(0)
    }
}

let issue73App = NSApplication.shared
issue73App.setActivationPolicy(.accessory)
DispatchQueue.main.async { MainActor.assumeIsolated { Issue73Child.start() } }
issue73App.run()
exit(0)
"""#
}
