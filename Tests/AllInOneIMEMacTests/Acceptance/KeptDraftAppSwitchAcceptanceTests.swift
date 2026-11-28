import AllInOneIMETestSupport
import Foundation
import Testing

// Issue #200: a draft kept for the field that lost the focus without a click (#180, PR #188) never survives a switch
// to another app. The app switched to (⌘-Tab, or `osascript -e 'tell application "Calculator" to activate'`; also
// Finder, Activity Monitor: apps with no text field) activates its own controller, and that controller's
// `activateServer` (`takeFocus`) drops the kept draft at once ("another field took the focus"), though no other field
// took it. As the issue asks: another controller merely activated, where Accessibility tells no text field has the
// focus, leaves the draft kept, and it shows again when its own field (the same controller, the same element) takes
// the focus back, nothing of it typed anywhere. It goes when another field really takes the focus: Accessibility
// tells (after the settle) a different text field has it, or a key is typed or a draft started in the other field. It
// never shows in the other field. The other ways it goes are KeptDraftControllerTests'.
//
// The ways run in a child of their own: Sources/AllInOneIME compiled with main.swift's dispatch replaced, as
// ControllerOffMainTests does it, with that suite's harness and KeptDraftControllerTests' (their fields, their
// controllers, the Mac's answers replaced: `DraftKeeper.shared.readers`) and this one's ways. Each app is a controller
// and a field of the child's own; nothing is typed into another app, the panel is drawn invisible. What the child's
// log says of each kept draft dropped (`dropKeptDraft`'s reason) is reported with it (`drops`), read from the child's
// own log store, for the failure to tell why.

@Suite(.serialized)
struct KeptDraftAppSwitchAcceptanceTests {
    static func run(_ way: String) throws -> [String: String] { try KeptDraftAppSwitchChild.run(way) }

    /// 1. ⌘-Tab to an app with no text field (Calculator: Accessibility tells no text field has the focus): its
    /// controller activated keeps nothing of the draft from its field, and the draft stays kept, hidden, through the
    /// settle; back in the field it was typed in (the same controller, the same element), it shows again as it was.
    @Test func anotherAppWithNoTextFieldLeavesTheDraftKept() throws {
        let report = try Self.run("switch-no-field")
        #expect(report["keptOnLeave"] == "true", "the draft wasn't kept as its field lost the focus: \(report)")
        #expect(report["keptAtActivation"] == "true",
                "dropped as soon as the other app's controller was activated (drops: \(report["drops"] ?? "?")): \(report)")
        #expect(report["keptAfterSettle"] == "true",
                "dropped once Accessibility told no text field has the focus (drops: \(report["drops"] ?? "?")): \(report)")
        #expect(report["panelInOther"] == "false" && report["otherComposing"] == "false" && report["otherTyped"] == "",
                "the draft showed in, or went into, the other app: \(report)")
        #expect(report["restored"] == "true" && report["input"] == "q",
                "back in its field, the draft didn't show again (drops: \(report["drops"] ?? "?")): \(report)")
        #expect(report["typed"] == "", "the draft went into its field: \(report)")
    }

    /// 2. Another app whose field Accessibility tells, after the settle, is a different text field: that field took the
    /// focus, and the draft goes (nothing of it there, nor in its own field), and doesn't show when its field is back.
    @Test func anotherTextFieldTakingTheFocusDropsTheDraft() throws {
        let report = try Self.run("switch-text-field")
        #expect(report["keptOnLeave"] == "true", "\(report)")
        #expect(report["panelAtActivation"] == "false", "the draft showed in the other field: \(report)")
        #expect(report["keptAfterSettle"] == "false" && report["composingAfterSettle"] == "false",
                "another text field has the focus and the draft is still kept: \(report)")
        #expect(report["panelAfterSettle"] == "false" && report["otherComposing"] == "false" && report["otherTyped"] == "",
                "the draft showed in, or went into, the other field: \(report)")
        #expect(report["restored"] == "false" && report["typed"] == "", "\(report)")
    }

    /// 3. Another app's field typed in while the draft is kept (where Accessibility told no text field: a page whose
    /// app doesn't tell its fields): a key typed there, or a draft started there, drops the kept one. The key types as
    /// any, the new draft is its own; nothing of the kept draft shows or goes in there, and it doesn't come back.
    @Test(arguments: ["key", "draft"]) func typingInAnotherAppsFieldDropsTheDraft(_ way: String) throws {
        let report = try Self.run("switch-" + way)
        #expect(report["keptOnLeave"] == "true", "\(report)")
        #expect(report["kept"] == "false" && report["firstComposing"] == "false",
                "typed in another field and the draft is still kept: \(report)")
        if way == "key" {
            #expect(report["otherTyped"] == "s", "the other field holds \(report["otherTyped"] ?? "?"): \(report)")
            #expect(report["otherComposing"] == "false" && report["panel"] == "false", "\(report)")
        } else {
            // "@w" as the panel shows it while typed ("＠w" until its commands are listed, as any draft's first is).
            #expect(report["otherInput"]?.hasSuffix("w") == true && report["otherInput"]?.contains("q") == false,
                    "the other field's draft is \(report["otherInput"] ?? "?"): \(report)")
            #expect(report["otherTyped"] == "", "\(report)")
        }
        #expect(report["restored"] == "false" && report["typed"] == "", "\(report)")
    }

    /// 4. Away a while, in apps with no text field one after another (Calculator, Finder, Activity Monitor), switched
    /// to by `osascript … activate` (no key) or by ⌘-Tab (⌘ let go in the app switched to, as the Mac hands it over):
    /// back in the field it was typed in, the draft shows again, none of it typed into that field or any app's.
    @Test(arguments: ["activate", "command-tab"]) func backFromAppsWithNoTextFieldTheDraftShowsAgain(_ way: String) throws {
        let report = try Self.run("switch-back-" + way)
        #expect(report["keptOnLeave"] == "true", "\(report)")
        #expect(report["keptWhileAway"] == "true,true,true",
                "dropped while away, in the apps with no text field (drops: \(report["drops"] ?? "?")): \(report)")
        #expect(report["panelWhileAway"] == "false,false,false" && report["othersTyped"] == ",,",
                "the draft showed in, or went into, an app with no text field: \(report)")
        #expect(report["shownAtOnce"] == "false", "shown before Accessibility told which field it is: \(report)")
        #expect(report["restored"] == "true" && report["input"] == "q",
                "back in its field, the draft didn't show again (drops: \(report["drops"] ?? "?")): \(report)")
        #expect(report["typed"] == "", "the draft went into its field: \(report)")
    }

    /// After KeptDraftControllerTests' harness, before ControllerOffMainTests' (whose dispatch, after this one's, is
    /// never reached): the ways named "switch-…".
    static let harness = #"""

    import OSLog

    @MainActor
    enum AppSwitch {
        static var first: AllInOneIMEInputController { OffMain.controller }
        static var panel: Bool { CandidatePanel.shared.isShowing }

        /// What the log says of each kept draft dropped, in this run, oldest first: their reasons.
        static func drops() -> String {
            guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
                  let entries = try? store.getEntries(matching: NSPredicate(format: "subsystem == %@", "com.allinoneime.inputmethod.AllInOneIME"))
            else { return "the log can't be read" }
            let said = entries.compactMap { ($0 as? OSLogEntryLog)?.composedMessage }.filter { $0.hasPrefix("the kept draft is dropped") }
            return said.isEmpty ? "none" : said.joined(separator: "; ")
        }

        /// The first controller with "@q" typed into its field (element "A"), the field left without a click.
        static func kept() -> OffMainField {
            KeptDrafts.make()
            let field = OffMainField()
            KeptDrafts.draft(in: field)
            first.deactivateServer(field)
            OffMain.say("keptOnLeave", first.session.keepsDraft)
            return field
        }

        /// Another app's controller and its field (the first stays `OffMain.controller`), Accessibility telling `element`
        /// has the focus once it is activated.
        static func otherApp(_ app: String, element: String?) -> (AllInOneIMEInputController, OffMainField) {
            let other = KeptDrafts.second()
            let field = OffMainField()
            field.app = app
            KeptDrafts.element.set(element)
            return (other, field)
        }

        /// Back in the first field: the same element told, and what shows then.
        static func back(to field: OffMainField) {
            KeptDrafts.element.set("A")
            first.activateServer(field)
            OffMain.say("shownAtOnce", panel)
            OffMain.pump(0.3)
            OffMain.say("restored", KeptDrafts.restored)
            OffMain.say("input", first.session.panelModel().input?.text ?? "")
            OffMain.say("typed", field.document)
            OffMain.say("drops", drops())
        }

        static func noField() {
            let field = kept()
            let (other, calculator) = otherApp("com.example.calculator", element: nil)
            other.activateServer(calculator)
            OffMain.say("keptAtActivation", first.session.keepsDraft)
            OffMain.pump(0.3)
            OffMain.say("keptAfterSettle", first.session.keepsDraft)
            OffMain.say("panelInOther", panel)
            OffMain.say("otherComposing", other.composer.isComposing)
            OffMain.say("otherTyped", calculator.document)
            other.deactivateServer(calculator)
            back(to: field)
        }

        static func textField() {
            let field = kept()
            let (other, editor) = otherApp("com.example.editor", element: "B")
            other.activateServer(editor)
            OffMain.say("panelAtActivation", panel)
            OffMain.pump(0.3)
            OffMain.say("keptAfterSettle", first.session.keepsDraft)
            OffMain.say("composingAfterSettle", first.composer.isComposing)
            OffMain.say("panelAfterSettle", panel)
            OffMain.say("otherComposing", other.composer.isComposing)
            OffMain.say("otherTyped", editor.document)
            other.deactivateServer(editor)
            back(to: field)
        }

        static func typed(draft: Bool) {
            let field = kept()
            let (other, page) = otherApp("com.example.browser", element: nil)
            other.activateServer(page)
            OffMain.pump(0.3)
            OffMain.say("keptBeforeKey", first.session.keepsDraft)
            if draft {
                KeptDrafts.press("@", code: 19, shift: true, on: other, into: page)
                KeptDrafts.press("w", code: 13, on: other, into: page)
            } else {
                KeptDrafts.press("s", code: 1, on: other, into: page)
            }
            OffMain.pump(0.3)
            OffMain.say("kept", first.session.keepsDraft)
            OffMain.say("firstComposing", first.composer.isComposing)
            OffMain.say("otherComposing", other.composer.isComposing)
            OffMain.say("otherInput", other.session.panelModel().input?.text ?? "")
            OffMain.say("panel", panel)
            OffMain.say("otherTyped", page.document)
            other.deactivateServer(page)
            back(to: field)
        }

        /// Three apps with no text field in turn, a while in each; with ⌘-Tab, ⌘ let go in each one switched to.
        static func away(commandTab: Bool) {
            let field = kept()
            var (keptAway, shownAway, typedAway): ([Bool], [Bool], [String]) = ([], [], [])
            for app in ["com.example.calculator", "com.example.finder", "com.example.activitymonitor"] {
                let (other, client) = otherApp(app, element: nil)
                other.activateServer(client)
                if commandTab { KeptDrafts.flags(55, 0x100, on: other, in: client) }
                OffMain.pump(0.3)
                keptAway.append(first.session.keepsDraft)
                shownAway.append(panel)
                typedAway.append(client.document)
                other.deactivateServer(client)
            }
            OffMain.say("keptWhileAway", keptAway.map(String.init).joined(separator: ","))
            OffMain.say("panelWhileAway", shownAway.map(String.init).joined(separator: ","))
            OffMain.say("othersTyped", typedAway.joined(separator: ","))
            back(to: field)
        }

        static func run(_ way: String) -> Bool {
            switch way {
            case "switch-no-field": noField()
            case "switch-text-field": textField()
            case "switch-key": typed(draft: false)
            case "switch-draft": typed(draft: true)
            case "switch-back-activate": away(commandTab: false)
            case "switch-back-command-tab": away(commandTab: true)
            default: return false
            }
            return true
        }
    }

    MainActor.assumeIsolated {
        guard AppSwitch.run(arguments.first ?? "") else {
            print("FAIL way \(arguments.first ?? "")")
            exit(3)
        }
        fflush(stdout)
        exit(0)
    }

    """#
}

/// The child this suite's ways run in: compiled once, run once for each.
enum KeptDraftAppSwitchChild {
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
        let home = TestScratch.temporary("appswitch-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["CFFIXED_USER_HOME": home.path, "HOME": home.path]) { $1 }
        let log = TestScratch.temporary("appswitch-\(UUID().uuidString).log")
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
        let scratch = TestScratch.temporary("appswitch-child-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        let harnesses = KeptDraftControllerTests.harness + KeptDraftAppSwitchAcceptanceTests.harness + ControllerOffMainChild.harness
        try (String(main[..<cut.upperBound]) + harnesses).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let executable = scratch.appendingPathComponent("appswitch")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else { throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n\(swift.output)") }
        return executable
    }
}
