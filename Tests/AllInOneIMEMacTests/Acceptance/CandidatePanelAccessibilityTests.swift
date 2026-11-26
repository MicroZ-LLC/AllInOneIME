import AllInOneIMETestSupport
import Foundation
import Testing

/// The executable's CandidateView is compiled with the core, then constructed offscreen. No window or input field is
/// opened. The model is the same PanelModel that PanelPresenter gives the Mac panel. Expected implementation seams:
/// CandidateView.Palette.footerColor is the color actually used to draw footer text, and
/// CandidateView.announceAccessibility is an injectable (String) -> Void closure whose default posts the
/// NSAccessibility announcement. The closure lets this test observe announcements without a window server.
@Suite(.serialized)
struct CandidatePanelAccessibilityTests {
    @Test func candidateRowsExposeLabelsAndOneSelection() throws {
        try AccessibilityChild.run("rows", program: .structure)
    }

    @Test func statusAndFooterAreAccessibleChildren() throws {
        try AccessibilityChild.run("messages", program: .structure)
    }

    @Test func smallTextUsesReadableColorsInBothContrastModes() throws {
        try AccessibilityChild.run("colors", program: .colors)
    }

    @Test func selectionAndStreamingResultsAreAnnouncedAtMostOncePerBurst() throws {
        try AccessibilityChild.run("announcements", program: .announcements)
    }
}

private enum AccessibilityChild {
    enum Program { case structure, colors, announcements }

    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let structure = Result { try compile(structureProgram) }
    static let colors = Result { try compile(colorsProgram) }
    static let announcements = Result { try compile(announcementProgram) }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func run(_ scenario: String, program: Program) throws {
        let executable: URL
        switch program {
        case .structure: executable = try structure.get()
        case .colors: executable = try colors.get()
        case .announcements: executable = try announcements.get()
        }
        let result = try command(executable, [scenario], timeout: 30)
        #expect(result.status == 0 && result.output.contains("ACCESSIBILITY PASS"), "\(result.output)")
    }

    static func command(_ executable: URL, _ arguments: [String], timeout: TimeInterval) throws -> (status: Int32, output: String) {
        let log = TestScratch.temporary("candidate-panel-accessibility-\(UUID().uuidString).log")
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
            throw Failure("accessibility child timed out")
        }
        try handle.synchronize()
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }

    static func compile(_ program: String) throws -> URL {
        let scratch = TestScratch.temporary("candidate-panel-accessibility-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let main = scratch.appendingPathComponent("Main.swift")
        try program.write(to: main, atomically: true, encoding: .utf8)
        let sources = ["CandidatePanel.swift", "CommandIcons.swift", "LiveSettings.swift"]
            .map { repository.appendingPathComponent("Sources/AllInOneIME/" + $0).path }
        let executable = scratch.appendingPathComponent("accessibility")
        let result = try SourceCompiler.compile(repository: repository, sources: sources + [main.path],
            executable: executable, parseAsLibrary: true, timeout: 300)
        guard result.status == 0 else { throw Failure(result.output) }
        return executable
    }

    static let structureProgram = #"""
    import AppKit
    import AllInOneIMECore

    @MainActor enum Check {
        static var failures = 0
        static func expect(_ condition: Bool, _ message: String) {
            if !condition { failures += 1; print("FAIL: " + message) }
        }
        static func label(_ item: Any) -> String {
            if let element = item as? NSAccessibilityElement { return element.accessibilityLabel() ?? "" }
            if let view = item as? NSView { return view.accessibilityLabel() ?? "" }
            return ""
        }
        static func role(_ item: Any) -> NSAccessibility.Role? {
            if let element = item as? NSAccessibilityElement { return element.accessibilityRole() }
            if let view = item as? NSView { return view.accessibilityRole() }
            return nil
        }
        static func selected(_ item: Any) -> Bool {
            if let element = item as? NSAccessibilityElement { return element.isAccessibilitySelected() }
            if let view = item as? NSView { return view.isAccessibilitySelected() }
            return false
        }
        static func rows() {
            let view = CandidateView()
            view.model = PanelModel(rows: [
                .init(label: "1", text: "你好", kind: .candidate),
                .init(label: "2", text: "您好", kind: .candidate)], highlighted: 1)
            expect(view.accessibilityRole() == .list, "candidate view has list role")
            expect(!(view.accessibilityLabel() ?? "").isEmpty, "candidate list has a name")
            let children = view.accessibilityChildren() ?? []
            expect(children.count == 2, "one accessibility child per visible row")
            guard children.count == 2 else { return }
            for (index, child) in children.enumerated() {
                expect(role(child) == .row || role(child) == .staticText, "child \(index) is a row or text")
                expect(label(child).contains("\(index + 1)"), "child \(index) includes its number hint")
                expect(label(child).contains(index == 0 ? "你好" : "您好"), "child \(index) includes its text")
                expect(selected(child) == (index == 1), "only highlighted row is selected")
            }
        }
        static func messages() {
            let view = CandidateView()
            view.model = PanelModel(status: .loading("Translating…"), footer: "⏎ insert")
            let children = view.accessibilityChildren() ?? []
            expect(children.contains { label($0).contains("Translating…") }, "status is an accessibility child")
            expect(children.contains { label($0).contains("⏎ insert") }, "footer is an accessibility child")
        }
    }

    @main struct Main {
        @MainActor static func main() {
            switch CommandLine.arguments.dropFirst().first {
            case "rows": Check.rows()
            case "messages": Check.messages()
            default: Check.expect(false, "unknown scenario")
            }
            if Check.failures == 0 { print("ACCESSIBILITY PASS") } else { exit(1) }
        }
    }
    """#

    static let colorsProgram = #"""
    import AppKit

    @main struct Main {
        @MainActor static func main() {
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                guard let appearance = NSAppearance(named: name) else { exit(2) }
                for increased in [false, true] {
                    let palette = CandidateView.palette(appearance: appearance, increaseContrast: increased)
                    let expected: NSColor = increased ? .labelColor : .secondaryLabelColor
                    if !palette.rowComment.isEqual(expected) || !palette.footerColor.isEqual(expected) {
                        print("FAIL: comment or footer color for \(name), increased=\(increased)")
                        exit(1)
                    }
                }
            }
            print("ACCESSIBILITY PASS")
        }
    }
    """#

    static let announcementProgram = #"""
    import AppKit
    import AllInOneIMECore

    @main struct Main {
        @MainActor static func main() {
            let view = CandidateView()
            var spoken: [String] = []
            view.announceAccessibility = { spoken.append($0) }
            let rows = [PanelModel.Row(label: "1", text: "你好", kind: .candidate),
                        PanelModel.Row(label: "2", text: "您好", kind: .candidate)]
            view.model = PanelModel(rows: rows, highlighted: 0)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            spoken.removeAll()
            view.model = PanelModel(rows: rows, highlighted: 1)
            view.model = PanelModel(rows: rows, highlighted: 0)
            view.model = PanelModel(rows: rows, highlighted: 1)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            guard spoken.count == 1, !spoken[0].isEmpty else {
                print("FAIL: rapid selection changes should make one nonempty announcement, got \(spoken)")
                exit(1)
            }
            spoken.removeAll()
            var updated = rows
            updated[1].text = "您"
            view.model = PanelModel(rows: updated, highlighted: 1)
            updated[1].text = "您好！"
            view.model = PanelModel(rows: updated, highlighted: 1)
            updated.append(.init(label: "3", text: "你好啊", kind: .candidate))
            view.model = PanelModel(rows: updated, highlighted: 1)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            guard spoken.count == 1, !spoken[0].isEmpty else {
                print("FAIL: streaming results should make one nonempty announcement, got \(spoken)")
                exit(1)
            }
            print("ACCESSIBILITY PASS")
        }
    }
    """#
}
