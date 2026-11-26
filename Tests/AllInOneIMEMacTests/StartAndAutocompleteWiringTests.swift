import AllInOneIMEMac
import Foundation
import Testing

/// What the review of 0.7.6's start and Settings found, read from the input method's sources (the executable target
/// can't be linked into a test; the logic each part goes by is tested where it lives: `InputSourceCheck.isEnabledNow`
/// below, `Config.fastConfig` and one @'s click in the core).
struct StartAndAutocompleteWiringTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The Swift source at `path` without comments.
    func code(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.range(of: "//").map { line[..<$0.lowerBound] } ?? line }
            .joined(separator: "\n")
    }

    /// `code` from `start` to the end of its block (the first line closing at `start`'s indentation).
    func block(_ code: String, _ start: String) throws -> String {
        let begin = try #require(code.range(of: start), "no \(start)")
        let lineStart = code[..<begin.lowerBound].lastIndex(of: "\n").map { code.index(after: $0) } ?? code.startIndex
        let indent = String(code[lineStart..<begin.lowerBound].prefix { $0 == " " })
        let rest = code[begin.lowerBound...]
        let end = rest.range(of: "\n" + indent + "}")?.upperBound ?? rest.endIndex
        return String(rest[..<end])
    }

    // MARK: - The start's step 1 never blocks the main thread (rule 6)

    /// Step 1 looks whether the input source is added as the window shows and as each one is added or taken out, on the
    /// main thread: read only (`InputSourceCheck.isEnabledNow`), never the check that registers the bundle and waits up
    /// to 2 s for it, nor the one that synchronizes the user's input sources' preferences.
    @Test func stepOneLooksAtTheInputSourceReadOnly() throws {
        let window = try code("Sources/AllInOneIME/StartWindow.swift")
        #expect(!window.contains("check.isEnabled()") && !window.contains("InputSourceCheck.system("), "a registering check on the main thread")
        #expect(!window.contains("InputSourceCheck.state(of:"), "the user's input sources' preferences read on the main thread")
        #expect(window.contains("InputSourceCheck.isEnabledNow("), "step 1 doesn't look read only")
    }

    /// The start shows the settings Settings has (kept by `SettingsWindow`), not a second model read from the config file
    /// and the AWS files on the main thread; and so what Settings looks at (a CLI's sign-in) is what the start sees.
    @Test func theStartSharesSettingsModel() throws {
        let window = try code("Sources/AllInOneIME/StartWindow.swift")
        #expect(!window.contains("SettingsModel()"), "the start builds settings of its own")
        #expect(window.contains("SettingsWindow.shared.settings"), "the start doesn't take Settings' model")
        let settings = try code("Sources/AllInOneIME/SettingsWindow.swift")
        let show = try block(settings, "private func show(opening page: SettingsPage?)")
        #expect(show.components(separatedBy: "SettingsModel()").count == 1, "Settings builds a model beside the start's: \(show)")
    }

    // MARK: - Step 2 goes on with a CLI

    /// Back on the start (from Settings or Terminal) on step 2 with a CLI chosen that isn't ready: its sign-in looked at
    /// now (forced: one signed in in Terminal within the last minute), and the step goes on when the look comes back.
    @Test func backOnStepTwoTheCLIChosenIsLookedAtAgain() throws {
        let window = try code("Sources/AllInOneIME/StartWindow.swift")
        let refresh = try block(window, "private static func refreshAI(")
        #expect(refresh.contains("config.ai.agent"), "\(refresh)")
        #expect(refresh.contains("refreshSessions([agent], force: true)"), "the CLI chosen isn't looked at again: \(refresh)")
    }

    // MARK: - Use My Own AI… unfolds the other AIs whatever is in use

    @Test func useMyOwnAIPointsAtACardNotInUse() throws {
        let view = try code("Sources/AllInOneIME/StartView.swift")
        let own = try block(view, "private func ownAI(")
        #expect(!own.contains("card: AIChoice.all.first)"), "the first card, which may be the one in use (folded then): \(own)")
        #expect(own.contains("!= settings.config.ai"), "\(own)")
    }

    // MARK: - Autocomplete: one answer for Settings, the input menu and the menu-bar panel (rule 1)

    @Test func theInputMenuAndThePanelGoByTheFastConfig() throws {
        let menu = try code("Sources/AllInOneIME/InputMenu.swift")
        let item = try block(menu, "func addingAutocomplete(to menu: NSMenu)")
        #expect(item.contains("AutocompleteSwitch.shown("), "the input menu's switch doesn't go by the fast config: \(item)")
        #expect(item.contains("shown.available"), "the input menu's switch can be turned on where it can't run: \(item)")
        #expect(!item.contains("AutocompleteSwitch.modelName(current)"), "the menu names the provider, not the fast fallback")
        let panel = try code("Sources/AllInOneIME/FloatingPanel.swift")
        #expect(!panel.contains("AutocompleteSwitch.modelName(LiveConfig.current)"), "the panel names the provider, not the fast fallback")
        #expect(!panel.contains("AutocompleteSwitch.destination(LiveConfig.current)"), "the panel's destination isn't the fast fallback's")
        #expect(panel.contains("AutocompleteSwitch.shown(LiveConfig.current)"), "the panel doesn't go by the fast config")
        let toggle = try block(panel, "private var autocompleteSwitch: some View")
        #expect(toggle.contains(".disabled("), "the panel's switch can be turned on where it can't run: \(toggle)")
        let settings = try code("Sources/AllInOneIME/ClaudeSessionSettings.swift")
        #expect(settings.contains("config.fastConfig(aiFacts)"), "Settings goes by another rule than the menu")
    }

    // MARK: - Settings → AI's note, true with a CLI in both languages (rule 14)

    @Test func theProviderNoteIsTrueWithACLIInBothLanguages() throws {
        let note = try block(try code("Sources/AllInOneIME/SettingsSearch.swift"), "var note: String? {")
        let from = try #require(note.range(of: "case .provider:"), "no provider note")
        let line = note[from.lowerBound...].prefix { $0 != "}" }.components(separatedBy: "\n        case ").first ?? ""
        #expect(!line.contains("所有 AI 功能都用它") && !line.localizedCaseInsensitiveContains("every AI feature")
                    && !line.localizedCaseInsensitiveContains("all the AI features"), "\(line)")
    }
}

/// The read-only look at an input source (`InputSourceCheck.isEnabledNow`): enabled as itself, as Text Input Sources has
/// it now, nothing registered or waited for.
struct InputSourceReadOnlyTests {
    static let id = "com.allinoneime.inputmethod.AllInOneIME"

    @Test func enabledAsItselfOnly() {
        func state(_ registered: Bool, _ enabled: Bool, _ bundle: String?) -> InputSourceState {
            InputSourceState(registered: registered, enabled: enabled, listed: false, bundleID: bundle)
        }
        #expect(InputSourceCheck.isEnabledNow(Self.id, as: state(true, true, Self.id)))
        #expect(InputSourceCheck.isEnabledNow(Self.id, as: state(true, true, nil)))
        #expect(!InputSourceCheck.isEnabledNow(Self.id, as: state(true, false, Self.id)))
        #expect(!InputSourceCheck.isEnabledNow(Self.id, as: state(false, false, nil)), "not registered yet: not added")
        #expect(!InputSourceCheck.isEnabledNow(Self.id, as: state(true, true, "com.example.inputmethod.Old")))
    }

    /// The Mac's own look, for an ID no input source has: not enabled, at once (the registering check waits up to 2 s
    /// for a source that doesn't come).
    @Test @MainActor func aSourceThatIsntThereIsNotEnabledAtOnce() {
        let start = Date()
        #expect(!InputSourceCheck.isEnabledNow("com.example.inputmethod.NotInstalled"))
        #expect(Date().timeIntervalSince(start) < 0.5)
    }
}
