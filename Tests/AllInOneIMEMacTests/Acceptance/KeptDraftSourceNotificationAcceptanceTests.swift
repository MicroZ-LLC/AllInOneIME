import AllInOneIMETestSupport
import Foundation
import Testing

// Issue #200, second cause: the system posts kTISNotifySelectedKeyboardInputSourceChanged on an app switch although the
// selected input source stays AllInOneIME, and DraftKeeper.watch() dropped the kept draft on it ("another input
// source selected") 5-290 ms after the switch. The draft must go only when the selected source is really no longer
// ours (`readers.sourceIsOurs()` false). The real sequence: draft typed, field loses the focus (kept), another app's
// controller activated with no text field, the notification posted with the source still ours.
// Same child/harness style as KeptDraftAppSwitchAcceptanceTests (its helpers `AppSwitch`, `KeptDrafts`).

@Suite(.serialized)
struct KeptDraftSourceNotificationAcceptanceTests {
    static func run(_ way: String) throws -> [String: String] { try KeptDraftSourceNotificationChild.run(way) }

    /// App switch, notification with our source still selected: still kept after the settle, shows again back in its field.
    @Test func sourceNotificationOnAppSwitchWithOurSourceKeepsTheDraft() throws {
        let report = try Self.run("srcnote-app-switch")
        #expect(report["keptOnLeave"] == "true", "\(report)")
        #expect(report["keptAfterNotification"] == "true",
                "dropped by the input-source notification though our source is still selected (drops: \(report["drops"] ?? "?")): \(report)")
        #expect(report["panelInOther"] == "false" && report["otherTyped"] == "", "\(report)")
        #expect(report["restored"] == "true" && report["input"] == "q",
                "back in its field, the draft didn't show again (drops: \(report["drops"] ?? "?")): \(report)")
        #expect(report["typed"] == "", "\(report)")
    }

    /// The same sequence, but the selected source is really another one: dropped, and it doesn't come back.
    @Test func sourceNotificationWithAnotherSourceSelectedDropsTheDraft() throws {
        let report = try Self.run("srcnote-not-ours")
        #expect(report["keptOnLeave"] == "true", "\(report)")
        #expect(report["keptAfterNotification"] == "false", "another source is selected and the draft is still kept: \(report)")
        #expect(report["restored"] == "false" && report["typed"] == "", "\(report)")
    }

    /// Screen locked, sleep, session resign still drop a draft kept across an app switch.
    @Test func lockSleepAndSessionResignStillDropAfterAnAppSwitch() throws {
        let report = try Self.run("srcnote-others")
        #expect(report["kept"] == "true,true,true,true", "\(report)")
        #expect(report["dropped"] == "true,true,true,true", "\(report)")
    }

    static let harness = #"""

    @MainActor
    enum SourceNote {
        static func appSwitch(ours: Bool) {
            let field = AppSwitch.kept()
            let (other, calculator) = AppSwitch.otherApp("com.example.calculator", element: nil)
            other.activateServer(calculator)
            KeptDrafts.ours = ours
            KeptDrafts.center.post(name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
            OffMain.pump(0.3)
            OffMain.say("keptAfterNotification", AppSwitch.first.session.keepsDraft)
            OffMain.say("panelInOther", AppSwitch.panel)
            OffMain.say("otherTyped", calculator.document)
            other.deactivateServer(calculator)
            KeptDrafts.ours = true
            AppSwitch.back(to: field)
        }

        static func others() {
            let workspace = NSWorkspace.shared.notificationCenter
            let endings: [(NotificationCenter, Notification.Name)] = [
                (workspace, NSWorkspace.sessionDidResignActiveNotification), (workspace, NSWorkspace.screensDidSleepNotification),
                (workspace, NSWorkspace.willSleepNotification), (KeptDrafts.center, Notification.Name("com.apple.screenIsLocked")),
            ]
            var (kept, dropped): ([Bool], [Bool]) = ([], [])
            for (center, name) in endings {
                KeptDrafts.make()
                let field = OffMainField()
                KeptDrafts.draft(in: field)
                KeptDrafts.controller.deactivateServer(field)
                let (other, calculator) = AppSwitch.otherApp("com.example.calculator", element: nil)
                other.activateServer(calculator)
                kept.append(KeptDrafts.controller.session.keepsDraft)
                center.post(name: name, object: nil)
                OffMain.pump(0.1)
                dropped.append(!KeptDrafts.controller.session.keepsDraft && !KeptDrafts.controller.composer.isComposing)
                other.deactivateServer(calculator)
            }
            OffMain.say("kept", kept.map(String.init).joined(separator: ","))
            OffMain.say("dropped", dropped.map(String.init).joined(separator: ","))
        }
    }

    MainActor.assumeIsolated {
        switch arguments.first ?? "" {
        case "srcnote-app-switch": SourceNote.appSwitch(ours: true)
        case "srcnote-not-ours": SourceNote.appSwitch(ours: false)
        case "srcnote-others": SourceNote.others()
        default: break
        }
        if (arguments.first ?? "").hasPrefix("srcnote-") { fflush(stdout); exit(0) }
    }

    """#
}

/// The child this suite's ways run in: compiled once, run once for each.
enum KeptDraftSourceNotificationChild {
    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    /// The child run in `way`: its "REPORT key=value" lines.
    static func run(_ way: String) throws -> [String: String] {
        let result = try launch([way])
        guard result.status == 0 else { throw Failure(description: "the child (\(way)) failed (\(result.status)):\n\(result.output)") }
        var report: [String: String] = [:]
        for line in result.output.split(separator: "\n") where line.hasPrefix("REPORT ") {
            let pair = line.dropFirst("REPORT ".count)
            guard let equals = pair.firstIndex(of: "=") else { continue }
            report[String(pair[..<equals])] = String(pair[pair.index(after: equals)...])
        }
        guard !report.isEmpty else { throw Failure(description: "the child (\(way)) reported nothing:\n\(result.output)") }
        return report
    }

    static func launch(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let executable = try compiled.get()
        let home = TestScratch.temporary("srcnote-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["CFFIXED_USER_HOME": home.path, "HOME": home.path]) { $1 }
        let log = TestScratch.temporary("srcnote-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: log)
        }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(90)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw Failure(description: "the child (\(arguments.first ?? "")) didn't finish in 90 s:\n\((try? String(contentsOf: log, encoding: .utf8)) ?? "")")
        }
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return (process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus, output)
    }

    /// main.swift up to its dispatch, then KeptDraftControllerTests' harness, this suite's (with its dispatch) and
    /// ControllerOffMainTests' (the fields and the controller's set-up they share).
    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = TestScratch.temporary("srcnote-child-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        let harnesses = KeptDraftControllerTests.harness + KeptDraftSourceNotificationAcceptanceTests.harness + KeptDraftAppSwitchAcceptanceTests.harness + ControllerOffMainChild.harness
        try (String(main[..<cut.upperBound]) + harnesses).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let executable = scratch.appendingPathComponent("srcnote")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else { throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n\(swift.output)") }
        return executable
    }
}
