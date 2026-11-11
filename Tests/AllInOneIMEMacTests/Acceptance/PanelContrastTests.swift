import Foundation
import Testing

/// Compiles the executable's real CandidateView with AppKit, as CandidatePanelLayoutTests does.
/// Assumed implementation seam: CandidateView.palette(appearance:increaseContrast:) returns the colors
/// actually used to draw row comments, pinyin numbers, and selected rows (selectedFill,
/// selectedBorder, selectedBorderWidth). CandidateView.handoffTargets exposes each clickable
/// destination's shortcut, keycapFrame, and targetFrame. PanelPointer.Handlers accepts a
/// handoff callback carrying the one-based digit used by the matching ⌘digit shortcut.
@Suite(.serialized)
struct PanelContrastTests {
    @Test func rowCommentsAndPinyinNumbersUseAccessibleSemanticColors() throws {
        try PanelContrastChild.run("text")
    }

    @Test func selectedTintHasVisibleContrastInBothAppearances() throws {
        try PanelContrastChild.run("selection")
    }

    @Test func continueInDestinationsHaveKeycapsAndClickableTargets() throws {
        try PanelContrastChild.run("handoff")
    }
}

private enum PanelContrastChild {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func run(_ scenario: String) throws {
        let result = try command(try compiled.get(), [scenario], timeout: 60)
        #expect(result.status == 0 && result.output.contains("PANEL PASS \(scenario)"), "\(result.output)")
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("panel-contrast-\(UUID().uuidString)")
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
        let executable = scratch.appendingPathComponent("panel")
        let arguments = ["swiftc", "-swift-version", "5", "-parse-as-library", "-I", modules.path,
                         "-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels", "-framework", "AppKit"]
            + sources + [main.path] + objects + ["-o", executable.path]
        let result = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments, timeout: 300)
        guard result.status == 0 else { throw Failure(result.output) }
        return executable
    }

    static func command(_ executable: URL, _ arguments: [String], timeout: TimeInterval) throws -> (status: Int32, output: String) {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("panel-contrast-\(UUID().uuidString).log")
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
            throw Failure("Panel contrast child timed out after \(Int(timeout))s")
        }
        try handle.synchronize()
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }

    static let program = #"""
    import AppKit
    import AllInOneIMECore
    import Foundation

    @MainActor enum Check {
        static var failures = 0
        static func expect(_ condition: Bool, _ message: String) {
            if !condition { failures += 1; print("FAIL: " + message) }
        }
        static func components(_ color: NSColor) -> (Double, Double, Double, Double) {
            let rgb = color.usingColorSpace(.deviceRGB)!
            return (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent), Double(rgb.alphaComponent))
        }
        static func same(_ a: NSColor, _ b: NSColor) -> Bool {
            let x = components(a), y = components(b)
            return abs(x.0 - y.0) < 0.005 && abs(x.1 - y.1) < 0.005 && abs(x.2 - y.2) < 0.005 && abs(x.3 - y.3) < 0.005
        }
        static func luminance(_ rgb: (Double, Double, Double)) -> Double {
            func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
        }
        static func contrast(_ foreground: NSColor, over background: NSColor) -> Double {
            let f = components(foreground), b = components(background)
            let mixed = (f.0 * f.3 + b.0 * (1 - f.3),
                         f.1 * f.3 + b.1 * (1 - f.3),
                         f.2 * f.3 + b.2 * (1 - f.3))
            let a = luminance(mixed), base = luminance((b.0, b.1, b.2))
            return (max(a, base) + 0.05) / (min(a, base) + 0.05)
        }
        static func appearances(_ body: (NSAppearance, String) -> Void) {
            for (name, label) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                let appearance = NSAppearance(named: name)!
                appearance.performAsCurrentDrawingAppearance { body(appearance, label) }
            }
        }
        static func text() {
            appearances { appearance, label in
                for increased in [false, true] {
                    let palette = CandidateView.palette(appearance: appearance, increaseContrast: increased)
                    let expected: NSColor = increased ? .labelColor : .secondaryLabelColor
                    expect(same(palette.rowComment, expected), "\(label) comment color at increased=\(increased)")
                    expect(same(palette.pillNumber, expected), "\(label) pinyin number color at increased=\(increased)")
                }
            }
        }
        static func selection() {
            appearances { appearance, label in
                let background = CandidateView.background
                let normal = CandidateView.palette(appearance: appearance, increaseContrast: false)
                let strong = CandidateView.palette(appearance: appearance, increaseContrast: true)
                let normalRatio = contrast(normal.selectedFill, over: background)
                let strongRatio = contrast(strong.selectedFill, over: background)
                expect(normalRatio >= 1.5, "\(label) selected row contrast \(normalRatio) < 1.5")
                expect(strongRatio > normalRatio, "\(label) Increase contrast must strengthen selected fill")
                expect(components(strong.selectedFill).3 >= 0.995, "\(label) Increase contrast needs a solid selected fill")
                expect(strong.selectedBorderWidth == 1, "\(label) Increase contrast needs a 1 px border")
                expect(strong.selectedBorder.map { same($0, .controlAccentColor) } == true,
                       "\(label) Increase contrast needs an accent border")
            }
        }
        static func handoff() {
            let panel = CandidatePanel()
            let model = PanelModel(handoff: .init(title: "Continue in…", choices: [
                .init(shortcut: "⌘1", name: "Claude Code"), .init(shortcut: "⌘2", name: "Codex")]))
            panel.show(model, anchor: NSRect(x: 500, y: 500, width: 1, height: 20))
            let targets = panel.view.handoffTargets
            expect(targets.count == 2, "two continue-in targets")
            guard targets.count == 2 else { return }
            var picked: [Int] = []
            panel.take(by: panel, .init(select: nil, delete: nil, scroll: nil, chip: nil,
                                        handoff: { picked.append($0) }))
            for (index, target) in targets.enumerated() {
                let digit = index + 1
                expect(target.shortcut == "⌘\(digit)", "target \(digit) has matching command-digit shortcut")
                expect(target.keycapFrame.height == CandidateView.Metrics.smallKeycapHeight,
                       "target \(digit) uses the footer's small keycap")
                expect(target.targetFrame.contains(target.keycapFrame), "target \(digit) contains its keycap")
                let point = NSPoint(x: target.targetFrame.midX, y: target.targetFrame.midY)
                let event = NSEvent.mouseEvent(with: .leftMouseDown, location: panel.view.convert(point, to: nil),
                    modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1)!
                panel.view.mouseDown(with: event)
                expect(picked.last == digit, "click target \(digit) invokes the same digit as ⌘\(digit)")
            }
            expect(picked == [1, 2], "each destination receives exactly one click")
        }
    }

    @main struct Main {
        @MainActor static func main() {
            _ = NSApplication.shared
            let scenario = CommandLine.arguments.dropFirst().first ?? ""
            switch scenario {
            case "text": Check.text()
            case "selection": Check.selection()
            case "handoff": Check.handoff()
            default: Check.expect(false, "unknown scenario")
            }
            if Check.failures == 0 { print("PANEL PASS \(scenario)") }
            else { exit(1) }
        }
    }
    """#
}
