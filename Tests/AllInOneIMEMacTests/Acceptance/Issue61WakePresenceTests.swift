import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMETestSupport
import AppKit
import Foundation
import Testing

/// Issue #61: display sleep and wake can leave the candidate box missing in one app while Notes still shows it.
/// Screen and window-server answers are supplied by the test; no real app receives keys.
@Suite(.serialized)
struct Issue61WakePresenceTests {
    @Test(arguments: ["mac-wake", "screen-wake", "screen-change"])
    func aMissingBoxIsCheckedAgainAfterTheDisplayReturns(_ event: String) throws {
        let output = try Issue61PresenceChild.run("wake", event)
        #expect(output.contains("ISSUE61 PASS"), "\(output)")
    }

    @Test func aWindowAtItsRequestedFrameButOutsideEveryScreenIsMissing() throws {
        let output = try Issue61PresenceChild.run("off-screen-frame")
        #expect(output.contains("ISSUE61 PASS"), "\(output)")
    }

    @Test func shortCompositionsStillCheckTheNextBox() throws {
        let output = try Issue61PresenceChild.run("short-compositions")
        #expect(output.contains("ISSUE61 PASS"), "\(output)")
    }

    @Test func aRememberedCaretOnADetachedDisplayIsNotUsedInTheSameField() {
        let oldScreens = [CGRect(x: 0, y: 0, width: 3000, height: 900)]
        let currentScreens = [CGRect(x: 0, y: 0, width: 1512, height: 900)]
        let oldCaret = CGRect(x: 2200, y: 400, width: 1, height: 18)
        var memory = PanelAnchor.Memory()
        let client = NSObject()
        memory.enter(.init(client: ObjectIdentifier(client), app: "com.tinyspeck.slackmacgap", session: 1))
        #expect(memory.place(oldCaret, screens: oldScreens) { nil }.source == .field)
        let placement = memory.place(.zero, screens: currentScreens) { nil }
        #expect(placement == .init(rect: .zero, source: .told), "stale same-field caret: \(placement)")
    }

    @Test @MainActor func aRememberedCaretOnADetachedDisplayDoesNotOverrideTheCurrentPointer() {
        let client = ProfiledTextClient(.electron)
        var memory = PanelAnchor.Memory()
        memory.enter(.init(client: ObjectIdentifier(client), app: "com.tinyspeck.slackmacgap", session: 1))
        memory.learnWindow { (ProfiledTextClient.window, false) }
        var lastByApp = ["com.tinyspeck.slackmacgap": CGRect(x: 2200, y: 400, width: 1, height: 18)]
        client.beginTurn() // Electron has not sent its caret bounds for this composition yet.
        let placed = FieldAnchor.place(in: client, app: "com.tinyspeck.slackmacgap", selection: nil,
                                       memory: &memory, lastByApp: &lastByApp,
                                       screens: [CGRect(x: 0, y: 0, width: 1512, height: 900)],
                                       pointer: { CGPoint(x: 500, y: 400) }, accessibility: { _ in nil })
        client.endTurn()
        #expect(placed.placement.rect == CGRect(x: 500, y: 391, width: 1, height: 18),
                "stale app caret instead of current pointer: \(placed.placement)")
    }
}

private enum Issue61PresenceChild {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let compiled = Result { try compile() }

    static func run(_ scenario: String, _ event: String = "") throws -> String {
        let executable = try compiled.get()
        let log = TestScratch.temporary("issue61-presence-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: log) }
        let process = Process()
        process.executableURL = executable
        process.arguments = [scenario, event]
        process.currentDirectoryURL = repository
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate(); throw Failure("presence child timed out") }
        try handle.synchronize()
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        guard process.terminationStatus == 0 else { throw Failure(output) }
        return output
    }

    static func compile() throws -> URL {
        let folder = TestScratch.temporary("issue61-presence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let main = folder.appendingPathComponent("Main.swift")
        try program.write(to: main, atomically: true, encoding: .utf8)
        let sources = ["CandidatePanel.swift", "CommandIcons.swift", "LiveSettings.swift"]
            .map { repository.appendingPathComponent("Sources/AllInOneIME/" + $0).path }
        let executable = folder.appendingPathComponent("presence")
        let result = try SourceCompiler.compile(repository: repository, sources: sources + [main.path],
                                                executable: executable, parseAsLibrary: true, timeout: 300)
        guard result.status == 0 else { throw Failure(result.output) }
        return executable
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static let program = #"""
    import AllInOneIMECore
    import AppKit
    import Foundation

    @MainActor enum Scenario {
        static var answers = 0
        static let model = PanelModel(rows: [.init(label: "1", text: "你好", kind: .candidate)])
        static var anchor: NSRect {
            let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 900)
            return NSRect(x: frame.midX, y: frame.midY, width: 1, height: 18)
        }
        static func pump(_ seconds: TimeInterval, until done: () -> Bool = { false }) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline && !done() {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        }
        static func missingServer() {
            CandidatePanel.recheckDelay = 0.03
            CandidatePanel.surroundings = .init(windowServer: { _ in
                answers += 1
                return .missing
            })
        }
        static func wake(_ event: String) -> Bool {
            missingServer()
            let original = CandidatePanel.shared
            original.show(model, anchor: anchor)
            pump(1) { CandidatePanel.shared !== original && answers >= 4 }
            let firstCount = answers
            guard CandidatePanel.shared !== original && firstCount >= 4 else {
                print("setup failed: fresh window was not checked; \(firstCount) answers")
                return false
            }
            let beforeWake = CandidatePanel.shared
            switch event {
            case "mac-wake":
                NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
            case "screen-wake":
                NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: NSWorkspace.shared)
            case "screen-change":
                NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            default: return false
            }
            pump(1) { CandidatePanel.shared !== beforeWake && answers >= firstCount + 4 }
            let healedAgain = CandidatePanel.shared !== beforeWake && answers >= firstCount + 4
            print("\(event): before \(firstCount), after \(answers), fresh window again \(CandidatePanel.shared !== beforeWake)")
            CandidatePanel.shared.hide()
            return healedAgain
        }
        static func offScreenFrame() -> Bool {
            let far = NSRect(x: 100_000, y: 400, width: 250, height: 80)
            let server = CandidatePanel.WindowServerView.window(onScreen: true, alpha: 1, frame: far)
            let absence = CandidatePanel.absence(appHidden: false, server: server, alpha: 1, frame: far)
            print("matching off-screen frames: \(String(describing: absence))")
            return absence != nil
        }
        static func shortCompositions() -> Bool {
            missingServer()
            CandidatePanel.recheckDelay = 0.25
            let panel = CandidatePanel.shared
            for _ in 0..<3 {
                panel.show(model, anchor: anchor)
                panel.hide()
            }
            panel.show(model, anchor: anchor)
            pump(1) { CandidatePanel.shared !== panel }
            let healed = CandidatePanel.shared !== panel && answers >= 3
            print("short compositions: \(answers) answers, fresh window \(CandidatePanel.shared !== panel)")
            CandidatePanel.shared.hide()
            return healed
        }
    }

    @main struct Main {
        @MainActor static func main() {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            let args = Array(CommandLine.arguments.dropFirst())
            let passed: Bool
            switch args.first {
            case "wake": passed = Scenario.wake(args.dropFirst().first ?? "")
            case "off-screen-frame": passed = Scenario.offScreenFrame()
            case "short-compositions": passed = Scenario.shortCompositions()
            default: passed = false
            }
            print(passed ? "ISSUE61 PASS" : "ISSUE61 FAIL")
            exit(passed ? 0 : 1)
        }
    }
    """#
}
