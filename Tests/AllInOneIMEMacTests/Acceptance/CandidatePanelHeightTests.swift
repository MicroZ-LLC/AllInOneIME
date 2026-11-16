import Foundation
import Testing

/// Reproduction (AGENTS.md rule 20) of a suspicion from a code read: the candidate panel has no height limit (only an
/// @question conversation is kept to half the screen and scrolls), so with long text its lower rows and its footer go off
/// the bottom of the screen. `@improve` on a pasted paragraph: each of its seven rows (the paragraph, three versions, three
/// rewrites) is shortened to 280 characters (`SessionText.preview`) but wraps onto as many lines as that takes.
///
/// The real panel (Sources/AllInOneIME/CandidatePanel.swift, compiled here with the core into a small program, as
/// CandidatePanelLayoutTests does) shows the model the session makes for those results (`PanelPresenter`), at a caret
/// near the top of the screen and one near its bottom, on this Mac's main screen; it must fit on that screen. On a screen
/// tall enough for the whole panel nothing goes off, and this passes there: the Mac mini's (1280×720 points, 690 of them
/// usable) isn't, where the panel was 921 points tall and its bottom 231 points below the screen (2026-11-15).
@Suite(.serialized)
struct CandidatePanelHeightTests {
    @Test func improveOnALongParagraphKeepsTheLastRowsAndTheFooterOnTheScreen() throws {
        try PanelHeightChild.run("improve")
    }
}

private enum PanelHeightChild {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func run(_ scenario: String) throws {
        let result = try command(try compiled.get(), [scenario], timeout: 60)
        #expect(result.status == 0 && result.output.contains("HEIGHT PASS \(scenario)"), "\(result.output)")
    }

    /// The panel's own sources and `program`, against the core as `swift build` built it (.build/debug).
    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("panel-height-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let main = scratch.appendingPathComponent("Main.swift")
        try program.write(to: main, atomically: true, encoding: .utf8)
        let products = repository.appendingPathComponent(".build/debug")
        let modules = fm.fileExists(atPath: products.appendingPathComponent("Modules").path)
            ? products.appendingPathComponent("Modules") : products
        var objects: [String] = []
        for module in ["AllInOneIMECore", "AllInOneIMEText", "AllInOneIMEScriptEngine", "Crypto"] {
            let aggregate = products.appendingPathComponent(module + ".o")
            if fm.fileExists(atPath: aggregate.path) {
                objects.append(aggregate.path)
            } else {
                objects += try fm.contentsOfDirectory(at: products.appendingPathComponent(module + ".build"), includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "o" }.map(\.path)
            }
        }
        let sources = ["CandidatePanel.swift", "CommandIcons.swift", "LiveSettings.swift"]
            .map { repository.appendingPathComponent("Sources/AllInOneIME/" + $0).path }
        let executable = scratch.appendingPathComponent("height")
        let arguments = ["swiftc", "-swift-version", "5", "-parse-as-library", "-I", modules.path,
                         "-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels", "-framework", "AppKit"]
            + sources + [main.path] + objects + ["-o", executable.path]
        let result = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments, timeout: 300)
        guard result.status == 0 else { throw Failure(result.output) }
        return executable
    }

    static func command(_ executable: URL, _ arguments: [String], timeout: TimeInterval) throws -> (status: Int32, output: String) {
        // A file, not a pipe: the compiler's diagnostics can fill a pipe's buffer.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("panel-height-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: log) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw Failure("\(executable.lastPathComponent) timed out after \(Int(timeout))s")
        }
        try handle.synchronize()
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }

    static let program = #"""
    import AllInOneIMECore
    import AppKit
    import Foundation

    /// English mode's engine: librime in its ASCII mode, so every key of a command's text goes into the draft.
    final class EnglishMode: PinyinEngine {
        func processKey(_ keycode: Int32, mask: Int32) -> Bool { false }
        func takeCommit() -> String? { nil }
        func snapshot() -> EngineSnapshot { EngineSnapshot(isAsciiMode: true) }
        func selectCandidate(onPage index: Int) -> Bool { false }
        func deleteCandidate(onPage index: Int) -> Bool { false }
        func commitComposition() -> String? { nil }
        var rawInput: String { "" }
        func clearComposition() {}
        func setAsciiMode(_ on: Bool) {}
    }

    @MainActor enum Height {
        static var failures = 0
        static func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
            if !condition { failures += 1; print("FAIL: \(message())") }
        }

        /// A paragraph as one is pasted into `@improve` (about 300 characters), and what the AI answers for it: three
        /// English versions and the three default rewrites (润色, 简洁, 正式), each as long.
        static let paragraph = String(repeating: "这周我们把新版本的输入法交给了更多的同事试用，大家普遍觉得候选词更准了，但是在长句子里切换中英文的时候还是会卡一下，有时候候选框会挡住正在输入的那一行文字。", count: 4)
        static let version = String(repeating: "This week we gave the new version of the input method to more colleagues to try, and most of them felt that the candidates are more accurate, but switching between Chinese and English in long sentences still stalls a little. ", count: 3)
        static let rewrite = String(repeating: "本周新版输入法已交给更多同事试用，普遍反馈候选词更加准确；不过在长句中切换中英文时仍有短暂卡顿，候选框偶尔会遮住正在输入的文字。", count: 4)

        /// "@improve " and the paragraph typed in English mode, ⏎, its results in: the panel the session shows for them.
        static func improved() -> PanelModel? {
            let c = Composer(engine: EnglishMode(), voiceEnabled: false, actionKey: .enter)
            c.setInputMode(.english)
            func press(_ text: String) {
                _ = c.handleKeyDown(KeyEvent(keyCode: text == " " ? VirtualKey.space : 0, characters: text))
            }
            _ = c.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
            for character in "improve" { press(String(character)) }
            _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
            for character in paragraph { press(String(character)) }
            guard c.draft == "@improve " + paragraph else {
                print("the draft: \(c.draft)")
                return nil
            }
            let started = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r")).effects
            guard case let .startConversion(input: _, id: id)? = started.first else {
                print("not started: \(started)")
                return nil
            }
            // Each line its own (the same text twice is shown once).
            let result = ConversionResult(
                versions: ["In short: ", "To sum up: ", "Update: "].map { CandidateLine($0 + version) },
                rewrites: zip(RewriteStyle.defaultNames, ["总的来说，", "简单说，", "现汇报如下："]).map {
                    Rewrite(style: $0.0, line: CandidateLine($0.1 + rewrite))
                })
            _ = c.receive(result, isFinal: true, id: id)
            return PanelPresenter(config: .default, language: "zh-Hans").model(for: c)
        }

        static func improve() {
            guard let model = improved() else { return expect(false, "the results are up") }
            print("\(model.rows.count) rows, \(model.rows.map(\.text.count)) characters; footer \(model.footer) \(model.hints.map { $0.key + " " + $0.text })")
            let main = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let carets = [("a caret near the top of the screen", NSRect(x: main.minX + 200, y: main.maxY - 120, width: 1, height: 20)),
                          ("a caret near the bottom of the screen", NSRect(x: main.minX + 200, y: main.minY + 60, width: 1, height: 20))]
            for (name, caret) in carets {
                let panel = CandidatePanel()
                panel.show(model, anchor: caret)
                let frame = panel.frame
                let screen = CandidatePanel.screen(for: caret)?.visibleFrame ?? main
                // The footer's top on the screen (the view's y goes down from the panel's top).
                let footerTop = frame.maxY - panel.view.footerY
                print("\(name): the panel \(frame) on the screen's \(screen); the footer's top at y \(footerTop)")
                expect(frame.height <= screen.height,
                       "\(name): the panel is \(Int(frame.height)) points tall, the screen \(Int(screen.height))")
                expect(frame.minY >= screen.minY - 0.5,
                       "\(name): its bottom \(Int(screen.minY - frame.minY)) points below the screen's (the last rows and the footer)")
                expect(footerTop >= screen.minY && footerTop <= screen.maxY, "\(name): the footer off the screen, its top at y \(footerTop)")
                panel.hide()
            }
        }
    }

    @main struct HeightMain {
        @MainActor static func main() {
            let scenario = CommandLine.arguments.dropFirst().first ?? ""
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            switch scenario {
            case "improve": Height.improve()
            default:
                print("unknown scenario \(scenario)")
                exit(2)
            }
            print("\(Height.failures == 0 ? "HEIGHT PASS" : "HEIGHT FAIL") \(scenario): \(Height.failures) failures")
            exit(Height.failures == 0 ? 0 : 1)
        }
    }
    """#
}
