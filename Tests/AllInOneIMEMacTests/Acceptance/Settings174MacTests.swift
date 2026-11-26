import AllInOneIMECore
import Foundation
import Testing

/// #174's headless seam is the page's `AIPickerState`: `choosing: Bool`, `visibleGroups`,
/// `scrollTarget: AIChoice?`, `change()`, `cancel()`, `pick(_:)`, `pageLeft()`, and
/// `show(search:target:)`. `visibleGroups` is empty while collapsed and equals `AIChoice.groups`
/// while choosing. `pageLeft()` collapses choosing and clears `scrollTarget` when leaving the
/// page; `cancel()` and `pick(_:)` collapse and clear `scrollTarget`; `show(search:target:)`
/// collapses when `search` and `target` are `nil` or name the current AI, and opens choosing for
/// a generic AI search (`"Choose the AI"` / `"选择 AI"`) or another AI.
/// `SettingsModel.aiPageShown()` checks only the visible CLIs through an injectable
/// `cliChecks: ([SessionAgent]) -> Void` closure (none when collapsed with a non-CLI provider,
/// only the chosen CLI when collapsed with a CLI, and all offered CLIs while choosing). The view
/// calls it on page entry and when choosing changes. The Cancel button in `AIPicker.swift` carries
/// `.keyboardShortcut(.cancelAction)` on the same `Button` statement so Esc takes the same
/// `cancel()` path. These seams let the real page state be tested with no window server, user
/// config, CLI, or network request.
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
            #expect(report["CANCEL\t\(language)"] == "kiroSession->0:openai::",
                    "Cancel keeps the AI, collapses, and clears scrollTarget")
            #expect(report["PICK\t\(language)"] == "bedrock->0:kiroSession::",
                    "A card chooses its AI, collapses, and clears scrollTarget")
            #expect(report["RETURN\t\(language)"] == "1->0:kiroSession::",
                    "Leaving while choosing and returning starts collapsed")
        }
        let picker = try Self.stripLineComments(
            String(contentsOf: Settings121Child.repository.appendingPathComponent("Sources/AllInOneIME/AIPicker.swift"), encoding: .utf8)
        )
        let cancelButtons = Self.buttonStatements(in: picker).filter { $0.contains("tr(\"取消\", \"Cancel\"") }
        #expect(!cancelButtons.isEmpty, "Choosing needs a Cancel/取消 Button in AIPicker.swift")
        #expect(cancelButtons.contains { $0.contains(".keyboardShortcut(.cancelAction)") },
                "Esc must bind .keyboardShortcut(.cancelAction) on the Cancel Button itself")
    }

    @Test func searchForAnotherAISettingOpensAndScrollsToItsCard() throws {
        let report = try Settings174Child.report.get()
        for language in ["en", "zh"] {
            #expect(report["SEARCH_GENERIC\t\(language)"] == "1:", "Searching for Choose the AI / 选择 AI opens choices")
            #expect(report["SEARCH_KIRO\t\(language)"] == "1:kiroSession")
            #expect(report["SEARCH_BEDROCK\t\(language)"] == "1:bedrock")
            #expect(report["SEARCH_CURRENT_NAME\t\(language)"] == "0:",
                    "Searching for the current AI keeps the page collapsed")
            #expect(report["SEARCH_CURRENT\t\(language)"] == "0:")
        }
        #expect(report["SEARCH_MODEL\ten"] == "1:kiroSession", "The settings-search navigation uses the page state")
        #expect(report["SEARCH_MODEL_GENERIC\ten"] == "1:", "Generic AI search opens the choices through SettingsModel")
        #expect(report["SEARCH_MODEL_CURRENT\ten"] == "0:", "Searching for the current AI keeps SettingsModel collapsed")
    }

    @Test func signInChecksFollowTheVisibleChoices() throws {
        let report = try Settings174Child.report.get()
        let expectedAllCLIs = try #require(report["CLI_EXPECTED\ten"])
        #expect(!expectedAllCLIs.isEmpty, "Choosing must include the offered CLI agents")
        #expect(report["CLI_PROVIDER_COLLAPSED\ten"] == "", "No CLI is checked while collapsed with a non-CLI provider")
        #expect(report["CLI_PROVIDER_CHOOSING\ten"] == expectedAllCLIs, "Choosing from a non-CLI provider checks all offered CLIs")
        #expect(report["CLI_COLLAPSED\ten"] == "claude", "Only the chosen CLI is checked while collapsed")
        #expect(report["CLI_CHOOSING\ten"] == expectedAllCLIs, "Choosing checks all offered CLIs")
        #expect(report["CLI_RETURN\ten"] == "claude", "Leaving while choosing and returning checks only the chosen CLI")
    }

    @Test func pageUsesTheChosenRowAndRemovesTheFold() throws {
        let sources = Settings121Child.repository.appendingPathComponent("Sources/AllInOneIME")
        let picker = try Self.stripLineComments(String(contentsOf: sources.appendingPathComponent("AIPicker.swift"), encoding: .utf8))
        let page = try Self.stripLineComments(String(contentsOf: sources.appendingPathComponent("SettingsWindow.swift"), encoding: .utf8))
        let choices = try Self.stripLineComments(String(contentsOf: sources.appendingPathComponent("ClaudeSessionSettings.swift"), encoding: .utf8))
        let aiPage = page + "\n" + choices
        let aiCardSources = picker + "\n" + choices
        let allAISources = picker + "\n" + choices + "\n" + page
        #expect(picker.contains("tr(\"更换 ▾\", \"Change ▾\")"), "The current row needs Change in both languages")
        #expect(picker.contains("tr(\"取消\", \"Cancel\""), "Choosing needs Cancel at the top")
        #expect(aiPage.contains("AIChosenRow("), "The collapsed AI page uses AIChosenRow")
        #expect(aiPage.contains("AIChoicesGrid("), "Choosing uses AIChoicesGrid")
        #expect(!allAISources.contains("Other AIs"), "The #161 Other AIs fold text must be gone")
        #expect(!allAISources.contains("其他 AI"), "The #161 其他 AI fold text must be gone")
        #expect(!aiCardSources.contains("DisclosureGroup"), "The #161 DisclosureGroup fold for AI cards must be gone")
    }

    private static func stripLineComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var inString = false
            var escaped = false
            var previous: Character?
            for index in line.indices {
                let char = line[index]
                if inString {
                    if escaped {
                        escaped = false
                    } else if char == "\\" {
                        escaped = true
                    } else if char == "\"" {
                        inString = false
                    }
                } else if char == "\"" {
                    inString = true
                } else if char == "/", previous == "/" {
                    return String(line[..<line.index(before: index)])
                }
                previous = char
            }
            return String(line)
        }.joined(separator: "\n")
    }

    private static func buttonStatements(in code: String) -> [String] {
        var results: [String] = []
        var searchStart = code.startIndex
        while let range = code.range(of: "Button", range: searchStart..<code.endIndex) {
            searchStart = range.upperBound
            if range.lowerBound > code.startIndex {
                let before = code[code.index(before: range.lowerBound)]
                if before.isLetter || before.isNumber || before == "_" || before == "." { continue }
            }
            var idx = range.upperBound
            while idx < code.endIndex && (code[idx] == " " || code[idx] == "\t") { idx = code.index(after: idx) }
            guard idx < code.endIndex, code[idx] == "(" || code[idx] == "{" else { continue }
            var parenDepth = 0
            var braceDepth = 0
            var inString = false
            var escaped = false
            var end = idx
            while idx < code.endIndex {
                let char = code[idx]
                if inString {
                    if escaped {
                        escaped = false
                    } else if char == "\\" {
                        escaped = true
                    } else if char == "\"" {
                        inString = false
                    }
                    idx = code.index(after: idx)
                    end = idx
                    continue
                }
                if char == "\"" {
                    inString = true
                } else if char == "(" {
                    parenDepth += 1
                } else if char == ")" {
                    parenDepth = max(0, parenDepth - 1)
                } else if char == "{" {
                    braceDepth += 1
                } else if char == "}" {
                    if braceDepth == 0 { break }
                    braceDepth -= 1
                } else if parenDepth == 0 && braceDepth == 0 && (char == "\n" || char == ";") {
                    if char == ";" { break }
                    var peek = code.index(after: idx)
                    while peek < code.endIndex && code[peek].isWhitespace { peek = code.index(after: peek) }
                    if peek >= code.endIndex || (code[peek] != "." && !code[peek...].hasPrefix("label:")) { break }
                }
                idx = code.index(after: idx)
                end = idx
            }
            results.append(String(code[range.lowerBound..<end]))
        }
        return results
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
        picker.show(search: "kiro", target: nil)
        let cancelTarget = picker.scrollTarget?.id ?? ""
        picker.cancel()
        print("CANCEL\t\(language)\t\(cancelTarget)->\(picker.choosing ? 1 : 0):\(picker.chosen.id):\(ids(picker.visibleGroups)):\(picker.scrollTarget?.id ?? "")")
        picker.show(search: nil, target: .provider(.bedrock))
        let pickTarget = picker.scrollTarget?.id ?? ""
        picker.pick(.cli(.kiro))
        print("PICK\t\(language)\t\(pickTarget)->\(picker.choosing ? 1 : 0):\(picker.chosen.id):\(ids(picker.visibleGroups)):\(picker.scrollTarget?.id ?? "")")
        picker.change()
        let wasChoosing = picker.choosing
        picker.pageLeft()
        picker.show(search: nil, target: nil)
        print("RETURN\t\(language)\t\(wasChoosing ? 1 : 0)->\(picker.choosing ? 1 : 0):\(picker.chosen.id):\(ids(picker.visibleGroups)):\(picker.scrollTarget?.id ?? "")")
        picker = AIPickerState(chosen: chosen, groups: groups)
        let genericSearch = language == "zh" ? "选择 AI" : "Choose the AI"
        picker.show(search: genericSearch, target: nil)
        print("SEARCH_GENERIC\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.scrollTarget?.id ?? "")")
        picker.show(search: "kiro", target: nil)
        print("SEARCH_KIRO\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.scrollTarget?.id ?? "")")
        picker.show(search: nil, target: .provider(.bedrock))
        print("SEARCH_BEDROCK\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.scrollTarget?.id ?? "")")
        picker.show(search: "openai", target: nil)
        print("SEARCH_CURRENT_NAME\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.scrollTarget?.id ?? "")")
        picker.show(search: nil, target: chosen)
        print("SEARCH_CURRENT\t\(language)\t\(picker.choosing ? 1 : 0):\(picker.scrollTarget?.id ?? "")")
    }
    UIText.choice = "en"
    let model = SettingsModel(persists: false)
    model.choose(.provider(.openai))
    model.point(at: .provider, search: "kiro")
    print("SEARCH_MODEL\ten\t\(model.aiCards.choosing ? 1 : 0):\(model.aiPicker.scrollTarget?.id ?? "")")
    model.point(at: .provider, search: "Choose the AI")
    print("SEARCH_MODEL_GENERIC\ten\t\(model.aiCards.choosing ? 1 : 0):\(model.aiPicker.scrollTarget?.id ?? "")")
    model.point(at: .provider, search: "openai")
    print("SEARCH_MODEL_CURRENT\ten\t\(model.aiCards.choosing ? 1 : 0):\(model.aiPicker.scrollTarget?.id ?? "")")
    var checked: [[SessionAgent]] = []
    model.cliChecks = { checked.append($0) }
    func checkedAgents() -> String { checked.flatMap { $0 }.map(\.rawValue).joined(separator: ",") }
    model.choose(.provider(.openai))
    model.changeAICards { $0.show(search: nil, target: nil) }
    checked.removeAll()
    model.aiPageShown()
    print("CLI_PROVIDER_COLLAPSED\ten\t\(checkedAgents())")
    model.changeAICards { $0.change() }
    checked.removeAll()
    model.aiPageShown()
    print("CLI_PROVIDER_CHOOSING\ten\t\(checkedAgents())")
    print("CLI_EXPECTED\ten\t\(model.aiCards.visibleGroups.flatMap(\.choices).compactMap(\.agent).map(\.rawValue).joined(separator: ","))")
    model.choose(.cli(.claude))
    model.changeAICards { $0.show(search: nil, target: nil) }
    checked.removeAll()
    model.aiPageShown()
    print("CLI_COLLAPSED\ten\t\(checkedAgents())")
    model.changeAICards { $0.change() }
    checked.removeAll()
    model.aiPageShown()
    print("CLI_CHOOSING\ten\t\(checkedAgents())")
    model.changeAICards { $0.pageLeft(); $0.show(search: nil, target: nil) }
    checked.removeAll()
    model.aiPageShown()
    print("CLI_RETURN\ten\t\(checkedAgents())")
    fflush(stdout)
}
exit(0)
"""#
}
