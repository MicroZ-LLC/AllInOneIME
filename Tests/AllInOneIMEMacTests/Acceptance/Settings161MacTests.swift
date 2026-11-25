import AllInOneIMECore
import Foundation
import Testing

/// #161's picker contract, exercised in a child compiled with the input method sources, as #121 does.
/// The implementer adds `AIPickerState` beside `AIChoiceSettings`: `init(chosen:groups:)`, `chosen`,
/// `isExpanded`, `otherGroups`, `rowTitle`, `accessibilityValue`, and `scrollTarget`; `toggle()`,
/// `pick(_:)`, and `show(search:target:)`. The view uses this state for its row, card list, and
/// navigation. `show` starts folded without a destination, and unfolds for the search's AI row,
/// an AI name, or a start/Doctor destination; `scrollTarget` names the matching other card.
/// This seam keeps the acceptance test independent of the window server and real apps.
@Suite(.serialized)
struct Settings161MacTests {
    @Test func otherAIsFoldOpenAndFoldAgainAfterPicking() throws {
        let report = try Settings161Child.report.get()
        for language in ["en", "zh"] {
            let count = try #require(Int(report["COUNT\t\(language)"] ?? ""))
            #expect(count > 0)
            #expect(report["DEFAULT\t\(language)"] == "0:", "The other cards must start hidden")
            #expect(report["OPEN\t\(language)"] == "1:\(count)", "Opening shows each other card")
            #expect(report["GROUPED\t\(language)"] == report["EXPECTED_GROUPS\t\(language)"],
                    "Opening preserves the other cards' groups and order")
            #expect(report["CLOSED\t\(language)"] == "0:", "Clicking the row again hides the cards")
            #expect(report["PICKED\t\(language)"] == "kiroSession:0:", "Picking changes the AI and folds the cards")
            #expect(report["RESHOWN\t\(language)"] == "0:", "The page starts folded when shown again")
        }
    }

    @Test func disclosureNamesItsCountAndAccessibilityState() throws {
        let report = try Settings161Child.report.get()
        for language in ["en", "zh"] {
            let count = try #require(report["COUNT\t\(language)"])
            let label = language == "en" ? "Other AIs (\(count))" : "其他 AI（\(count)）"
            #expect(report["ROW_CLOSED\t\(language)"] == label)
            #expect(report["ROW_OPEN\t\(language)"] == label)
            #expect(report["ACCESS_CLOSED\t\(language)"] == "collapsed")
            #expect(report["ACCESS_OPEN\t\(language)"] == "expanded")
        }
    }

    @Test func searchAndNavigationRevealTheRightCard() throws {
        let report = try Settings161Child.report.get()
        for language in ["en", "zh"] {
            #expect(report["SEARCH_AI\t\(language)"] == "1", "Choose the AI opens the list")
            #expect(report["SEARCH_KIRO\t\(language)"] == "1:kiroSession", "A provider name opens and targets its card")
            #expect(report["POINT_BEDROCK\t\(language)"] == "1:bedrock", "Start and Doctor can point at another card")
            #expect(report["POINT_CHOSEN\t\(language)"] == "0:", "The current card stays above the folded list")
        }
    }

    @Test func showingTheFoldedPageDoesNotInspectOtherCLIs() throws {
        let source = Settings121Child.repository.appendingPathComponent("Sources/AllInOneIME/ClaudeSessionSettings.swift")
        let code = try String(contentsOf: source, encoding: .utf8)
        #expect(!code.contains(".onAppear { model.aiPageShown() }"), "The folded page still refreshes every CLI on appear")
    }

    @Test func theRowUsesTheExistingDisclosureAccessibility() throws {
        let sources = Settings121Child.repository.appendingPathComponent("Sources/AllInOneIME")
        let picker = try String(contentsOf: sources.appendingPathComponent("AIPicker.swift"), encoding: .utf8)
        let settings = try String(contentsOf: sources.appendingPathComponent("ClaudeSessionSettings.swift"), encoding: .utf8)
        let code = picker + settings
        #expect(code.contains("DisclosureGroup"), "Other AIs is not a disclosure row")
        #expect(code.contains("RowDisclosureStyle()"), "The row does not use the existing VoiceOver disclosure style")
    }
}

private enum Settings161Child {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static let report: Result<[String: String], Error> = Result { try run() }

    static func run() throws -> [String: String] {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("settings161-\(UUID().uuidString)", isDirectory: true)
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
        let executable = scratch.appendingPathComponent("settings161")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else {
            let errors = Set(swift.output.split(separator: "\n").filter { $0.contains("error:") })
            throw Failure(description: "The #161 picker seam could not compile:\n\(errors.joined(separator: "\n"))")
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
        if process.isRunning { process.terminate(); throw Failure(description: "The #161 picker child timed out") }
        let lines = try String(contentsOf: output, encoding: .utf8)
        guard process.terminationStatus == 0 else { throw Failure(description: "The #161 picker child failed:\n\(lines)") }
        return Dictionary(uniqueKeysWithValues: lines.split(separator: "\n").compactMap { line -> (String, String)? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3 else { return nil }
            return (fields[0] + "\t" + fields[1], fields[2])
        })
    }

    static let harness = #"""

// MARK: - Settings161MacTests' child (in place of main.swift's dispatch)
Platform.current.secrets = .inMemory()
MainActor.assumeIsolated { SettingsModel.looksUpKeys = false }
MainActor.assumeIsolated {
    let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
    guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
        print("FAIL: config is outside the test home")
        exit(3)
    }
    for language in ["en", "zh"] {
        UIText.choice = language
        let chosen = AIChoice.provider(.openai)
        let groups = AIChoice.groups(hosted: false, apple: .available, keeping: chosen)
        var picker = AIPickerState(chosen: chosen, groups: groups)
        let count = groups.flatMap(\.choices).count - 1
        print("COUNT\t\(language)\t\(count)")
        print("DEFAULT\t\(language)\t\(picker.isExpanded ? 1 : 0):\(picker.otherGroups.flatMap(\.choices).map(\.id).joined(separator: ","))")
        print("ROW_CLOSED\t\(language)\t\(picker.rowTitle)")
        print("ACCESS_CLOSED\t\(language)\t\(picker.accessibilityValue)")
        picker.toggle()
        print("OPEN\t\(language)\t\(picker.isExpanded ? 1 : 0):\(picker.otherGroups.flatMap(\.choices).count)")
        let grouped = picker.otherGroups.map { $0.group.rawValue + ":" + $0.choices.map(\.id).joined(separator: ",") }.joined(separator: ";")
        print("GROUPED\t\(language)\t\(grouped)")
        let expectedGroups = groups.compactMap { group -> String? in
            let others = group.choices.filter { $0 != chosen }
            return others.isEmpty ? nil : group.group.rawValue + ":" + others.map(\.id).joined(separator: ",")
        }.joined(separator: ";")
        print("EXPECTED_GROUPS\t\(language)\t\(expectedGroups)")
        print("ROW_OPEN\t\(language)\t\(picker.rowTitle)")
        print("ACCESS_OPEN\t\(language)\t\(picker.accessibilityValue)")
        picker.toggle()
        print("CLOSED\t\(language)\t\(picker.isExpanded ? 1 : 0):\(picker.otherGroups.flatMap(\.choices).map(\.id).joined(separator: ","))")
        picker.toggle()
        picker.pick(.cli(.kiro))
        print("PICKED\t\(language)\t\(picker.chosen.id):\(picker.isExpanded ? 1 : 0):\(picker.otherGroups.flatMap(\.choices).map(\.id).joined(separator: ","))")
        picker.show(search: nil, target: nil)
        print("RESHOWN\t\(language)\t\(picker.isExpanded ? 1 : 0):\(picker.otherGroups.flatMap(\.choices).map(\.id).joined(separator: ","))")
        picker = AIPickerState(chosen: chosen, groups: groups)
        picker.show(search: "Choose the AI", target: nil)
        print("SEARCH_AI\t\(language)\t\(picker.isExpanded ? 1 : 0)")
        picker.show(search: "kiro", target: nil)
        print("SEARCH_KIRO\t\(language)\t\(picker.isExpanded ? 1 : 0):\(picker.scrollTarget?.id ?? "")")
        picker.show(search: nil, target: .provider(.bedrock))
        print("POINT_BEDROCK\t\(language)\t\(picker.isExpanded ? 1 : 0):\(picker.scrollTarget?.id ?? "")")
        picker.show(search: nil, target: chosen)
        print("POINT_CHOSEN\t\(language)\t\(picker.isExpanded ? 1 : 0):\(picker.scrollTarget?.id ?? "")")
    }
    fflush(stdout)
}
exit(0)
"""#
}
