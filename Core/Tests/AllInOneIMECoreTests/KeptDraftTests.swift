import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A draft kept while the focus is elsewhere (#180, InputSession+KeptDraft.swift), as the review of it found it (each
/// test one finding): it never comes back in a password field or while secure input is on; a shell that can't tell yet
/// whether the field taking the focus is the one left holds it (`holdKeptDraft`) until it can (`releaseKeptDraft`), and
/// a key before that drops it; it goes after ten minutes; a modifier key with no focus told shows it, as a key does;
/// librime deployed again meanwhile leaves nothing composed.
@Suite(.serialized)
struct KeptDraftTests {
    final class World: @unchecked Sendable {
        var secure = false
        var now: TimeInterval = 1_000
        var valid = true
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
        }
    }

    /// A session in a field that has the focus, pinyin first.
    func host(_ world: World) -> FakeHost {
        var services = SessionServices(loadSettings: { world.config })
        services.levelOne = { .engine(FakeEngine()) }
        services.engineIsValid = { _ in world.valid }
        services.secureInputActive = { world.secure }
        services.uptime = { world.now }
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    /// Review #1: secure input turned on while the focus was elsewhere (a password field of the same client took it):
    /// the draft doesn't come back, and the password's first key puts nothing of it in.
    @Test(arguments: ["nihao", "@q"]) func aKeptDraftNeverComesBackWhileSecureInputIsOn(_ typed: String) async {
        await inEnglish {
            let world = World()
            let host = host(world)
            host.type(typed)
            host.send(.blur)
            #expect(host.session.keepsDraft)
            world.secure = true
            host.focus()
            #expect(!host.session.keepsDraft && !host.composer.isComposing && host.panel == nil, "\(host.preedit)")
            // The password's first key, told with secure input on as the Mac tells it (`FieldContext.secure`).
            (host.appTypesKeys, host.secure) = (true, true)
            host.type("s")
            #expect(host.document == "s", "the password field holds \(host.document.debugDescription)")
        }
    }

    /// The same for a field told to be a secure one at its focus (`FieldInfo.secure`).
    @Test func aKeptDraftNeverComesBackInASecureField() async {
        await inEnglish {
            let world = World()
            let host = host(world)
            host.type("nihao")
            host.send(.blur)
            host.send(.focus(FieldInfo(app: host.app, secure: true)))
            #expect(!host.session.keepsDraft && !host.composer.isComposing && host.panel == nil)
        }
    }

    /// Review #1: the shell can't tell yet whether the field taking the focus is the one left: held, the draft stays
    /// hidden through the focus, and shows once the shell says it is that field.
    @Test func aHeldDraftShowsOnlyOnceTheShellSaysItIsTheSameField() async {
        await inEnglish {
            let host = host(World())
            host.type("nihao")
            host.send(.blur)
            host.session.holdKeptDraft()
            host.focus()
            #expect(host.session.keepsDraft && host.panel == nil && host.composer.isComposing)
            host.releaseKeptDraft()
            #expect(!host.session.keepsDraft && host.preedit == "nihao" && host.panel != nil, "\(host.preedit)")
            host.type("wo")
            #expect(host.preedit == "nihaowo" && host.document.isEmpty, "\(host.preedit)")
        }
    }

    /// A key before the shell could tell: the field typed in may be another one, so the draft goes, nothing of it in,
    /// and the key starts afresh. Another field (the shell's `cancel`) drops it the same way.
    @Test func aHeldDraftGoesWithAKeyOrACancel() async {
        await inEnglish {
            let typed = host(World())
            typed.type("nihao")
            typed.send(.blur)
            typed.session.holdKeptDraft()
            typed.focus()
            typed.type("wo")
            #expect(!typed.session.keepsDraft && typed.preedit == "wo" && typed.document.isEmpty, "\(typed.preedit)")
            // Released after it went: nothing to show.
            typed.releaseKeptDraft()
            #expect(typed.preedit == "wo")

            let other = host(World())
            other.type("nihao")
            other.send(.blur)
            other.session.holdKeptDraft()
            other.focus()
            other.send(.cancel)
            #expect(!other.session.keepsDraft && !other.composer.isComposing && other.panel == nil && other.document.isEmpty)
            // The hold ends with the draft: the next one kept comes back as any does.
            other.type("ni")
            other.send(.blur)
            other.focus()
            #expect(other.preedit == "ni", "\(other.preedit)")
        }
    }

    /// Review #2: a draft kept longer than ten minutes doesn't come back (`InputSession.keptDraftLife`).
    @Test func aKeptDraftGoesAfterTenMinutes() async {
        await inEnglish {
            let world = World()
            let recent = host(world)
            recent.type("nihao")
            recent.send(.blur)
            world.now += InputSession.keptDraftLife - 1
            recent.focus()
            #expect(recent.preedit == "nihao", "\(recent.preedit)")

            let stale = host(world)
            stale.type("nihao")
            stale.send(.blur)
            world.now += InputSession.keptDraftLife + 1
            stale.focus()
            #expect(!stale.session.keepsDraft && !stale.composer.isComposing && stale.panel == nil && stale.document.isEmpty)
        }
    }

    /// Review #6: a modifier key with no focus told first (the action key as a tap of Option) is the field typed in
    /// again, as a key is: the draft shows, and so does what the key does next.
    @Test func aModifierKeyWithNoFocusToldShowsTheKeptDraft() async {
        await inEnglish {
            let host = host(World())
            host.type("nihao")
            host.send(.blur)
            #expect(host.session.keepsDraft && host.panel == nil)
            host.modifiers(ModifierChange(key: .modifier(.option, .left), modifiers: .option, timestamp: 1))
            #expect(!host.session.keepsDraft && host.preedit == "nihao" && host.panel != nil, "\(host.preedit)")
        }
    }

    /// Review #4: librime deployed again while pinyin was kept: its pinyin went with the engine, and nothing is left
    /// composed (the composer idle, so the field's settings apply), the next key starting afresh.
    @Test func librimeDeployedAgainWhileADraftIsKeptLeavesNothingComposed() async {
        await inEnglish {
            let world = World()
            let host = host(world)
            host.type("nihao")
            host.send(.blur)
            world.valid = false
            host.focus()
            world.valid = true
            #expect(host.composer.phase == .idle && !host.composer.isComposing, "\(host.composer.phase)")
            #expect(host.panel == nil && host.document.isEmpty)
            host.type("wo")
            #expect(host.preedit == "wo", "\(host.preedit)")
        }
    }

    /// A draft of a command's own text stays through the same deployment: only the pinyin went.
    @Test func aCommandsDraftStaysWhenLibrimeIsDeployedAgain() async {
        await inEnglish {
            let world = World()
            let host = host(world)
            host.composer.setInputMode(.english)
            host.type("@improve ok")
            host.send(.blur)
            world.valid = false
            host.focus()
            world.valid = true
            #expect(host.preedit == "improve › ok" && host.composer.phase == .drafting, "\(host.preedit)")
        }
    }
}
