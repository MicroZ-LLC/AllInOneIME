import AllInOneIMECore
import Foundation
import Testing

// Issue #40: unsaved Settings text fields are lost when the input method ends. Amazon Bedrock's Model ID and Region are
// bound to the settings live but saved only on Return, when the window closes (`willClose`) or when its view goes away.
// The Settings window lives in the input method's process. Ended by SIGTERM (`make install`'s pkill, the update helper
// stopping an input method that hangs, launchd at logout or shutdown: main.swift's handler), the process exits from
// the handler (`_exit`) without the window closing and without anything saving the window's settings, so what was typed
// without Return is silently dropped. Expected: pending edits are saved before the input method ends.
//
// About → Update quits with `NSApp.terminate` (once the update is staged): AppKit closes every window as it terminates
// (`-[NSWindow _closeForTermination]`), the window's `willClose` saves, and the typed value is kept already; that test
// keeps it so.
//
// The input method's own code can't be imported here (it is an executable target): all of Sources/AllInOneIME is
// compiled into a child process, with the Mac library, the core and librime, as the input method is built. Only
// main.swift's dispatch (what follows `let arguments = …`) is replaced: the child does what `runServer` does about
// ending (the app's delegate, and the signal sources it sets up and resumes, taken from main.swift as written; no
// IMKServer, nothing else started), shows the real Settings window on the AI page, and types into the field as the
// field editor takes keystrokes (no Return). Then it ends as the user's action does: About → Update (the page turned
// to About, then `NSApp.terminate`), or SIGTERM. The child's home is a folder of the test's (the config file is never
// the user's), its keychain an in-memory one and the window looks up no keys (`SettingsModel.looksUpKeys`, as the
// self-test has it): nothing asks the user's keychain or the network.

@Suite(.serialized)
struct Issue40Tests {
    /// Typed without Return, About shown, Update clicked: the input method quits (`NSApp.terminate`) for the helper. The
    /// field's value is in config.json once it has (today too: the window closes as the app terminates).
    @Test(arguments: Issue40Child.Field.allCases)
    func aFieldTypedWithoutReturnIsSavedWhenUpdateQuits(_ field: Issue40Child.Field) throws {
        let report = try Issue40Child.run(.update, field)
        #expect(report.typed == field.typed, "the field shows what was typed: \(report)")
        #expect(report.saved == field.typed,
                "About → Update quit the input method and dropped the \(field.title) typed without Return: \(report)")
    }

    /// Typed without Return, then the input method gets SIGTERM (logging out, `make install`): the field's value is in
    /// config.json once it has ended.
    @Test(arguments: Issue40Child.Field.allCases)
    func aFieldTypedWithoutReturnIsSavedWhenSIGTERMEndsTheInputMethod(_ field: Issue40Child.Field) throws {
        let report = try Issue40Child.run(.sigterm, field)
        #expect(report.typed == field.typed, "the field shows what was typed: \(report)")
        #expect(report.saved == field.typed,
                "SIGTERM ended the input method and dropped the \(field.title) typed without Return: \(report)")
    }
}

enum Issue40Child {
    /// How the input method ends after the field is typed in.
    enum Quit: String, Sendable {
        /// About → Update: the page turned to About, then, the update staged, `NSApp.terminate` (`UpdateController.install`).
        case update
        /// SIGTERM: logging out, `make install`, the update helper stopping an input method that hangs.
        case sigterm
    }

    /// A field of the AI page bound live and saved on Return, Amazon Bedrock's.
    enum Field: String, CaseIterable, CustomTestStringConvertible, Sendable {
        case modelId = "model-id"
        case region
        var testDescription: String { rawValue }

        var title: String {
            switch self {
            case .modelId: "Model ID"
            case .region: "Region"
            }
        }
        /// What config.json has before: what the field shows when the page opens (a model ID not among the suggested
        /// ones, so that the field is shown).
        var before: String {
            switch self {
            case .modelId: "us.anthropic.issue40-before-v1:0"
            case .region: "us-west-1"
            }
        }
        /// What the user types over it, without Return.
        var typed: String {
            switch self {
            case .modelId: "us.anthropic.issue40-typed-v1:0"
            case .region: "eu-central-1"
            }
        }
        /// The field's value in `config`.
        func value(in config: Config) -> String? {
            switch self {
            case .modelId: config.modelId
            case .region: config.region
            }
        }
    }

    struct Report: CustomStringConvertible {
        /// What the field showed once typed in (nil: the child never got there).
        var typed: String?
        /// The field's value in config.json once the child has ended.
        var saved: String?
        var status: Int32
        var output: String
        var description: String {
            "field showed \(typed.map { "\"\($0)\"" } ?? "nothing"), config.json has \(saved.map { "\"\($0)\"" } ?? "nothing") "
                + "(the child exited \(status)):\n\(output)"
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

    static func run(_ quit: Quit, _ field: Field) throws -> Report {
        let executable = try compiled.get()
        let fm = FileManager.default
        // The child's home: its config.json there, never the user's.
        let home = fm.temporaryDirectory.appendingPathComponent("issue40-home-\(UUID().uuidString)", isDirectory: true)
        let file = home.appendingPathComponent(".config/allinoneime/config.json")
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        var config = Config.default
        config.uiLanguage = "en"
        config.provider = .bedrock
        config.modelId = Field.modelId.before
        config.region = Field.region.before
        try config.write(to: file)

        let result = try command(executable, [quit.rawValue, field.before, field.typed],
                                 environment: ["CFFIXED_USER_HOME": home.path, "HOME": home.path], timeout: 60)
        let typed = result.output.split(separator: "\n").last(where: { $0.hasPrefix("TYPED ") })
            .map { String($0.dropFirst("TYPED ".count)) }
        let saved = (try? Config.load(from: file)).flatMap(field.value(in:))
        return Report(typed: typed, saved: saved, status: result.status, output: result.output)
    }

    /// The lines of `runServer` (main.swift) that set up a signal (`signal(…)`) or resume a signal source: SIGTERM handled
    /// as the input method handles it.
    static func signalSetUp(_ main: String) -> String {
        guard let start = main.range(of: "func runServer(") else { return "" }
        let body = main[start.lowerBound...]
        let end = body.range(of: "\n}\n")?.lowerBound ?? body.endIndex
        return body[..<end].split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && ($0.hasSuffix(".resume()") || $0.hasPrefix("signal(")) }.joined(separator: "\n")
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue40-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let harness = String(main[..<cut.upperBound])
            + Issue40Harness.swift.replacingOccurrences(of: "SIGNAL_SET_UP", with: signalSetUp(main))
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
        let executable = scratch.appendingPathComponent("issue40")
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
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue40-\(UUID().uuidString).log")
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

/// What follows main.swift's `let arguments = …` in the child: the input method as `runServer` sets it up for ending,
/// the Settings window on the AI page, the field typed in, then the input method ended as the scenario says.
private enum Issue40Harness {
    static let swift = #"""

// MARK: - Issue #40's child (in place of main.swift's dispatch)

// Never the user's keychain: an in-memory one, and the window looks up no keys (as the self-test has it).
Platform.current.secrets = .inMemory()
MainActor.assumeIsolated { SettingsModel.looksUpKeys = false }

@MainActor
enum Issue40Child {
    static let quit = arguments.count > 0 ? arguments[0] : ""
    static let before = arguments.count > 1 ? arguments[1] : ""
    static let typed = arguments.count > 2 ? arguments[2] : ""

    static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }

    static func start() {
        // Never the user's config: the test's home.
        let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
        guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
            say("FAIL the config file isn't in the test's home: \(Config.defaultURL.path)")
            exit(3)
        }
        SettingsWindow.shared.show(page: .ai)
        find(until: Date().addingTimeInterval(20))
    }

    static func textFields(in view: NSView?) -> [NSTextField] {
        guard let view else { return [] }
        return ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap { textFields(in: $0) }
    }

    static func allTextFields() -> [NSTextField] {
        NSApp.windows.filter(\.isVisible).flatMap { textFields(in: $0.contentView) }
    }

    /// The editable field showing `before`, once the page is laid out.
    static func find(until deadline: Date) {
        for window in NSApp.windows where window.isVisible {
            if let field = textFields(in: window.contentView).first(where: { $0.isEditable && $0.stringValue == before }) {
                type(into: field, in: window)
                return
            }
        }
        guard Date() < deadline else {
            say("FAIL no field shows \"\(before)\" on the AI page; fields: \(allTextFields().map { "\"\($0.stringValue)\"" })")
            exit(3)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { MainActor.assumeIsolated { find(until: deadline) } }
    }

    /// Focused, all of it selected, and typed over a key at a time as the field editor takes keystrokes: no Return.
    static func type(into field: NSTextField, in window: NSWindow) {
        guard window.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView else {
            say("FAIL the field didn't take the focus")
            exit(3)
        }
        editor.selectAll(nil)
        for character in typed {
            editor.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                say("TYPED \(field.stringValue)")
                end()
            }
        }
    }

    static func end() {
        switch quit {
        case "update":
            // About shown, Update clicked: once the update is staged and the helper started, `NSApp.terminate`.
            SettingsWindow.shared.show(page: .about)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        case "sigterm":
            // Logging out, `make install`: SIGTERM to the process (here sent by itself, once typed in).
            kill(getpid(), SIGTERM)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                MainActor.assumeIsolated {
                    say("FAIL SIGTERM didn't end the input method")
                    exit(4)
                }
            }
        default:
            say("FAIL unknown way to quit: \(quit)")
            exit(2)
        }
    }
}

// As `runServer` does it: the app's delegate, the signals set up; no IMKServer, nothing else started.
let issue40App = NSApplication.shared
issue40App.setActivationPolicy(.accessory)
issue40App.delegate = IMEAppDelegate.shared
SIGNAL_SET_UP
DispatchQueue.main.async { MainActor.assumeIsolated { Issue40Child.start() } }
issue40App.run()
exit(0)
"""#
}
