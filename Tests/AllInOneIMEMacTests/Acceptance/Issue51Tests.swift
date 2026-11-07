import AllInOneIMECore
import Foundation
import Testing

// Issue #51: a word typed into Settings → Privacy → Words to hide without Return isn't applied or saved. The field's
// text lives only in the view (`PrivacySection`'s `@State`) and goes into `redaction.customWords` only on Return
// (`onSubmit`) or when the page goes away (`onDisappear`). Until then the input method, which reads config.json for each
// request, sends the word unredacted (`@improve` on "ProjectX ships Monday" sends ProjectX as typed), and if the input
// method ends meanwhile (SIGTERM: logging out, an update, `make install`) the word is lost: `SettingsWindow.save()`,
// which #40's quit paths call, saves only the window's settings, never the field's text. Expected: the word is saved,
// and so applied, when the field loses focus and when the input method ends, as #40's fields are.
//
// The input method's own code can't be imported here (it is an executable target): as Issue40Tests does it, all of
// Sources/AllInOneIME is compiled into a child process, with the Mac library, the core and librime, as the input method
// is built. Only main.swift's dispatch (what follows `let arguments = …`) is replaced: the child does what `runServer`
// does about ending (the app's delegate, and the signal sources it sets up and resumes, taken from main.swift as
// written; no IMKServer, nothing else started), shows the real Settings window on the Privacy page, and types into the
// Words to hide field as the field editor takes keystrokes (no Return). Then, as the user would: SIGTERM ends the input
// method, or the focus leaves the field (Tab to the next control, a click on no field) while Settings stays open on the
// Privacy page. The child's home is a folder of the test's (the config file is never the user's), its keychain an
// in-memory one and the window looks up no keys (`SettingsModel.looksUpKeys`): nothing asks the user's keychain or the
// network. The child is never made the active app (macOS doesn't grant it to a test's process), so its window is never
// key: another app taking the focus, the issue's trigger, can't be shown here; Tab and a click away can.

@Suite(.serialized)
struct Issue51Tests {
    /// Typed without Return, then the input method gets SIGTERM (logging out, an update, `make install`): the word is in
    /// config.json once it has ended, and what `@improve` sends hides it.
    @Test func aWordTypedWithoutReturnIsSavedWhenSIGTERMEndsTheInputMethod() throws {
        let report = try Issue51Child.run(.sigterm)
        #expect(report.typed == Issue51Child.typed, "the field shows what was typed: \(report)")
        #expect(report.saved?.contains(Issue51Child.word) == true,
                "SIGTERM ended the input method and dropped \"\(Issue51Child.word)\" typed in Words to hide without Return: \(report)")
        #expect(report.saved?.contains(Issue51Child.before) == true, "the word already there stays: \(report)")
        #expect(report.hides, "\"\(Issue51Child.request)\" is sent with \"\(Issue51Child.word)\" as typed: \(report)")
    }

    /// Typed without Return, then the focus leaves the field (`way`), Settings left open on the Privacy page: the word is
    /// in config.json (what the input method reads for each request) right away, and what `@improve` sends hides it.
    @Test(arguments: Issue51Child.Mode.focusLost)
    func aWordTypedWithoutReturnIsSavedWhenTheFieldLosesFocus(_ way: Issue51Child.Mode) throws {
        let report = try Issue51Child.run(way)
        #expect(report.typed == Issue51Child.typed, "the field shows what was typed: \(report)")
        #expect(report.left == true, "the field lost the focus: \(report)")
        #expect(report.saved?.contains(Issue51Child.word) == true,
                "the focus left Words to hide (\(way.title)) and \"\(Issue51Child.word)\" typed without Return isn't saved: \(report)")
        #expect(report.hides, "\"\(Issue51Child.request)\" is sent with \"\(Issue51Child.word)\" as typed: \(report)")
    }
}

enum Issue51Child {
    /// What config.json's Words to hide has before: what the field shows when the page opens.
    static let before = "Acme"
    /// The word the user adds.
    static let word = "ProjectX"
    /// What the user types over the field, without Return.
    static let typed = "Acme, ProjectX"
    /// The text `@improve` is run on in another app.
    static let request = "ProjectX ships on Monday"

    /// What happens once the field is typed in.
    enum Mode: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// SIGTERM: logging out, an update, `make install`.
        case sigterm
        /// Tab: the focus goes to the next control.
        case tab
        /// A click on no field: the window itself takes the focus.
        case click
        var testDescription: String { rawValue }

        static let focusLost: [Mode] = [.tab, .click]

        var title: String {
            switch self {
            case .sigterm: "SIGTERM"
            case .tab: "Tab to the next control"
            case .click: "a click outside the field"
            }
        }
    }

    struct Report: CustomStringConvertible {
        /// What the field showed once typed in (nil: the child never got there).
        var typed: String?
        /// Whether the field had lost the focus (nil: not asked).
        var left: Bool?
        /// `redaction.customWords` in config.json once the child has ended.
        var saved: [String]?
        /// What `@improve` would send for `request`, hidden with config.json's settings as they are then.
        var sent: String?
        var status: Int32
        var output: String
        var hides: Bool { sent.map { !$0.localizedCaseInsensitiveContains(Issue51Child.word) } ?? false }
        var description: String {
            "field showed \(typed.map { "\"\($0)\"" } ?? "nothing"), "
                + "config.json's Words to hide \(saved.map { "\($0)" } ?? "unreadable"), sent \(sent.map { "\"\($0)\"" } ?? "nothing") "
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

    static func run(_ mode: Mode) throws -> Report {
        let executable = try compiled.get()
        let fm = FileManager.default
        // The child's home: its config.json there, never the user's.
        let home = fm.temporaryDirectory.appendingPathComponent("issue51-home-\(UUID().uuidString)", isDirectory: true)
        let file = home.appendingPathComponent(".config/allinoneime/config.json")
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        var config = Config.default
        config.uiLanguage = "en"
        config.redaction = RedactionSettings(enabled: true, customWords: [before])
        try config.write(to: file)

        let result = try command(executable, [mode.rawValue, before, typed],
                                 environment: ["CFFIXED_USER_HOME": home.path, "HOME": home.path], timeout: 60)
        let lines = result.output.split(separator: "\n")
        let typed = lines.last(where: { $0.hasPrefix("TYPED ") }).map { String($0.dropFirst("TYPED ".count)) }
        let left = lines.last(where: { $0.hasPrefix("LEFT ") }).map { $0 == "LEFT true" }
        let saved = try? Config.load(from: file)
        var redaction = saved.flatMap { Redaction($0.redaction) }
        return Report(typed: typed, left: left, saved: saved?.redaction.customWords, sent: redaction?.hide(request),
                      status: result.status, output: result.output)
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
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue51-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let harness = String(main[..<cut.upperBound])
            + Issue51Harness.swift.replacingOccurrences(of: "SIGNAL_SET_UP", with: signalSetUp(main))
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
        let executable = scratch.appendingPathComponent("issue51")
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
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue51-\(UUID().uuidString).log")
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
/// the Settings window on the Privacy page, Words to hide typed in, then what the mode says.
private enum Issue51Harness {
    static let swift = #"""

// MARK: - Issue #51's child (in place of main.swift's dispatch)

// Never the user's keychain: an in-memory one, and the window looks up no keys (as the self-test has it).
Platform.current.secrets = .inMemory()
MainActor.assumeIsolated { SettingsModel.looksUpKeys = false }

@MainActor
enum Issue51Child {
    static let mode = arguments.count > 0 ? arguments[0] : ""
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
        SettingsWindow.shared.show(page: .privacy)
        find(until: Date().addingTimeInterval(20))
    }

    static func textFields(in view: NSView?) -> [NSTextField] {
        guard let view else { return [] }
        return ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap { textFields(in: $0) }
    }

    static func allTextFields() -> [NSTextField] {
        NSApp.windows.filter(\.isVisible).flatMap { textFields(in: $0.contentView) }
    }

    /// The editable field showing `before` (Words to hide), once the page is laid out.
    static func find(until deadline: Date) {
        for window in NSApp.windows where window.isVisible {
            if let field = textFields(in: window.contentView).first(where: { $0.isEditable && $0.isEnabled && $0.stringValue == before }) {
                type(into: field, in: window)
                return
            }
        }
        guard Date() < deadline else {
            say("FAIL no field shows \"\(before)\" on the Privacy page; fields: \(allTextFields().map { "\"\($0.stringValue)\"" })")
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
                then(field, editor, in: window)
            }
        }
    }

    /// Whether `field` is being edited (its field editor is the window's first responder).
    static func editing(_ field: NSTextField, in window: NSWindow) -> Bool {
        guard let editor = field.currentEditor() else { return false }
        return window.firstResponder === editor
    }

    static func then(_ field: NSTextField, _ editor: NSTextView, in window: NSWindow) {
        switch mode {
        case "sigterm":
            // Logging out, `make install`: SIGTERM to the process (here sent by itself, once typed in).
            kill(getpid(), SIGTERM)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                MainActor.assumeIsolated {
                    say("FAIL SIGTERM didn't end the input method")
                    exit(4)
                }
            }
        case "tab", "click":
            if mode == "tab" {
                editor.insertTab(nil)  // Tab: the next control takes the focus
            } else {
                _ = window.makeFirstResponder(nil)  // a click on no field: the window takes it
            }
            // Settings stays open on the Privacy page; the input method reads config.json as it is a moment later (the
            // next request), then ends without anything saving (no window closed, no termination).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    say("LEFT \(!editing(field, in: window))")
                    _exit(0)
                }
            }
        default:
            say("FAIL unknown mode: \(mode)")
            exit(2)
        }
    }
}

// As `runServer` does it: the app's delegate, the signals set up; no IMKServer, nothing else started.
let issue51App = NSApplication.shared
issue51App.setActivationPolicy(.accessory)
issue51App.delegate = IMEAppDelegate.shared
SIGNAL_SET_UP
DispatchQueue.main.async { MainActor.assumeIsolated { Issue51Child.start() } }
issue51App.run()
exit(0)
"""#
}
