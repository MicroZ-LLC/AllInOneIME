import AllInOneIMECore
import Foundation
import Testing

// Issue #53: editing a command in Settings drops its icon, color and custom stdin. The command editor's Save writes the
// command as the form has it, rebuilt from a fresh `CustomCommand(name:type:)` (CommandEditor's `draft`), and
// `CustomCommand.saving` puts that in place of the whole entry: what config.json has that the form doesn't show is
// erased. A hand-set `icon` and `color` (documented in CHANGELOG and docs/plugins.md, drawn in the command list) are
// gone, and a `stdin` like "{input}\nquit\n" comes back as "{input}\n" (the form's switch only says whether the text
// goes to standard input). The changed command then syncs to the other Macs. Expected: fields the form doesn't show are
// kept; a `stdin` the switch can't show stays as it was unless the user changes the switch.
//
// The input method's own code can't be imported here (it is an executable target): as Issue51Tests does it, all of
// Sources/AllInOneIME is compiled into a child process, with the Mac library, the core and librime, as the input method
// is built. Only main.swift's dispatch (what follows `let arguments = …`) is replaced: the child shows the real Settings
// window on the Commands page, presses the command's Edit, types a new description over the editor's Description field
// as the field editor takes keystrokes, and presses Save, as the user does (the buttons pressed as VoiceOver presses
// them: SwiftUI draws them without an NSButton). The test reads config.json after. The child's home is a folder of the
// test's (the config file is never the user's), its keychain an in-memory one and the window looks up no keys
// (`SettingsModel.looksUpKeys`): nothing asks the user's keychain or the network.

@Suite(.serialized)
struct Issue53Tests {
    /// A command config.json has with a hand-set icon and color (and, for `run`, a stdin the form's switch can't show):
    /// only its description edited in Settings and saved, config.json still has the icon, the color and the stdin as
    /// they were, and the new description.
    @Test(arguments: Issue53Child.Case.allCases)
    func editingOnlyTheDescriptionKeepsWhatTheFormDoesNotShow(_ edited: Issue53Child.Case) throws {
        let report = try Issue53Child.run(edited)
        let before = edited.command
        #expect(report.typed == Issue53Child.typed, "the Description field shows what was typed: \(report)")
        #expect(report.closed == true, "Save closed the editor: \(report)")
        let saved = try #require(report.saved, "config.json has no command \(before.name) after Save: \(report)")
        #expect(saved.summary == Issue53Child.typed, "the new description was saved: \(report)")
        #expect(saved.icon == before.icon,
                "@\(before.name)'s icon \(before.icon.map { "\"\($0)\"" } ?? "nil") became \(saved.icon.map { "\"\($0)\"" } ?? "nil") when only its description was edited: \(report)")
        #expect(saved.color == before.color,
                "@\(before.name)'s color \(before.color.map { "\"\($0)\"" } ?? "nil") became \(saved.color.map { "\"\($0)\"" } ?? "nil") when only its description was edited: \(report)")
        #expect(saved.stdin == before.stdin,
                "@\(before.name)'s stdin \(before.stdin.debugDescription) became \(saved.stdin.debugDescription) when only its description was edited: \(report)")
        #expect(saved.type == before.type && saved.prompt == before.prompt && saved.argv == before.argv,
                "what the form shows was saved as it was: \(report)")
    }
}

enum Issue53Child {
    /// The description the user types over the old one, without changing anything else.
    static let typed = "Edited description"

    /// The command in config.json the user edits.
    enum Case: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// The issue's: a program run with a stdin of its own ("{input}\nquit\n"), a hand-set icon and color.
        case run
        /// An instruction for the AI with a hand-set icon and color ("#RRGGBB").
        case prompt
        var testDescription: String { rawValue }

        var command: CustomCommand {
            switch self {
            case .run:
                CustomCommand(name: "calc", type: .run, summary: "Calculator", argv: ["bc", "-q"], stdin: "{input}\nquit\n",
                              icon: "function", color: "green")
            case .prompt:
                CustomCommand(name: "polite", type: .prompt, summary: "Reply politely", prompt: "Write a short, polite reply to the user's message.",
                              icon: "bubble.left", color: "#FF8800")
            }
        }
    }

    struct Report: CustomStringConvertible {
        /// What the Description field showed once typed in (nil: the child never got there).
        var typed: String?
        /// Whether the editor closed after Save (nil: Save never clicked).
        var closed: Bool?
        /// The command of that name in config.json once the child has ended.
        var saved: CustomCommand?
        var status: Int32
        var output: String
        var description: String {
            "field showed \(typed.map { "\"\($0)\"" } ?? "nothing"), config.json's command \(saved.map(Issue53Child.describe) ?? "missing") "
                + "(the child exited \(status)):\n\(output)"
        }
    }

    static func describe(_ command: CustomCommand) -> String {
        let data = (try? JSONEncoder().encode(command)) ?? Data()
        return String(decoding: data, as: UTF8.self)
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

    static func run(_ edited: Case) throws -> Report {
        let executable = try compiled.get()
        let fm = FileManager.default
        // The child's home: its config.json there, never the user's.
        let home = fm.temporaryDirectory.appendingPathComponent("issue53-home-\(UUID().uuidString)", isDirectory: true)
        let file = home.appendingPathComponent(".config/allinoneime/config.json")
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        var config = Config.default
        config.uiLanguage = "en"
        config.customCommands = [edited.command]
        try config.write(to: file)
        guard try Config.load(from: file).customCommands == [edited.command] else {
            throw Failure(description: "config.json doesn't read back the command as written: \(describe(edited.command))")
        }

        let result = try command(executable, [edited.command.summary ?? "", typed],
                                 environment: ["CFFIXED_USER_HOME": home.path, "HOME": home.path], timeout: 60)
        let lines = result.output.split(separator: "\n")
        let typed = lines.last(where: { $0.hasPrefix("TYPED ") }).map { String($0.dropFirst("TYPED ".count)) }
        let closed = lines.last(where: { $0.hasPrefix("CLOSED ") }).map { $0 == "CLOSED true" }
        let saved = (try? Config.load(from: file))?.customCommands.first { $0.name == edited.command.name }
        return Report(typed: typed, closed: closed, saved: saved, status: result.status, output: result.output)
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue53-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let harness = String(main[..<cut.upperBound]) + Issue53Harness.swift
        let mainFile = scratch.appendingPathComponent("main.swift")
        try harness.write(to: mainFile, atomically: true, encoding: .utf8)
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
        let executable = scratch.appendingPathComponent("issue53")
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
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue53-\(UUID().uuidString).log")
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

/// What follows main.swift's `let arguments = …` in the child: the Settings window on the Commands page, the command's
/// Edit clicked, a new description typed over the old one, Save clicked.
private enum Issue53Harness {
    static let swift = #"""

// MARK: - Issue #53's child (in place of main.swift's dispatch)

// Never the user's keychain: an in-memory one, and the window looks up no keys (as the self-test has it).
Platform.current.secrets = .inMemory()
MainActor.assumeIsolated { SettingsModel.looksUpKeys = false }

@MainActor
enum Issue53Child {
    /// The command's description as config.json has it: what the editor's Description field shows when it opens.
    static let before = arguments.count > 0 ? arguments[0] : ""
    static let typed = arguments.count > 1 ? arguments[1] : ""

    static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }

    static func fail(_ line: String) -> Never {
        say("FAIL " + line)
        exit(3)
    }

    static func start() {
        // Never the user's config: the test's home.
        let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
        guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
            fail("the config file isn't in the test's home: \(Config.defaultURL.path)")
        }
        // SwiftUI builds the views' accessibility (their buttons) for an assistive app only, which says so with
        // `AXEnhancedUserInterface` on the app: set on this process's own, as AssistantSelfTest does.
        _ = NSApp.perform(Selector(("accessibilitySetValue:forAttribute:")), with: true as NSNumber, with: "AXEnhancedUserInterface")
        SettingsWindow.shared.show(page: .commands)
        waitFor("the command's Edit button", until: Date().addingTimeInterval(20), { () -> Bool? in press("Edit", in: visibleWindows()) }) { _ in
            waitFor("the editor's Description field showing \"\(before)\"", until: Date().addingTimeInterval(20), { descriptionField() }) { field, window in
                type(into: field, in: window)
            }
        }
    }

    /// Polls `find` on the main thread until it finds what it looks for, then hands it to `then`.
    static func waitFor<T>(_ what: String, until deadline: Date, _ find: @escaping () -> T?, then: @escaping (T) -> Void) {
        if let found = find() {
            then(found)
            return
        }
        guard Date() < deadline else { fail("no \(what); buttons: \(buttonTitles()), fields: \(allTextFields().map { "\"\($0.stringValue)\"" })") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { MainActor.assumeIsolated { waitFor(what, until: deadline, find, then: then) } }
    }

    static func visibleWindows() -> [NSWindow] { NSApp.windows.filter(\.isVisible) }

    /// The editor's sheet (or any visible window, should it be shown otherwise).
    static func editorWindows() -> [NSWindow] {
        let sheets = NSApp.windows.compactMap(\.attachedSheet).filter(\.isVisible)
        return sheets.isEmpty ? NSApp.windows.filter { $0.isVisible && $0.isSheet } : sheets
    }

    static func views<T: NSView>(_ type: T.Type, in view: NSView?) -> [T] {
        guard let view else { return [] }
        return ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
    }

    static func allTextFields() -> [NSTextField] {
        NSApp.windows.filter(\.isVisible).flatMap { views(NSTextField.self, in: $0.contentView) }
    }

    /// The titles of the buttons on screen, AppKit's and those SwiftUI only shows to accessibility.
    static func buttonTitles() -> [String] {
        NSApp.windows.filter(\.isVisible).flatMap { window in
            views(NSButton.self, in: window.contentView).map(\.title) + accessibilityButtons(in: window).compactMap(label)
        }
    }

    /// SwiftUI's accessibility nodes answer the accessibility methods without declaring the protocol: asked by name,
    /// as AssistantSelfTest does.
    static func ax(_ node: NSObject, _ key: String) -> Any? { node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil }

    static func children(_ node: NSObject) -> [NSObject] { (ax(node, "accessibilityChildren") as? [NSObject]) ?? [] }

    static func accessibilityButtons(in node: NSObject, depth: Int = 0) -> [NSObject] {
        guard depth < 60 else { return [] }
        let own = (ax(node, "accessibilityRole") as? String) == NSAccessibility.Role.button.rawValue ? [node] : []
        return own + children(node).flatMap { accessibilityButtons(in: $0, depth: depth + 1) }
    }

    static func label(_ node: NSObject) -> String? {
        (ax(node, "accessibilityLabel") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (ax(node, "accessibilityTitle") as? String)
    }

    /// Clicks the button titled `title` in `windows`, as AppKit's control or as SwiftUI shows it to accessibility.
    static func press(_ title: String, in windows: [NSWindow]) -> Bool? {
        for window in windows {
            if let button = views(NSButton.self, in: window.contentView).first(where: { $0.title == title && $0.isEnabled }) {
                say("PRESSED \(title)")
                button.performClick(nil)
                return true
            }
        }
        for window in windows {
            if let button = accessibilityButtons(in: window).first(where: { label($0) == title }),
               button.responds(to: NSSelectorFromString("accessibilityPerformPress")) {
                _ = button.perform(NSSelectorFromString("accessibilityPerformPress"))
                say("PRESSED \(title)")
                return true
            }
        }
        return nil
    }

    /// The editor's Description field, showing the command's description.
    static func descriptionField() -> (NSTextField, NSWindow)? {
        for window in editorWindows() {
            if let field = views(NSTextField.self, in: window.contentView).first(where: { $0.isEditable && $0.isEnabled && $0.stringValue == before }) {
                return (field, window)
            }
        }
        return nil
    }

    /// Focused, all of it selected, and typed over a key at a time as the field editor takes keystrokes.
    static func type(into field: NSTextField, in window: NSWindow) {
        guard window.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView else { fail("the field didn't take the focus") }
        editor.selectAll(nil)
        for character in typed {
            editor.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                say("TYPED \(field.stringValue)")
                save(window)
            }
        }
    }

    /// Save clicked; the editor closes once it has saved.
    static func save(_ sheet: NSWindow) {
        guard press("Save", in: [sheet]) != nil else { fail("no Save button in the editor; buttons: \(buttonTitles())") }
        let deadline = Date().addingTimeInterval(5)
        func closed() {
            if !sheet.isVisible || Date() >= deadline {
                say("CLOSED \(!sheet.isVisible)")
                // Read once Settings has written config.json; then the child ends without anything else saving.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { _exit(0) }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { MainActor.assumeIsolated { closed() } }
        }
        closed()
    }
}

let issue53App = NSApplication.shared
issue53App.setActivationPolicy(.accessory)
DispatchQueue.main.async { MainActor.assumeIsolated { Issue53Child.start() } }
issue53App.run()
exit(0)
"""#
}
