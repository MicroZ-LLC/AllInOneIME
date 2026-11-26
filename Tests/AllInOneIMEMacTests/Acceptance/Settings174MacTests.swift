import AllInOneIMECore
import Foundation
import Testing

/// #174's headless seam is the page's `AIPickerState`: `choosing: Bool`, `visibleGroups`,
/// `change()`, `cancel()`, `pick(_:)`, and `show(search:target:)`. `visibleGroups` is empty
/// while collapsed and equals `AIChoice.groups` while choosing. `SettingsModel.aiCardsShown()`
/// checks only those visible choices through an injectable `cliChecks: ([SessionAgent]) -> Void`
/// closure. The view calls it on page entry and when choosing changes. The Cancel button's
/// `.keyboardShortcut(.cancelAction)` makes Esc take the same `cancel()` path. These seams let
/// the real page state be tested with no window server, user config, CLI, or network request.
@Suite(.serialized)
struct Settings174MacTests {
    @Test func collapsedPageAndChoosingShowTheRightChoices() throws {
        let report = try Settings174Child.report.get()
        for language in ["en", "zh"] {
            #expect(report["COLLAPSED\t\(language)"] == "0::openai", "Only the current AI belongs in the collapsed row")
            #expect(report["OPEN\t\(language)"] == "1:openai", "Change opens choosing without changing the AI")
            #expect(report["GROUPED\t\(language)"] == report["EXPECTED\t\(language)"],
                    "Choosing shows every offered card, including the current AI, in AIChoice.groups order")
            #expect(report["CURRENT_COUNT\t\(language)"] == "1", "The current AI has exactly one highlighted card")
        }
    }

    @Test func pickCancelEscapeAndReturnToPage() throws {
        let report = try Settings174Child.report.get()
        for language in ["en", "zh"] {
            #expect(report["CANCEL\t\(language)"] == "0:openai:", "Cancel keeps the AI and collapses")
            #expect(report["ESCAPE\t\(language)"] == "0:openai:", "Esc takes Cancel's path")
            #expect(report["PICK\t\(language)"] == "0:kiroSession:", "A card chooses its AI and collapses")
            #expect(report["RETURN\t\(language)"] == "0:kiroSession:", "Returning to AI starts collapsed")
        }
    }

    @Test func searchForAnotherAISettingOpensAndScrollsToItsCard() throws {
        let report = try Settings174Child.report.get()
        for language in ["en", "zh"] {
            #expect(report["SEARCH_KIRO\t\(language)"] == "1:kiroSession")
            #expect(report["SEARCH_BEDROCK\t\(language)"] == "1:bedrock")
            #expect(report["SEARCH_CURRENT\t\(language)"] == "0:")
        }
        #expect(report["SEARCH_MODEL\ten"] == "1:kiroSession", "The settings-search navigation uses the page state")
    }

    @Test func signInChecksFollowTheVisibleChoices() throws {
        let report = try Settings174Child.report.get()
        #expect(report["CLI_COLLAPSED\ten"] == "claude", "Only the chosen CLI is checked while collapsed")
        #expect(report["CLI_CHOOSING\ten"] == report["CLI_EXPECTED\ten"], "Choosing checks the offered CLIs")
        #expect(report["CLI_RETURN\ten"] == "claude", "Returning to the page checks only the chosen CLI")
    }

    @Test func pageUsesTheChosenRowAndCancelKeyboardAction() throws {
        let sources = Settings121Child.repository.appendingPathComponent("Sources/AllInOneIME")
        let picker = try String(contentsOf: sources.appendingPathComponent("AIPicker.swift"), encoding: .utf8)
        let page = try String(contentsOf: sources.appendingPathComponent("SettingsWindow.swift"), encoding: .utf8)
        let choices = try String(contentsOf: sources.appendingPathComponent("ClaudeSessionSettings.swift"), encoding: .utf8)
        let hasChange = picker.contains("tr(\"更换 ▾\", \"Change ▾\")")
        let hasCancel = picker.contains("tr(\"取消\", \"Cancel\")")
        let hasEscape = picker.contains(".keyboardShortcut(.cancelAction)")
        let hasChosenRow = page.contains("AIChosenRow(choice: chosen")
        let hasChosenSettings = page.contains("switch chosen")
        let hasGrid = choices.contains("AIChoicesGrid(chosen:")
        #expect(hasChange, "The current row needs Change in both languages")
        #expect(hasCancel, "Choosing needs Cancel at the top")
        #expect(hasEscape, "Esc must use Cancel")
        #expect(hasChosenRow, "The collapsed row shows the chosen AI")
        #expect(hasChosenSettings, "The rows below the chosen AI must be its own settings")
        #expect(hasGrid, "Choosing uses the grouped cards")
    }
}

private enum Settings174Child {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static let report: Result<[String: String], Error> = Result { try run() }

    static func run() throws -> [String: String] {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("settings174-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let home = scratch.appendingPathComponent("home", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let repository = Settings121Child.repository
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift dispatch not found") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + harness).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let executable = scratch.appendingPathComponent("settings174")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else {
            let errors = Set(swift.output.split(separator: "\n").filter { $0.contains("error:") })
            throw Failure(description: "The #174 page seam could not compile:\n\(errors.joined(separator: "\n"))")
        }
        let output = scratch.appendingPathComponent("output.log")
        fm.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = repository
        process.environment = ProcessInfo.processInfo.environment.merging(["CFFIXED_USER_HOME": home.path, "HOME": home.path]) { $1 }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate(); throw Failure(description: "The #174 page child timed out") }
        let lines = try String(contentsOf: output, encoding: .utf8)
        guard process.terminationStatus == 0 else { throw Failure(description: "The #174 page child failed:\n\(lines)") }
        return Dictionary(uniqueKeysWithValues: lines.split(separator: "\n").compactMap { line -> (String, String)? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3 else { return nil }
            return (fields[0] + "\t" + fields[1], fields[2])
        })
    }

    static let harness = #"""

// MARK: - Settings174MacTests' child (in place of main.swift's dispatch)
Platform.current.secrets = .inMemory()
MainActor.assumeIsolated { SettingsModel.looksUpKeys = false }
MainActor.assumeIsolated {
    let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
    guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
        print("FAIL: config is outside the test home")
        exit(3)
    }
    func ids(_ groups: AIPickerState.Groups) -> String { groups.flatMap(\.choices).map(\.id).joined(separator: ",") }
    func grouped(_ groups: AIPickerState.Groups) -> String {
        groups.map { $0.group.rawValue + ":" + $0.choices.map(\.id).joined(separator: ",") }.joined(separator: ";")
    }
    for language in ["en", "zh"] {
        UIText.choice = language
        let chosen = AIChoice.provider(.openai)
        let groups = AIChoice.groups(hosted: false, apple: .available, keeping: chosen)
        var picker = AIPickerState(chosen: chosen, groups: groups)
        print("COLLAPSED\t\(language)\t\(picker.choosing ? 1 : 0):\(ids(picker.visibleGroups)):\(picker.chosen.id)")
        picker.change()
        print("OPEN\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.chosen.id)")
        print("GROUPED\t\(language)\t\(grouped(picker.visibleGroups))")
        print("EXPECTED\t\(language)\t\(grouped(groups))")
        print("CURRENT_COUNT\t\(language)\t\(picker.visibleGroups.flatMap(\.choices).filter { $0 == chosen }.count)")
        picker.cancel()
        print("CANCEL\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.chosen.id):\(ids(picker.visibleGroups))")
        picker.change()
        picker.cancel() // Esc invokes the same action through .cancelAction on the view.
        print("ESCAPE\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.chosen.id):\(ids(picker.visibleGroups))")
        picker.change()
        picker.pick(.cli(.kiro))
        print("PICK\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.chosen.id):\(ids(picker.visibleGroups))")
        picker.show(search: nil, target: nil)
        print("RETURN\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.chosen.id):\(ids(picker.visibleGroups))")
        picker = AIPickerState(chosen: chosen, groups: groups)
        picker.show(search: "kiro", target: nil)
        print("SEARCH_KIRO\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.scrollTarget?.id ?? "")")
        picker.show(search: nil, target: .provider(.bedrock))
        print("SEARCH_BEDROCK\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.scrollTarget?.id ?? "")")
        picker.show(search: nil, target: chosen)
        print("SEARCH_CURRENT\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.scrollTarget?.id ?? "")")
    }
    UIText.choice = "en"
    let model = SettingsModel(persists: false)
    model.choose(.provider(.openai))
    model.point(at: .provider, search: "kiro")
    print("SEARCH_MODEL\ten\t\(model.aiCards.choosing ? 1 : 0):\(model.aiPicker.scrollTarget?.id ?? "")")
    model.changeAICards { $0.show(search: nil, target: nil) }
    model.choose(.cli(.claude))
    var checked: [[SessionAgent]] = []
    model.cliChecks = { checked.append($0) }
    model.aiPageShown()
    print("CLI_COLLAPSED\ten\t\(checked.last?.map(\.rawValue).joined(separator: ",") ?? "")")
    model.changeAICards { $0.change() }
    model.aiPageShown()
    print("CLI_CHOOSING\ten\t\(checked.last?.map(\.rawValue).joined(separator: ",") ?? "")")
    print("CLI_EXPECTED\ten\t\(model.aiCards.visibleGroups.flatMap(\.choices).compactMap(\.agent).map(\.rawValue).joined(separator: ","))")
    model.changeAICards { $0.cancel() }
    model.aiPageShown()
    print("CLI_RETURN\ten\t\(checked.last?.map(\.rawValue).joined(separator: ",") ?? "")")
    fflush(stdout)
}
exit(0)
"""#
}
