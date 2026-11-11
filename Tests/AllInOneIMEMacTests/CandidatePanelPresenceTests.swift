import Foundation
import Testing

/// The candidate panel makes sure it can be seen as it comes up (GitHub #61: in every app, the box never showed until
/// the input method was killed, while the log had the caret's rect right on every key). The app hidden (Hide Others) is
/// shown again, never activated; the window server, asked a turn after the panel came up, saying it can't be seen (off
/// screen, no alpha, somewhere else) twice: put back, ordered out and in again, and where that isn't enough a fresh window
/// in its place, the shared panel's, with everything attached (`CandidatePanel.checkPresence`, `replace`); an alpha lost
/// for no reason given back, the self-test's invisible panel left so; and nothing more on a key while it is up. The
/// window server and the app's hidden state are a stand-in's (`CandidatePanel.surroundings`). The panel is in the app's
/// executable, which this target can't import: its source is compiled here with the core into a small program that
/// shows it (real AppKit windows, nothing else of the app), as CandidatePanelLayoutTests does.
@Suite(.serialized)
struct CandidatePanelPresenceTests {
    @Test func aHiddenAppIsShownAgainAsTheBoxComesUpNeverActivated() throws {
        try PresenceChild.run("hidden")
    }

    @Test func aBoxTheWindowServerLostIsPutBackOrReplacedWithEverythingAttached() throws {
        try PresenceChild.run("offscreen")
    }

    @Test func anAlphaLostForNoReasonIsGivenBackButTheSelfTestsInvisibleBoxStaysSo() throws {
        try PresenceChild.run("alpha")
    }

    @Test func nothingMoreIsDoneOnAKeyWhileTheBoxIsUp() throws {
        try PresenceChild.run("steady")
    }
}

private enum PresenceChild {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static func run(_ scenario: String) throws {
        let result = try command(try compiled.get(), [scenario], timeout: 60)
        #expect(result.status == 0 && result.output.contains("PRESENCE PASS \(scenario)"), "\(result.output)")
    }

    /// The panel's own sources (CandidatePanel.swift, and the two it uses: CommandIcons.swift, LiveSettings.swift) and
    /// `program`, against the core as `swift build` built it (.build/debug).
    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("candidate-panel-presence-\(UUID().uuidString)")
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
        let executable = scratch.appendingPathComponent("presence")
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
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("candidate-panel-presence-\(UUID().uuidString).log")
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

    /// The app and the window server as the panel finds them (`CandidatePanel.surroundings`): what they say is the test's,
    /// and what the panel asks and does is counted.
    final class World {
        static var hidden = false
        static var hiddenAsked = 0
        static var unhides = 0
        /// The windows the window server was asked about, in turn.
        static var asked: [Int] = []
        /// What it says of window `number` the `call`th time it is asked about it (0: the first).
        static var answer: (_ number: Int, _ call: Int) -> CandidatePanel.WindowServerView = { number, _ in World.seen(number) }

        static func install() {
            CandidatePanel.recheckDelay = 0.05
            CandidatePanel.surroundings = .init(
                appHidden: {
                    World.hiddenAsked += 1
                    return World.hidden
                },
                unhideApp: {
                    World.unhides += 1
                    World.hidden = false
                },
                windowServer: { number in
                    let call = World.asked.filter { $0 == number }.count
                    World.asked.append(number)
                    return World.answer(number, call)
                })
        }

        /// Window `number` as a window server that has it right: on screen, with its own alpha and frame.
        static func seen(_ number: Int) -> CandidatePanel.WindowServerView {
            guard let window = NSApp.window(withWindowNumber: number) else { return .missing }
            return MainActor.assumeIsolated { .window(onScreen: window.isVisible, alpha: window.alphaValue, frame: window.frame) }
        }
    }

    /// Each window's `orderFrontRegardless`, counted (AppKit's own then done).
    enum Ordering {
        static var counts: [ObjectIdentifier: Int] = [:]
        static func count(_ window: NSWindow) -> Int { counts[ObjectIdentifier(window)] ?? 0 }

        static func install() {
            let selector = #selector(NSWindow.orderFrontRegardless)
            guard let method = class_getInstanceMethod(NSWindow.self, selector) else { return }
            typealias Implementation = @convention(c) (NSWindow, Selector) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: Implementation.self)
            let counted: @convention(block) (NSWindow) -> Void = { window in
                counts[ObjectIdentifier(window), default: 0] += 1
                original(window, selector)
            }
            method_setImplementation(method, imp_implementationWithBlock(counted))
        }
    }

    @MainActor enum Presence {
        typealias Row = PanelModel.Row

        static func expect(_ condition: Bool, _ message: @autoclosure () -> String) { Check.expect(condition, message()) }

        static func model(_ texts: [String]) -> PanelModel {
            PanelModel(rows: texts.enumerated().map { Row(label: "\($0.offset + 1)", text: $0.element, kind: .candidate) },
                       highlighted: 0, footer: "⏎ do it · ↑↓ choose")
        }
        static let words = model(["你好", "拟好", "你"])
        static let others = model(["世界", "视界", "是"])

        static var screen: NSRect { NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900) }
        static var high: NSRect { NSRect(x: screen.midX, y: screen.maxY - 150, width: 1, height: 20) }
        static var low: NSRect { NSRect(x: screen.midX - 100, y: screen.minY + 40, width: 1, height: 20) }

        /// The run loop turned for up to `seconds`, until `done`.
        @discardableResult
        static func pump(_ seconds: TimeInterval, until done: () -> Bool = { false }) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if done() { return true }
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            return done()
        }

        /// Hidden and put away, as it is a moment after a word is done.
        static func putAway(_ panel: CandidatePanel) {
            panel.hide()
            pump(1) { !panel.isVisible }
        }

        static func asked(about panel: CandidatePanel) -> Int { World.asked.filter { $0 == panel.windowNumber }.count }

        /// Hide Others (⌥⌘H in another app) hid the input method: shown again as the box comes up, and while it's up,
        /// never activated; not while it isn't up.
        static func hidden() {
            World.install()
            let panel = CandidatePanel()
            World.hidden = true
            panel.show(words, anchor: high)
            expect(World.unhides == 1 && !World.hidden, "the hidden app shown again as the box comes up (\(World.unhides))")
            expect(panel.isShowing && panel.alphaValue == 1, "the box up")
            expect(!NSApp.isActive, "the app never activated")
            pump(0.3)
            World.hidden = true
            NotificationCenter.default.post(name: NSApplication.didHideNotification, object: NSApp)
            expect(World.unhides == 2 && !World.hidden, "hidden while it's up: shown again at once (\(World.unhides))")
            expect(panel.isShowing && !NSApp.isActive, "still up, the app not activated")
            putAway(panel)
            World.hidden = true
            NotificationCenter.default.post(name: NSApplication.didHideNotification, object: NSApp)
            expect(World.unhides == 2 && World.hidden, "hidden while it isn't up: left hidden (\(World.unhides))")
            panel.show(others, anchor: high)
            expect(World.unhides == 3 && !World.hidden && panel.isShowing, "shown again as it comes up next (\(World.unhides))")
            putAway(panel)

            // AppKit's own: the app really hidden, the box up, the app shown and never activated.
            CandidatePanel.surroundings = .init(windowServer: { _ in .unknown })
            NSApp.hide(nil)
            guard pump(2, until: { NSApp.isHidden }) else { return print("note: this session doesn't hide the app; AppKit's own part skipped") }
            panel.show(words, anchor: high)
            expect(!NSApp.isHidden && !NSApp.isActive, "AppKit's: shown again (\(!NSApp.isHidden)), not activated (\(!NSApp.isActive))")
            expect(panel.isVisible, "AppKit's: the box up")
            panel.hide()
        }

        /// The window server says the box can't be seen: once, nothing done; twice, put back by ordering it out and in
        /// again; lost for good, a fresh window takes the shared panel's place, showing what it showed with everything
        /// attached; asked a turn after it came up, never on the key.
        static func offscreen() {
            World.install()
            let panel = CandidatePanel.shared
            var presented = 0, replacedWith: CandidatePanel?, picked: [Int] = []
            let owner = NSObject()
            panel.onPresent = { presented += 1 }
            panel.onReplace = { replacedWith = $0 }
            panel.take(by: owner, .init(select: { picked.append($0) }, delete: nil, scroll: nil, chip: nil, handoff: nil))

            panel.show(words, anchor: high)
            expect(World.asked.isEmpty, "not asked on the key that brought it up")
            pump(0.5)
            expect(World.asked == [panel.windowNumber], "seen: asked once, a turn later (\(World.asked))")

            // Unseen once (on its way to the window server): asked again, nothing done.
            putAway(panel)
            (World.asked, World.answer) = ([], { number, call in call == 0 ? .missing : World.seen(number) })
            panel.show(words, anchor: high)
            pump(0.5)
            expect(asked(about: panel) == 2 && CandidatePanel.shared === panel && panel.isShowing,
                   "unseen once: asked again, nothing more (\(World.asked))")

            // Unseen until ordered out and in again: put back so.
            putAway(panel)
            let frame = NSRect(x: 1, y: 2, width: 3, height: 4)
            (World.asked, World.answer) = ([], { number, call in
                call < 2 ? .window(onScreen: true, alpha: 1, frame: frame) : World.seen(number)
            })
            panel.show(words, anchor: high)
            pump(1) { asked(about: panel) >= 3 }
            pump(0.2)
            expect(asked(about: panel) == 3 && CandidatePanel.shared === panel && panel.isShowing,
                   "in another frame: ordered out and in again, seen then, the same window (\(World.asked))")

            // Lost for good: a fresh window.
            putAway(panel)
            let lost = panel.windowNumber
            (World.asked, World.answer) = ([], { number, _ in number == lost ? .missing : World.seen(number) })
            panel.show(others, anchor: low)
            let shownFrame = panel.frame
            pump(2) { CandidatePanel.shared !== panel }
            let fresh = CandidatePanel.shared
            expect(fresh !== panel, "lost for good: a fresh window in its place")
            guard fresh !== panel else { return }
            expect(replacedWith === fresh, "whoever keeps the panel told (onReplace)")
            expect(World.asked.filter { $0 == lost }.count == 3, "asked about the lost one three times (\(World.asked))")
            expect(!panel.isVisible, "the lost one put away")
            expect(fresh.isShowing && fresh.windowNumber != lost && fresh.alphaValue == 1 && !fresh.ignoresMouseEvents,
                   "the fresh one up, visible and clickable")
            expect(fresh.view === panel.view && fresh.view.model == others && fresh.frame == shownFrame,
                   "showing what it showed where it showed it: \(fresh.frame) / \(shownFrame)")
            expect(fresh.owner === owner, "the same owner")
            pump(0.5)
            expect(asked(about: fresh) == 1, "the fresh one asked about once, seen (\(World.asked))")
            if let row = fresh.view.rowFrame(1) {
                let point = fresh.view.convert(NSPoint(x: row.midX, y: row.midY), to: nil)
                let click = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                               windowNumber: fresh.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                fresh.view.mouseDown(with: click)
            }
            expect(picked == [1], "a click on its row is the owner's, as before (\(picked))")
            let before = presented
            fresh.hide()
            expect(presented == before + 1, "what follows it still told (onPresent)")
            fresh.show(words, anchor: high)
            expect(fresh.isShowing && fresh.view.model == words, "it shows the next word")
            fresh.hide()
        }

        /// A box with no alpha as it comes up, for no reason, is given it back (with clicks); one lost while it's up too,
        /// the window server telling; the self-test's invisible box stays invisible and isn't asked about.
        static func alpha() {
            World.install()
            let panel = CandidatePanel()
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            panel.show(words, anchor: high)
            expect(panel.alphaValue == 1 && !panel.ignoresMouseEvents, "no alpha as it came up: visible and clickable")
            pump(0.3)

            // Lost while up, then hidden between words (its alpha kept as it was): visible as it comes back.
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            panel.hide()
            panel.show(others, anchor: high)
            expect(panel.alphaValue == 1 && !panel.ignoresMouseEvents, "kept with no alpha between words: visible again")
            pump(0.3)

            // Lost while up, before the window server is asked: given back once it says so twice.
            putAway(panel)
            World.asked = []
            panel.show(words, anchor: high)
            panel.alphaValue = 0
            pump(1) { panel.alphaValue == 1 }
            expect(panel.alphaValue == 1 && panel.isShowing, "lost while up: given back")
            pump(0.3)

            // The window server has it with no alpha: put back.
            putAway(panel)
            (World.asked, World.answer) = ([], { number, call in
                guard call < 2, let window = NSApp.window(withWindowNumber: number) else { return World.seen(number) }
                return MainActor.assumeIsolated { .window(onScreen: true, alpha: 0, frame: window.frame) }
            })
            panel.show(words, anchor: high)
            pump(1) { asked(about: panel) >= 3 }
            pump(0.2)
            expect(asked(about: panel) == 3 && panel.isShowing && panel.alphaValue == 1, "no alpha at the window server: put back (\(World.asked))")
            putAway(panel)

            // The self-test's: invisible on purpose, kept so, never asked about.
            World.answer = { number, _ in World.seen(number) }
            CandidatePanel.invisible = true
            let quiet = CandidatePanel()
            quiet.alphaValue = 0
            quiet.ignoresMouseEvents = true
            World.asked = []
            quiet.show(words, anchor: high)
            pump(0.3)
            quiet.hide()
            quiet.show(others, anchor: high)
            pump(0.3)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
            pump(0.3)
            expect(quiet.isShowing && quiet.alphaValue == 0 && quiet.ignoresMouseEvents, "the self-test's box stays invisible and click-through")
            expect(World.asked.isEmpty, "the self-test's box isn't asked about (\(World.asked))")
            quiet.hide()
            CandidatePanel.invisible = false

            // Lost while up, the Mac woke: given back at once.
            panel.show(words, anchor: high)
            pump(0.3)
            panel.alphaValue = 0
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
            expect(panel.alphaValue == 1 && panel.isShowing, "lost while up, the Mac woke: given back at once")
            panel.hide()
        }

        /// While the box is up, a key changes what it shows and where, and nothing more: the window server and the app
        /// aren't asked, and it isn't ordered in again. The next word asks the window server again, its window reused as
        /// it is while still ordered in from the last one (GitHub #23), ordered in once put away.
        static func steady() {
            World.install()
            Ordering.install()
            let panel = CandidatePanel()
            panel.show(words, anchor: high)
            expect(Ordering.count(panel) == 1, "ordered in as it came up (\(Ordering.count(panel)))")
            pump(0.3)
            expect(World.asked.count == 1, "asked once as it came up (\(World.asked))")
            // The real window server finds nothing wrong with it (where it tells anything: not while the screen is locked).
            let real = CandidatePanel.windowServerView(of: panel.windowNumber)
            expect(CandidatePanel.absence(appHidden: false, server: real, alpha: panel.alphaValue, frame: panel.frame) == nil,
                   "the window server has it as it is: \(real), \(panel.frame)")
            let hiddenAsked = World.hiddenAsked
            for key in 0..<40 {
                panel.show(key % 2 == 0 ? others : words, anchor: high.offsetBy(dx: CGFloat(key * 3), dy: 0))
            }
            expect(panel.view.model == words && panel.isShowing, "the keys' rows shown")
            pump(0.3)
            expect(World.asked.count == 1, "keys while it's up: the window server not asked again (\(World.asked))")
            expect(World.hiddenAsked == hiddenAsked, "keys while it's up: the app not asked (\(World.hiddenAsked - hiddenAsked))")
            expect(Ordering.count(panel) == 1, "keys while it's up: not ordered in again (\(Ordering.count(panel)))")

            // The next word, the window still ordered in from the last one: reused as it is, asked about again.
            panel.hide()
            expect(panel.isVisible, "between words: still ordered in")
            panel.show(words, anchor: high)
            expect(Ordering.count(panel) == 1, "the next word in a burst: the window reused, not ordered in again (\(Ordering.count(panel)))")
            pump(0.3)
            expect(World.asked.count == 2, "the next word: asked again (\(World.asked))")
            // Once put away: ordered in as it comes up, asked again.
            putAway(panel)
            panel.show(others, anchor: high)
            expect(Ordering.count(panel) == 2, "after a pause: ordered in (\(Ordering.count(panel)))")
            pump(0.3)
            expect(World.asked.count == 3, "after a pause: asked again (\(World.asked))")
            panel.hide()

            // AppKit's and the window server's own: a box that can be seen is left as it is, word after word.
            CandidatePanel.surroundings = .init()
            let shared = CandidatePanel.shared
            for word in 0..<3 {
                shared.show(word % 2 == 0 ? words : others, anchor: word == 1 ? low : high)
                pump(0.8)
                expect(CandidatePanel.shared === shared && shared.isShowing && Ordering.count(shared) == word + 1,
                       "word \(word + 1): left as it is (ordered in \(Ordering.count(shared)) times)")
                putAway(shared)
            }
        }
    }

    @main struct PresenceMain {
        @MainActor static func main() {
            let scenario = CommandLine.arguments.dropFirst().first ?? ""
            _ = NSApplication.shared
            // As the input method: an agent app, which can be activated (and must never be).
            NSApp.setActivationPolicy(.accessory)
            switch scenario {
            case "hidden": Presence.hidden()
            case "offscreen": Presence.offscreen()
            case "alpha": Presence.alpha()
            case "steady": Presence.steady()
            default:
                print("unknown scenario \(scenario)")
                exit(2)
            }
            print("\(Check.failures == 0 ? "PRESENCE PASS" : "PRESENCE FAIL") \(scenario): \(Check.checks) checks, \(Check.failures) failures")
            exit(Check.failures == 0 ? 0 : 1)
        }
    }
    """#
}
