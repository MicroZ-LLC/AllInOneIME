import Foundation
import Testing

/// The candidate panel as the Mac draws it (`CandidateView`, Sources/AllInOneIME/CandidatePanel.swift): one @'s rows and
/// the pinyin candidates being composed on a line of their own, on the side of the panel nearest the caret, the rows on
/// the far side. Below the caret: that line at the top, the rows under it, the footer; above it: the rows at the top,
/// that line under them, just above the footer. A selection's header stays just above the rows either way. The pointer
/// and a click find the row under them, never the candidates' line; the wheel still moves the list; as that line comes
/// and goes the rows move by it only, all together; while typing on a line the panel stays on its side (no flip back and
/// forth with each key); it never covers the caret. While it shows, its width only grows (a shorter row leaves it as wide,
/// the rows across all of it), its height following the rows; once it has hidden, it is as wide as its rows need again,
/// in a column and in a row alike. The panel is in the app's executable, which this target can't
/// import: its source is compiled here with the core into a small program that shows it (real AppKit windows, nothing
/// else of the app).
@Suite(.serialized)
struct CandidatePanelLayoutTests {
    @Test func belowTheCaretThePinyinCandidatesAreOnTopAndTheRowsUnderThem() throws {
        try LayoutChild.run("below")
    }

    @Test func aboveTheCaretTheRowsAreOnTopAndThePinyinCandidatesUnderThem() throws {
        try LayoutChild.run("above")
    }

    @Test func aSelectionsHeaderStaysJustAboveTheRowsOnEitherSide() throws {
        try LayoutChild.run("selection")
    }

    @Test func whileTypingOnALineThePanelStaysOnItsSideOfTheCaret() throws {
        try LayoutChild.run("steady")
    }

    @Test func whileItShowsThePanelOnlyWidensAndAfterHidingItIsAsWideAsItsRows() throws {
        try LayoutChild.run("width")
    }

    @Test func thePinyinCandidatesInARowKeepTheirPanelsWidthTheSameWay() throws {
        try LayoutChild.run("row")
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
        typealias Spans = [Int: ClosedRange<CGFloat>]

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

        static var screen: NSRect { NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900) }
        /// A caret's line high on the screen (room below it), and one near its bottom (none: the panel goes above).
        static var high: NSRect { NSRect(x: screen.midX, y: screen.maxY - 150, width: 1, height: 20) }
        static var low: NSRect { NSRect(x: screen.midX, y: screen.minY + 40, width: 1, height: 20) }
        static let gap: CGFloat = 4

        /// How far the candidates' line takes: its text and the space around it.
        static func room(_ line: NSRect) -> CGFloat { line.height + 2 * CandidateView.Metrics.rowInsetY }

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
        static func spans(_ panel: CandidatePanel) -> Spans {
            var rows: Spans = [:]
            let view = panel.view
            for y in stride(from: CGFloat(0.5), to: view.bounds.height, by: 1) {
                guard let row = hovered(panel, at: NSPoint(x: view.bounds.midX, y: y)) else { continue }
                rows[row] = rows[row].map { $0.lowerBound...y } ?? y...y
            }
            return rows
        }

        static func moved(_ rows: Spans, by distance: CGFloat) -> Spans {
            rows.mapValues { ($0.lowerBound + distance)...($0.upperBound + distance) }
        }

        static func expect(_ condition: Bool, _ message: @autoclosure () -> String) { Check.expect(condition, message()) }

        /// The panel on `side` of the caret at `anchor`, not over it, its rows all there one under the other, and the
        /// candidates' line (if any) on the side nearest the caret: at the top below it, under the last row and just above
        /// the footer above it. The rows.
        @discardableResult
        static func placed(_ panel: CandidatePanel, at anchor: NSRect, _ side: CandidatePanel.Side, _ what: String) -> Spans {
            let view = panel.view, frame = panel.frame
            expect(view.side == side, "\(what): \(side) the caret, laid out for it (\(view.side))")
            expect(side == .above ? frame.minY >= anchor.maxY : frame.maxY <= anchor.minY, "\(what): \(side) the caret, not over it: \(frame) for \(anchor)")
            expect(panel.shows(view.model, anchor: anchor), "\(what): shown as it would be placed again")
            let rows = spans(panel), count = view.model.rows.count
            expect(rows.keys.sorted() == Array(0..<count), "\(what): every row is under the pointer somewhere: \(rows.keys.sorted())")
            guard rows.count == count, count > 0 else { return rows }
            for index in 1..<count {
                expect(rows[index - 1]!.upperBound < rows[index]!.lowerBound, "\(what): row \(index - 1) above row \(index): \(rows)")
            }
            let first = rows[0]!, last = rows[count - 1]!
            let top = CandidateView.Metrics.padding + CandidateView.Metrics.rowInsetY + 0.5
            expect(view.footerY > last.upperBound && view.footerY < view.bounds.height, "\(what): the footer under the rows: \(view.footerY)")
            if let line = view.candidatesFrame {
                if side == .below {
                    expect(line.minY <= top, "\(what): below the caret, the candidates' line at the top: \(line)")
                    expect(line.maxY < first.lowerBound, "\(what): the rows under the candidates' line: \(line), first row \(first)")
                } else {
                    expect(line.minY > last.upperBound, "\(what): above the caret, the candidates' line under the rows: \(line), last row \(last)")
                    expect(line.maxY <= view.footerY, "\(what): the candidates' line just above the footer: \(line), footer at \(view.footerY)")
                }
            } else if view.headerFrame == nil {
                expect(first.lowerBound <= CandidateView.Metrics.padding + 1, "\(what): the rows at the top: \(first)")
            }
            return rows
        }

        static func run(above: Bool) {
            let anchor = above ? low : high
            let side: CandidatePanel.Side = above ? .above : .below
            let panel = CandidatePanel()
            let view = panel.view
            let model = composing
            panel.show(model, anchor: anchor)
            let frame = panel.frame
            let rows = placed(panel, at: anchor, side, "pinyin composed")
            guard rows.count == model.rows.count, let line = view.candidatesFrame else {
                return expect(false, "the rows and the candidates' line are drawn")
            }

            // A click on a row picks that row; the pointer over the candidates highlights nothing, and a click there picks nothing.
            let x = view.bounds.midX
            for (index, row) in rows {
                expect(click(panel, at: NSPoint(x: x, y: (row.lowerBound + row.upperBound) / 2)) == [index], "a click on row \(index) picks it")
            }
            expect(hovered(panel, at: NSPoint(x: x, y: line.midY)) == nil, "the pointer over the candidates highlights no row")
            expect(click(panel, at: NSPoint(x: x, y: line.midY)).isEmpty, "a click on the candidates picks no row")

            // The wheel over the candidates' line moves the list as anywhere on the panel.
            var steps: [Int] = []
            panel.onScroll = { steps.append($0) }
            if let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -3, wheel2: 0, wheel3: 0),
               let event = NSEvent(cgEvent: wheel) {
                view.scrollWheel(with: event)
                expect(steps.count == 1 && steps[0] != 0, "the wheel moves the list: \(steps)")
            }

            // Pinyin picked: the line goes, the panel shorter by it only, on the same side. Below the caret its top stays
            // under the caret and the rows move up by the line, all together; above it its bottom stays at the caret and
            // the rows are where they were in the panel (which loses the line at its bottom).
            panel.show(picked, anchor: anchor)
            expect(view.candidatesFrame == nil, "no candidates' line without pinyin")
            let after = placed(panel, at: anchor, side, "pinyin picked"), shorter = frame.height - panel.frame.height
            expect(shorter == room(line), "shorter by the candidates' line only: \(shorter) (\(room(line)))")
            if above {
                expect(after == rows, "the rows where they were in the panel: \(after) / \(rows)")
                expect(panel.frame.minY == frame.minY, "above the caret, its bottom stays at the caret: \(panel.frame) / \(frame)")
            } else {
                expect(after == moved(rows, by: -room(line)), "the rows up by the line, together: \(after) / \(rows)")
                expect(panel.frame.maxY == frame.maxY, "below the caret, its top stays under the caret: \(panel.frame) / \(frame)")
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

        /// With text selected, its line (the header) stays just above the rows: below the caret the candidates' line, the
        /// header, the rows; above it the header, the rows, the candidates' line, the footer.
        static func selection() {
            for side in [CandidatePanel.Side.below, .above] {
                let anchor = side == .above ? low : high
                let panel = CandidatePanel()
                let view = panel.view
                var model = composing
                model.header = ["On the selection: “hello there” (11 characters)"]
                panel.show(model, anchor: anchor)
                let rows = placed(panel, at: anchor, side, "\(side), a selection")
                guard let first = rows[0], let header = view.headerFrame, let line = view.candidatesFrame else {
                    expect(false, "\(side): the header, the rows and the candidates' line are drawn")
                    continue
                }
                expect(header.maxY < first.lowerBound && first.lowerBound - header.maxY <= 2 * CandidateView.Metrics.rowInsetY + 1,
                       "\(side): the header just above the first row: \(header), \(first)")
                if side == .below {
                    expect(line.maxY < header.minY, "below the caret, the candidates' line above the header: \(line), \(header)")
                } else {
                    expect(header.minY <= CandidateView.Metrics.padding + CandidateView.Metrics.rowInsetY + 0.5, "above the caret, the header at the top: \(header)")
                }
                // Picked: the header and the rows as they were, but for the line.
                panel.show(picked.with(header: model.header), anchor: anchor)
                let shift = side == .below ? -room(line) : 0
                expect(view.headerFrame == header.offsetBy(dx: 0, dy: shift), "\(side): the header moves with the rows: \(String(describing: view.headerFrame))")
                expect(spans(panel) == moved(rows, by: shift), "\(side): the rows as they were")
                panel.hide()
            }
        }

        /// A line with room under it for the panel without the candidates' line, not with it: the line puts it above, and
        /// while typing on that line it stays there (pinyin picked, typed again, the caret moving along the line), its
        /// bottom at the caret, instead of flipping with each key. On another line, or once it has hidden, where it goes is
        /// decided again.
        static func steady() {
            let panel = CandidatePanel()
            let view = panel.view
            panel.show(composing, anchor: high)
            let tall = panel.frame.height
            panel.show(picked, anchor: high)
            let short = panel.frame.height
            panel.hide()
            expect(tall > short, "the candidates' line takes room: \(tall) / \(short)")
            let line = NSRect(x: screen.midX, y: screen.minY + gap + ((tall + short) / 2).rounded(), width: 1, height: 20)

            panel.show(picked, anchor: line)
            placed(panel, at: line, .below, "the rows alone fit under the line")
            let belowFrame = panel.frame
            panel.show(composing, anchor: line)
            placed(panel, at: line, .above, "with the candidates' line they don't: above")
            let bottom = panel.frame.minY
            expect(bottom == line.maxY + gap, "its bottom at the caret: \(panel.frame) for \(line)")
            for (key, model) in [picked, composing, picked, composing, picked].enumerated() {
                panel.show(model, anchor: line)
                placed(panel, at: line, .above, "key \(key + 1) on the line")
                expect(panel.frame.minY == bottom, "key \(key + 1): its bottom stays at the caret: \(panel.frame)")
                expect(view.candidatesFrame == nil || view.candidatesFrame!.maxY <= view.footerY, "key \(key + 1): the candidates' line nearest the caret")
            }
            // The caret further along the line (the pinyin typed before it): still above.
            let further = line.offsetBy(dx: 30, dy: 0)
            panel.show(composing, anchor: further)
            placed(panel, at: further, .above, "the caret further along the line")
            // On another line, higher, with room under it: below.
            let higher = line.offsetBy(dx: 0, dy: tall + 40)
            panel.show(composing, anchor: higher)
            placed(panel, at: higher, .below, "another line, with room under it")
            // Hidden, then up again on the first line: below, where the rows alone fit, as at first.
            panel.hide()
            panel.show(picked, anchor: line)
            placed(panel, at: line, .below, "up again after hiding")
            expect(panel.frame == belowFrame, "as at first: \(panel.frame) / \(belowFrame)")
            panel.hide()

            // Too tall for either side: the side with more room (then moved onto the screen).
            let huge = NSSize(width: 300, height: screen.height)
            expect(CandidatePanel.placement(for: huge, anchor: low).side == .above, "too tall: above a caret near the bottom")
            expect(CandidatePanel.placement(for: huge, anchor: high).side == .below, "too tall: below a caret near the top")
        }

        /// Rows one under another, each on its number's keycap, the first highlighted, a footer; `pending` more on their way.
        static func column(_ texts: [String], pending: Int = 0) -> PanelModel {
            PanelModel(rows: texts.enumerated().map { Row(label: "\($0.offset + 1)", text: $0.element, kind: .candidate) },
                       highlighted: 0, footer: "⏎ do it · ↑↓ choose", pending: pending)
        }

        /// The same candidates side by side (`PanelModel.horizontal`), as pinyin shows them in a row, without the footer:
        /// as wide as they are.
        static func inARow(_ texts: [String]) -> PanelModel {
            var model = column(texts)
            model.horizontal = true
            model.footer = ""
            return model
        }

        /// How big `model` is laid out on its own: in a panel that has never shown.
        static func natural(_ model: PanelModel) -> NSSize {
            let view = CandidateView()
            view.model = model
            return view.contentSize
        }

        /// The panel shows `model` at `size`, laid out at that size itself (not only its window).
        static func shown(_ panel: CandidatePanel, _ size: NSSize, _ what: String) {
            expect(panel.frame.size == size && panel.view.contentSize == size && panel.view.bounds.size == size,
                   "\(what): \(size) (window \(panel.frame.size), laid out \(panel.view.contentSize), view \(panel.view.bounds.size))")
        }

        /// Every row reaches the panel's right side, as at a natural width: the pointer just inside it is on the row, just
        /// past it (in the padding) on none.
        static func across(_ panel: CandidatePanel, _ what: String) {
            let right = panel.view.bounds.width - CandidateView.Metrics.padding
            let rows = spans(panel)
            expect(rows.count == panel.view.model.rows.count, "\(what): every row under the pointer: \(rows.keys.sorted())")
            for (index, span) in rows {
                let y = (span.lowerBound + span.upperBound) / 2
                expect(hovered(panel, at: NSPoint(x: right - 0.5, y: y)) == index && hovered(panel, at: NSPoint(x: right + 0.5, y: y)) == nil,
                       "\(what): row \(index) as wide as the panel, less its padding (\(right))")
            }
        }

        /// The owner's example: `@` needs a little, `@t` more, `@tr` and `@tra` less: the panel stays as wide as at `@t`,
        /// its height following the rows, its rows across all of it, until it hides; the next `@` starts at its own width.
        static func width() {
            let panel = CandidatePanel()
            let view = panel.view
            let anchor = high
            let short = column(["你好"])
            let long = column(["你好", "A row much longer than the narrowest panel would be"])
            let middle = column(["你好", "A row longer than the narrowest", "拟好"])
            let (shortSize, longSize, middleSize) = (natural(short), natural(long), natural(middle))
            expect(shortSize.width < middleSize.width && middleSize.width < longSize.width && middleSize.height > longSize.height,
                   "the rows need \(shortSize), \(middleSize), \(longSize)")

            panel.show(short, anchor: anchor)
            shown(panel, shortSize, "first shown")
            let first = panel.frame
            panel.show(long, anchor: anchor)
            shown(panel, longSize, "a longer row: wider")
            across(panel, "wider")
            panel.show(middle, anchor: anchor)
            shown(panel, NSSize(width: longSize.width, height: middleSize.height), "a shorter row: as wide, its height the rows'")
            across(panel, "kept, three rows")
            expect(panel.shows(middle, anchor: anchor), "shown as it would be shown again")
            let kept = panel.frame
            panel.show(middle, anchor: anchor)
            expect(panel.frame == kept, "shown again: as it is (\(panel.frame) / \(kept))")
            panel.show(short, anchor: anchor)
            shown(panel, NSSize(width: longSize.width, height: shortSize.height), "the shortest row: as wide, its height the row's")
            across(panel, "kept, one row")
            expect(panel.frame.minX == first.minX && panel.frame.maxY == first.maxY, "no sideways jump, its top under the caret: \(panel.frame)")

            // Hidden (Esc, a pick), then up again: as wide as its rows need.
            panel.hide()
            panel.show(short, anchor: anchor)
            shown(panel, shortSize, "up again after hiding")
            expect(panel.frame == first, "as at first: \(panel.frame) / \(first)")
            across(panel, "up again")

            // The rows on their way: their bars as long for the kept width as for a natural one.
            let waiting = column(["你好"], pending: 2)
            func bars() -> CGFloat? { view.subviews.first?.frame.width }
            panel.hide()
            panel.show(waiting, anchor: anchor)
            let naturalBars = bars(), naturalWidth = panel.frame.width
            panel.hide()
            panel.show(long, anchor: anchor)
            panel.show(waiting, anchor: anchor)
            shown(panel, NSSize(width: longSize.width, height: natural(waiting).height), "rows on their way: as wide")
            if CandidateView.reducesMotion {
                print("(Reduce Motion: no light over the bars to measure them by)")
            } else if let naturalBars, let keptBars = bars() {
                let grown = (longSize.width - naturalWidth) * CandidateView.Metrics.skeletonBars[0]
                expect(abs(keptBars - naturalBars - grown) <= 1, "the bars grow with the panel: \(naturalBars) → \(keptBars) (+\(grown))")
            } else {
                expect(false, "the bars of the rows on their way are drawn")
            }

            // One @'s rows with pinyin being composed: the candidates' line shorter, the panel as wide.
            panel.hide()
            panel.show(composing, anchor: anchor)
            let wide = natural(composing)
            shown(panel, wide, "one @ while composing")
            var fewer = composing
            fewer.rows = [composing.rows[0]]
            fewer.candidates = "1 你"
            fewer.footer = "Space picks a word"
            fewer.detail = nil
            expect(natural(fewer).width < wide.width, "fewer rows need less: \(natural(fewer)) / \(wide)")
            panel.show(fewer, anchor: anchor)
            shown(panel, NSSize(width: wide.width, height: natural(fewer).height), "one @, fewer rows and candidates: as wide")
            expect(view.candidatesFrame != nil, "the candidates' line still there")
            across(panel, "one @, kept")
            panel.hide()

            // Near the screen's right edge: placed as any panel that wide (moved left onto the screen), not past it.
            let edge = NSRect(x: screen.maxX - 60, y: high.minY, width: 1, height: 20)
            panel.show(short, anchor: edge)
            panel.show(long, anchor: edge)
            panel.show(short, anchor: edge)
            let placed = CandidatePanel.placement(for: panel.frame.size, anchor: edge, textInset: view.textInset, keeping: view.side)
            expect(panel.frame.width == longSize.width && panel.frame.origin == placed.origin && panel.frame.maxX <= screen.maxX,
                   "at the right edge, kept as wide and placed as that wide a panel: \(panel.frame) / \(placed.origin)")
            panel.hide()
        }

        /// The pinyin candidates in a row: a longer line widens the panel, a shorter one leaves it as wide (its height the
        /// line's), the candidates where they were; once hidden, as wide as its candidates need.
        static func row() {
            let panel = CandidatePanel()
            let view = panel.view
            let anchor = high
            let few = inARow(["你", "好"])
            let many = inARow(["你好", "拟好", "A candidate long enough to be cut short with an ellipsis", "泥", "尼", "你号", "逆好"])
            let two = inARow(["你好", "拟好"])
            let (fewSize, manySize, twoSize) = (natural(few), natural(many), natural(two))
            expect(fewSize.width < twoSize.width && twoSize.width < manySize.width && twoSize.height < manySize.height,
                   "the candidates need \(fewSize), \(twoSize), \(manySize)")

            panel.show(few, anchor: anchor)
            shown(panel, fewSize, "in a row, first shown")
            let first = panel.frame, inset = view.textInset
            panel.show(many, anchor: anchor)
            shown(panel, manySize, "in a row, more: wider")
            panel.show(two, anchor: anchor)
            shown(panel, NSSize(width: manySize.width, height: twoSize.height), "in a row, fewer: as wide, its height the line's")
            expect(view.textInset == inset && panel.frame.minX == first.minX, "the first candidate where it was: \(view.textInset) / \(inset)")
            expect(panel.shows(two, anchor: anchor), "in a row: shown as it would be shown again")
            let line = Set(stride(from: CGFloat(0.5), to: view.bounds.width, by: 1).compactMap { hovered(panel, at: NSPoint(x: $0, y: view.bounds.midY)) })
            expect(line == [0, 1], "both candidates under the pointer, nothing in the room after them: \(line.sorted())")

            panel.hide()
            panel.show(two, anchor: anchor)
            shown(panel, twoSize, "in a row, up again after hiding")
            panel.hide()
        }
    }

    extension PanelModel {
        func with(header: [String]) -> PanelModel {
            var model = self
            model.header = header
            return model
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
            case "selection": Layout.selection()
            case "steady": Layout.steady()
            case "width": Layout.width()
            case "row": Layout.row()
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
