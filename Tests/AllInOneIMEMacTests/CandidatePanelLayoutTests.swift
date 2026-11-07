import Foundation
import Testing

/// The candidate panel as the Mac draws it (`CandidateView`, Sources/AllInOneIME/CandidatePanel.swift): one @'s rows on
/// top and the pinyin candidates being composed on a line under them, just above the footer, below the caret or above
/// it. The pointer and a click find the row under them, never the candidates' line; the wheel still moves the list;
/// the rows don't move under the pointer as that line comes and goes (above the caret, by that line only); the panel
/// never covers the caret. The panel is in the app's executable, which this target can't import: its source is compiled
/// here with the core into a small program that shows it (real AppKit windows, nothing else of the app).
@Suite(.serialized)
struct CandidatePanelLayoutTests {
    @Test func belowTheCaretTheRowsAreOnTopAndThePinyinCandidatesUnderThem() throws {
        try LayoutChild.run("below")
    }

    @Test func aboveTheCaretTheRowsAreOnTopAndThePinyinCandidatesUnderThem() throws {
        try LayoutChild.run("above")
    }
}

private enum LayoutChild {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static func run(_ scenario: String) throws {
        let result = try command(try compiled.get(), [scenario], timeout: 60)
        #expect(result.status == 0 && result.output.contains("LAYOUT PASS \(scenario)"), "\(result.output)")
    }

    /// The panel's own sources (CandidatePanel.swift, and the two it uses: CommandIcons.swift, LiveSettings.swift) and
    /// `program`, against the core as `swift build` built it (.build/debug).
    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("candidate-panel-layout-\(UUID().uuidString)")
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
        let executable = scratch.appendingPathComponent("layout")
        let arguments = ["swiftc", "-swift-version", "5", "-parse-as-library", "-I", modules.path,
                         "-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels", "-framework", "AppKit"]
            + sources + [main.path] + objects + ["-o", executable.path]
        let swiftc = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments, timeout: 300)
        guard swiftc.status == 0 else { throw ChildError(swiftc.output) }
        return executable
    }

    struct ChildError: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    static func command(_ executable: URL, _ arguments: [String], timeout: TimeInterval) throws -> (status: Int32, output: String) {
        // A file, not a pipe: the compiler's diagnostics can fill a pipe's buffer.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("candidate-panel-layout-\(UUID().uuidString).log")
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
            throw ChildError("\(executable.lastPathComponent) timed out after \(Int(timeout))s")
        }
        try handle.synchronize()
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }

    static let program = #"""
    import AllInOneIMECore
    import AppKit
    import Foundation

    @MainActor enum Check {
        static var checks = 0
        static var failures = 0
        static func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
            checks += 1
            if !condition {
                failures += 1
                print("FAIL: \(message())")
            }
        }
    }

    @MainActor enum Layout {
        typealias Row = PanelModel.Row

        /// One @'s rows for 你好 as the presenter makes them (no numbers, an icon each, the command dimmed on the right),
        /// seven of more (the list scrolls), while "nihao" is composed: its candidates on a line of their own.
        static var composing: PanelModel {
            func row(_ text: String, _ command: Command) -> Row {
                Row(label: "", text: text, comment: "@" + command.name, kind: .candidate, icon: IconToken.command(command))
            }
            return PanelModel(
                rows: [row("Ask AI", .question), row("Improve", .improve), row("Translate into English", .translate),
                       row("Reminder: tomorrow 3:00 PM 你好", .reminder), row("note", .note), row("open", .open),
                       row("Open Notes", .open)],
                highlighted: 0, candidates: "1 你好   2 拟好   3 你   4 泥   5 尼", footer: "Space picks a word · ⏎ do the highlighted row · ↑↓ choose",
                detail: "1–7 / 9")
        }

        /// The same once 你好 is picked: no line of candidates.
        static var picked: PanelModel {
            var model = composing
            model.candidates = nil
            model.footer = "⏎ do it · ↑↓ choose · Esc as typed"
            return model
        }

        static func event(_ type: NSEvent.EventType, _ panel: CandidatePanel, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: panel.view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }

        /// The row the pointer at `point` (the view's, from its top) highlights.
        static func hovered(_ panel: CandidatePanel, at point: NSPoint) -> Int? {
            panel.view.mouseMoved(with: event(.mouseMoved, panel, at: point))
            return panel.view.hovered
        }

        /// What a click at `point` picks.
        static func click(_ panel: CandidatePanel, at point: NSPoint) -> [Int] {
            var picked: [Int] = []
            panel.onSelect = { picked.append($0) }
            panel.view.mouseDown(with: event(.leftMouseDown, panel, at: point))
            return picked
        }

        /// Where each row is, from the top of the panel: what the pointer highlights, moved down it a point at a time.
        static func spans(_ panel: CandidatePanel) -> [Int: ClosedRange<CGFloat>] {
            var rows: [Int: ClosedRange<CGFloat>] = [:]
            let view = panel.view
            for y in stride(from: CGFloat(0.5), to: view.bounds.height, by: 1) {
                guard let row = hovered(panel, at: NSPoint(x: view.bounds.midX, y: y)) else { continue }
                rows[row] = rows[row].map { $0.lowerBound...y } ?? y...y
            }
            return rows
        }

        static func expect(_ condition: Bool, _ message: @autoclosure () -> String) { Check.expect(condition, message()) }

        static func run(above: Bool) {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            // High on the screen: room below the caret. Near its bottom: none, the panel goes above.
            let anchor = NSRect(x: screen.midX, y: above ? screen.minY + 40 : screen.maxY - 150, width: 1, height: 20)
            let panel = CandidatePanel()
            let view = panel.view
            let model = composing, count = model.rows.count
            panel.show(model, anchor: anchor)
            let frame = panel.frame
            expect(above ? frame.minY >= anchor.maxY : frame.maxY <= anchor.minY,
                   "\(above ? "above" : "below") the caret, not over it: \(frame) for \(anchor)")

            // The rows from the top, one under the other in their order; nothing above the first but the padding.
            let rows = spans(panel)
            expect(rows.keys.sorted() == Array(0..<count), "every row is under the pointer somewhere: \(rows.keys.sorted())")
            guard rows.count == count else { return }
            for index in 1..<count {
                expect(rows[index - 1]!.upperBound < rows[index]!.lowerBound, "row \(index - 1) above row \(index): \(rows)")
            }
            expect(rows[0]!.lowerBound <= CandidateView.Metrics.padding + 1, "the rows first, at the top: \(rows[0]!)")

            // The candidates' line under the last row, above the footer.
            guard let line = view.candidatesFrame else { return expect(false, "the candidates' line is drawn") }
            expect(line.minY > rows[count - 1]!.upperBound, "the candidates under the rows: \(line), last row \(rows[count - 1]!)")
            expect(line.maxY <= view.footerY && view.footerY < view.bounds.height, "the candidates above the footer: \(line), footer at \(view.footerY)")

            // A click on a row picks that row; the pointer over the candidates highlights nothing, and a click there picks nothing.
            let x = view.bounds.midX
            for (index, row) in rows {
                expect(click(panel, at: NSPoint(x: x, y: (row.lowerBound + row.upperBound) / 2)) == [index], "a click on row \(index) picks it")
            }
            expect(hovered(panel, at: NSPoint(x: x, y: line.midY)) == nil, "the pointer over the candidates highlights no row")
            expect(click(panel, at: NSPoint(x: x, y: line.midY)).isEmpty, "a click on the candidates picks no row")

            // The wheel over the candidates' line moves the list as anywhere on the panel.
            var moved: [Int] = []
            panel.onScroll = { moved.append($0) }
            if let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -3, wheel2: 0, wheel3: 0),
               let event = NSEvent(cgEvent: wheel) {
                view.scrollWheel(with: event)
                expect(moved.count == 1 && moved[0] != 0, "the wheel moves the list: \(moved)")
            }

            // Pinyin picked: the line goes; the rows are where they were in the panel, which only loses that line at its
            // bottom. Below the caret its top stays, so the rows don't move; above it its bottom stays at the caret, and
            // the rows move down by that line.
            panel.show(picked, anchor: anchor)
            expect(view.candidatesFrame == nil, "no candidates' line without pinyin")
            let after = spans(panel), shorter = frame.height - panel.frame.height
            expect(after == rows, "the rows where they were in the panel: \(after) / \(rows)")
            expect(shorter > 0 && shorter <= line.height + 2 * CandidateView.Metrics.rowInsetY + 0.5,
                   "shorter by the candidates' line only: \(shorter) (\(line.height))")
            if above {
                expect(panel.frame.minY == frame.minY, "above the caret, its bottom stays at the caret: \(panel.frame) / \(frame)")
            } else {
                expect(panel.frame.maxY == frame.maxY, "below the caret, its top stays: the rows don't move: \(panel.frame) / \(frame)")
            }
            expect(panel.frame.minX == frame.minX, "no sideways jump: \(panel.frame.minX) / \(frame.minX)")
            for (index, row) in after {
                expect(click(panel, at: NSPoint(x: x, y: (row.lowerBound + row.upperBound) / 2)) == [index], "still: a click on row \(index) picks it")
            }

            // Pinyin again: as it was.
            panel.show(model, anchor: anchor)
            expect(panel.frame == frame && spans(panel) == rows && view.candidatesFrame == line, "the same panel again: \(panel.frame) / \(frame)")
            panel.hide()
        }
    }

    @main struct LayoutMain {
        @MainActor static func main() {
            let scenario = CommandLine.arguments.dropFirst().first ?? ""
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            switch scenario {
            case "below": Layout.run(above: false)
            case "above": Layout.run(above: true)
            default:
                print("unknown scenario \(scenario)")
                exit(2)
            }
            print("\(Check.failures == 0 ? "LAYOUT PASS" : "LAYOUT FAIL") \(scenario): \(Check.checks) checks, \(Check.failures) failures")
            exit(Check.failures == 0 ? 0 : 1)
        }
    }
    """#
}
