import AllInOneIMECore
import AllInOneIMEWire
import Foundation

/// The engine's `WireHost` for now (M2): what the wire doesn't carry is logged, not done yet (the panel isn't drawn,
/// nothing is opened, no model is asked). A request the Composer would wait on fails at once (`Composer.fail`: the
/// panel would say why, Esc gives the draft back), so that it doesn't wait forever. In test mode, level two comes from
/// a `ScriptedProvider` (a golden's `#! provider`) and the client is taken to own the foreground.
final class EngineHost: WireHost, @unchecked Sendable {
    let testMode: Bool
    let clock: WireClock
    let log: @Sendable (String) -> Void
    /// Whether the client's process owns the foreground window (§8).
    let foreground: @Sendable (WirePeer) -> Bool

    private let lock = NSLock()
    private var scripted: ScriptedProvider?
    private var language = Language.english

    init(testMode: Bool, clock: WireClock, foreground: @escaping @Sendable (WirePeer) -> Bool,
         log: @escaping @Sendable (String) -> Void) {
        self.testMode = testMode
        self.clock = clock
        self.foreground = foreground
        self.log = log
    }

    /// Test mode: level two's script (`#! provider`).
    var provider: ScriptedProvider? {
        get { lock.lock(); defer { lock.unlock() }; return scripted }
        set { lock.lock(); scripted = newValue; lock.unlock() }
    }

    /// The input language new Composers start in (`#! inputLanguage` in test mode).
    var inputLanguage: Language {
        get { lock.lock(); defer { lock.unlock() }; return language }
        set { lock.lock(); language = newValue; lock.unlock() }
    }

    /// A field's Composer: Latin letters (no language pack on Windows yet), in the input language.
    func makeComposer(_ field: FieldInfo, _ peer: WirePeer) -> Composer {
        let composer = Composer(engine: LatinEngine())
        composer.setInputMode(inputLanguage)
        return composer
    }

    static let unavailable = "Not available in the Windows engine yet"

    func perform(_ effect: Composer.Effect, in session: ComposerSession) {
        let kind = ComposerSession.kind(of: effect)
        if effect == .cancelConversion {
            provider?.cancel(in: session)
            return
        }
        if let provider, provider.start(effect, in: session) {
            log("session \(session.sid): \(kind): scripted")
            return
        }
        switch effect {
        case let .notice(text):
            log("session \(session.sid): notice (\(text.count) characters): not shown yet")
        case let .startConversion(_, id), let .startCommand(_, _, id), let .startRefine(_, id), let .search(_, id),
             let .listAgents(id), let .previewReminder(_, id), let .startRun(_, _, id), let .startScript(_, _, _, id, _),
             let .reask(_, _, id), let .startPlan(_, _, id), let .startTranslateMode(_, _, id):
            log("session \(session.sid): \(kind): not available yet, failed")
            session.feed { $0.fail(Self.unavailable, id: id) }
        case let .readClipboard(id):
            log("session \(session.sid): readClipboard: not available yet")
            session.feed { $0.pasted(nil, id: id) }
        case let .startVoice(id, _):
            log("session \(session.sid): startVoice: not available yet")
            session.feed { $0.voiceFailed(Self.unavailable, id: id) }
        default:
            log("session \(session.sid): \(kind): not performed yet")
        }
    }

    func panel(shown: Bool, in session: ComposerSession) {
        log("session \(session.sid): panel \(shown ? "shown" : "hidden") (not drawn yet)")
    }

    func caretMoved(in session: ComposerSession) {
        guard let caret = session.caret else { return }
        log("session \(session.sid): caret \(caret.rect)\(caret.exact ? "" : " (the window's)")")
    }

    func ownsForeground(_ peer: WirePeer) -> Bool { testMode || foreground(peer) }

    func sessionClosed(_ session: ComposerSession) { provider?.cancel(in: session) }

    /// Test mode's directives the server leaves to the engine: `provider <file>` (the fixture comes in the frame) and
    /// `inputLanguage <name>`.
    func testDirective(_ directive: String, _ frame: TestFrame) -> Bool {
        let words = directive.split(separator: " ").map(String.init)
        switch (words.first, words.count) {
        case ("provider", 2):
            guard let fixture = frame.fixture else { return false }
            provider = ScriptedProvider(fixture: fixture, clock: clock)
            return true
        case ("inputLanguage", 2):
            guard let named = Self.language(words[1]) else { return false }
            inputLanguage = named
            return true
        default:
            return false
        }
    }

    static func language(_ name: String) -> Language? {
        switch name {
        case "english": return .english
        case "chinese": return .chinese
        case "french": return .french
        case "korean": return .korean
        case "hindi": return .hindi
        default: return nil
        }
    }
}
