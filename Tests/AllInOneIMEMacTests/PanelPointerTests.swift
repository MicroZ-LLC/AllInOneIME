import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The pointer over the candidate panel, which every text field shares (`PanelPointer`): whoever shows something there
/// takes it with every handler at once, and a field's session has the wheel over what it shows. GitHub #66: field 1's
/// candidates took the panel, then field 2's autocomplete suggestion showed as a line of it ("Tab accept · Esc dismiss")
/// but left the wheel to field 1; a wheel over the line counted as the pointer used in field 2, and Tab and Esc went to
/// the app. Two fields' sessions as the input method's shell has them (`FakeHost`), autocomplete's model a stand-in.
struct PanelPointerTests {
    /// Translate as You Type's chip's parts, as the panel's view has them.
    enum Part { case source, target }

    /// The fields' clock (`SessionServices.uptime`), moved by the test, and when the pointer was used on it: the Mac
    /// tells any use of the pointer, the wheel over our panel too (`SessionServices.pointerUsedWithin`).
    final class World: @unchecked Sendable {
        private let lock = NSLock()
        private var time: TimeInterval = 1000
        private var used: [TimeInterval] = []

        var now: TimeInterval { lock.withLock { time } }
        func advance(_ seconds: TimeInterval) { lock.withLock { time += seconds } }
        func pointerUsed() { lock.withLock { used.append(time) } }
        func pointerUsed(within seconds: TimeInterval) -> Bool { lock.withLock { used.contains { time - $0 < seconds } } }
    }

    /// The on-device model's stand-in: every request answered at once with the same continuation.
    struct Model: AppleModelBackend {
        var availability: AppleModelAvailability { .available }
        var contextSize: Int { 4096 }
        var supportedLanguages: Set<String> { ["en", "zh"] }
        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(AppleModelSnapshot(text: "ld, how are you? Fine."))
                continuation.finish()
            }
        }
    }

    /// A text field (English) with autocomplete on (Apple Intelligence), in `world`.
    static func field(_ world: World) -> FakeHost {
        var config = Config.default
        config.provider = .apple
        config.uiLanguage = "en"
        config.setOrder([Language.english])
        config.setOrder([OutputLanguage.english, .chinese])
        config.autocomplete = true
        let settings = config
        var services = SessionServices(converter: Converter(loadConfig: { settings }, appleModel: Model()), loadSettings: { settings })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.uptime = { world.now }
        services.pointerUsedWithin = { world.pointerUsed(within: $0) }
        let host = FakeHost(services: services)
        host.appTypesKeys = true
        host.focus()
        return host
    }

    /// What `field`'s controller hands the panel's pointer, as the input method's do: its session's events.
    static func session(_ field: FakeHost, rows: Bool) -> PanelPointer<Part>.Handlers {
        .session({ [weak field] in field?.send($0) }, rows: rows, chip: rows ? { _ in } : nil)
    }

    /// Field 1's candidates take the panel; field 2 shows autocomplete's suggestion for "Hello wor" as a line of it and
    /// takes it then; a moment later the wheel over the panel (the pointer used, then the panel told), and a moment
    /// after that `key` in field 2: whether the input method took it.
    func wheelOverTheLine(then key: KeyEvent) -> (took: Bool, line: FakeHost, candidates: FakeHost, pointer: PanelPointer<Part>) {
        let world = World()
        let pointer = PanelPointer<Part>()
        let candidates = Self.field(world), line = Self.field(world)
        pointer.take(by: candidates, Self.session(candidates, rows: true))
        line.type("Hello wor")
        world.advance(0.2)
        line.fireTimers { if case .autocomplete = $0 { true } else { false } }
        #expect(line.settle(timeout: 5) { line.ghost != nil }, "a suggestion")
        pointer.take(by: line, Self.session(line, rows: false))
        world.advance(0.5)
        world.pointerUsed()
        pointer.scrolled(1)
        world.advance(0.1)
        return (line.press(key), line, candidates, pointer)
    }

    /// The line takes every handler: the rows' and the chip's are field 1's no more, the wheel is field 2's.
    @Test func whoeverShowsSomethingTakesEveryHandler() {
        let (_, line, _, pointer) = wheelOverTheLine(then: FakeHost.tab)
        #expect(pointer.owner === line)
        #expect(pointer.handlers.select == nil && pointer.handlers.delete == nil && pointer.handlers.chip == nil,
                "no row to pick on the line, and nothing left to field 1")
        #expect(pointer.handlers.scroll != nil)
    }

    /// A wheel over the line is no pointer use in its field: Tab puts the suggestion in, as the line says, and field 1's
    /// session was told nothing.
    @Test func tabAfterTheWheelOverTheLinePutsTheSuggestionIn() {
        let (took, line, candidates, _) = wheelOverTheLine(then: FakeHost.tab)
        #expect(took, "Tab is the input method's, not the app's")
        #expect(line.document == "Hello world, how are you?" && line.ghost == nil, "\(line.document)")
        #expect(candidates.session.caretMayHaveMoved(within: 60), "field 1's session had none of the wheel")
    }

    /// The same for Esc: it only takes the suggestion down, and never reaches the app.
    @Test func escAfterTheWheelOverTheLineTakesItDown() {
        let (took, line, _, _) = wheelOverTheLine(then: FakeHost.escape)
        #expect(took, "Esc is the input method's, not the app's")
        #expect(line.document == "Hello wor" && line.ghost == nil, "\(line.document)")
    }

    /// A notice no text field shows (near the pointer) takes the panel with nothing: the wheel over it is no field's.
    @Test func aNoticeOfNoFieldTakesItWithNothing() {
        let world = World()
        let pointer = PanelPointer<Part>()
        let field = Self.field(world)
        pointer.take(by: field, Self.session(field, rows: true))
        let notice = NSObject()
        pointer.take(by: notice, .none)
        #expect(pointer.owner === notice)
        world.pointerUsed()
        pointer.scrolled(1)
        world.advance(0.1)
        #expect(field.session.caretMayHaveMoved(within: 60), "the field had none of it")
    }

    /// The input method takes the shared panel only with `take` (`CandidatePanel.take`): nothing sets its owner or one
    /// of the pointer's handlers on its own, which would leave the rest to whoever showed the panel before.
    @Test func theInputMethodTakesThePanelOnlyWithTake() throws {
        let folder = StringCatalogTests.root.appendingPathComponent("Sources/AllInOneIME")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        #expect(files.count > 20)
        let set = try NSRegularExpression(pattern: #"\b(panel|CandidatePanel\.shared)(\.view)?\.(owner|onSelect|onDelete|onScroll|onChip)\s*=[^=]"#)
        var found: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in source.components(separatedBy: "\n").enumerated()
            where set.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                found.append("\(file.lastPathComponent):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }
}
