import AllInOneIMECore
import Foundation
import Testing

/// Runtime acceptance tests for 0.7.6 UI review items 21–24.
///
/// The input method and installer are executable targets and cannot be imported directly, so `ReviewUI076AppChild`
/// and `ReviewUI076InstallerChild` compile them with `SourceCompiler` and run their real types (`SettingsSpot`,
/// `AllInOneIMEInputController.makeMenu`, `showPreferences`, `StartModel`, `StartView`, `SettingsModel`,
/// `SettingsView`, `Installer`) offline in a temporary home with an in-memory keychain and stubbed Apple model.
/// Only OS-coupled seams that cannot be driven without mutating the host Mac's Text Input Sources, opening a modal
/// `NSAlert`, or flipping a compile-time `static let` remain as small documented source checks.
@Suite(.serialized)
struct ReviewUI076AcceptanceTests {
    private static let root = ReviewUI076AppChild.repository

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static func between(_ text: String, _ start: String, _ end: String) throws -> String {
        let first = try #require(text.range(of: start), "Missing \(start)")
        let last = try #require(text.range(of: end, range: first.upperBound..<text.endIndex), "Missing \(end)")
        return String(text[first.lowerBound..<last.lowerBound])
    }

    // MARK: - Item 21: Input menu language links open Settings at their row

    /// Item 21: `SettingsSpot.outputLanguages` and `.inputLanguages` both live on `.common` (not `.ai`); the real
    /// `NSMenu` built by `makeMenu()` attaches those `SettingsSpot` raw values to "Add or Reorder Languages…" and
    /// "Add Languages…" in both languages; and invoking `showPreferences(_:)` with those items opens `.common` at
    /// each row.
    @Test func outputAndInputLanguageMenuItemsOpenSettingsAtTheirRow() throws {
        let report = try ReviewUI076AppChild.report.get()
        #expect(report["21_OUTPUT_PAGE"] == "common", "Translate to must live on Common")
        #expect(report["21_INPUT_PAGE"] == "common", "Input languages must live on Common")
        #expect(report["21_COMMON_HAS_OUTPUT"] == "1")
        #expect(report["21_AI_HAS_OUTPUT"] == "0", "Translate to should no longer be listed on AI")
        #expect(report["21_COMMON_HAS_INPUT"] == "1")

        for lang in ["en", "zh"] {
            #expect(report["21_\(lang)_ADD_OUTPUT_ACTION"] == "showPreferences:")
            #expect(report["21_\(lang)_ADD_OUTPUT_OBJ"] == "outputLanguages",
                    "Add or Reorder Languages… should carry only the SettingsSpot raw value (\(lang))")
            #expect(report["21_\(lang)_ADD_OUTPUT_RESOLVED_PAGE"] == "common")
            #expect(report["21_\(lang)_UNWRAP_OK"] == "1", "menuItem(from:) must unwrap both NSMenuItem and IMK info dict")
            #expect(report["21_\(lang)_ADD_INPUT_ACTION"] == "showPreferences:")
            #expect(report["21_\(lang)_ADD_INPUT_OBJ"] == "inputLanguages",
                    "Add Languages… should carry only the SettingsSpot raw value (\(lang))")
            #expect(report["21_\(lang)_ADD_INPUT_RESOLVED_PAGE"] == "common")
            #expect(report["21_\(lang)_SETTINGS_OBJ_NIL"] == "1", "Settings… carries no spot")
        }

        #expect(report["21_SHOW_OUTPUT_PAGE"] == "common", "showPreferences(addOutput) must open Common")
        #expect(report["21_SHOW_OUTPUT_SPOT"] == "outputLanguages", "showPreferences(addOutput) must target outputLanguages")
        #expect(report["21_SHOW_INPUT_PAGE"] == "common", "showPreferences(addInput) must open Common")
        #expect(report["21_SHOW_INPUT_SPOT"] == "inputLanguages", "showPreferences(addInput) must target inputLanguages")
    }

    // MARK: - Item 22: Start step 2 choices and advancing when the chosen AI is ready

    /// Item 22 (UI): the real `StartView` at step 2 renders no Google sign-in button while `HostedService.googleEnabled`
    /// is false, offers Email sign-in, and offers exactly one "Use My Own AI…" button in both languages.
    @Test func startStepTwoRendersAvailableSignInEmailDefaultAndOneOwnAIButton() throws {
        let report = try ReviewUI076AppChild.report.get()
        let googleEnabled = report["22_GOOGLE_ENABLED"] == "1"
        #expect(googleEnabled == HostedService.googleEnabled)

        for lang in ["en", "zh"] {
            #expect(report["22_\(lang)_GOOGLE_COUNT"] == (googleEnabled ? "1" : "0"),
                    "Google button count must match HostedService.googleEnabled (\(lang)): \(report["22_\(lang)_BUTTONS"] ?? "")")
            #expect(report["22_\(lang)_EMAIL_COUNT"] == "1", "Email sign-in button missing (\(lang))")
            #expect(report["22_\(lang)_OWN_COUNT"] == "1", "Step 2 must have exactly one Use My Own AI… button (\(lang))")
            #expect(report["22_\(lang)_LATER_COUNT"] == "1", "Later button missing (\(lang))")
            let total = (report["22_\(lang)_BUTTONS"] ?? "").split(separator: "|").count
            #expect(total == (googleEnabled ? 4 : 3),
                    "Unexpected extra buttons on step 2 (\(lang)): \(report["22_\(lang)_BUTTONS"] ?? "")")
        }

        // Source checks only for what cannot be exercised at runtime:
        // 1. `HostedService.googleEnabled` is a compile-time `static let` constant, so its `true` branch cannot be
        //    flipped at runtime.
        // 2. SwiftUI's `.keyboardShortcut(.defaultAction)` is not exposed via `NSWindow.accessibilityDefaultButton()`,
        //    and sending Return would invoke `settings.signIn(.email)` (`ASWebAuthenticationSession`).
        let view = try Self.source("Sources/AllInOneIME/StartView.swift")
        let connect = try Self.between(view, "private var connectStep:", "private func ownAI(")
        let google = try Self.between(connect, "Button(tr(\"用 Google 登录\"", "Button(tr(\"用邮箱登录")
        let email = try Self.between(connect, "Button(tr(\"用邮箱登录", "if settings.accountBusy")
        #expect(connect.contains("if HostedService.googleEnabled"),
                "Start step 2 must gate Google sign-in on HostedService.googleEnabled")
        #expect(!google.contains(".keyboardShortcut(.defaultAction)"),
                "Google sign-in must not be the default action")
        #expect(email.contains(".keyboardShortcut(.defaultAction)"),
                "Email sign-in must be the default action on step 2")
    }

    /// Item 22 (transitions): `StartModel.aiReady(_:)` advances step 2 → 3 when the chosen AI is ready (any signed-in
    /// CLI, saved or shell API key, available Apple Intelligence, valid AWS Bedrock profile, or AllInOneIME Cloud),
    /// stays at step 2 when not ready, and does nothing on step 1 or step 3.
    @Test func startModelAdvancesFromStepTwoWhenChosenAIBecomesReady() throws {
        let report = try ReviewUI076AppChild.report.get()
        #expect(report["22_STEP1_AIREADY_TRUE"] == "1", "aiReady(true) must not skip step 1")
        #expect(report["22_STEP2_AIREADY_FALSE"] == "2", "aiReady(false) must keep step 2")
        #expect(report["22_STEP2_AIREADY_TRUE"] == "3", "aiReady(true) must advance step 2 to 3")
        #expect(report["22_STEP3_AIREADY_FALSE"] == "3", "aiReady(false) must keep step 3")

        for agent in SessionAgent.allCases {
            #expect(report["22_CLI_\(agent.rawValue)_READY"] == "3", "\(agent.rawValue) signed in must advance step 2")
            #expect(report["22_CLI_\(agent.rawValue)_SIGNEDOUT"] == "2", "\(agent.rawValue) signed out must stay at step 2")
            #expect(report["22_CLI_\(agent.rawValue)_UNKNOWN"] == "2", "\(agent.rawValue) unknown must stay at step 2")
            #expect(report["22_CLI_\(agent.rawValue)_NOTINSTALLED"] == "2", "\(agent.rawValue) not installed must stay at step 2")
        }
        for provider in [Provider.anthropic, .openai, .gemini] {
            #expect(report["22_KEY_\(provider.rawValue)_SAVED"] == "3", "\(provider.rawValue) saved key must advance step 2")
            #expect(report["22_KEY_\(provider.rawValue)_SHELL"] == "3", "\(provider.rawValue) shell key must advance step 2")
            #expect(report["22_KEY_\(provider.rawValue)_NONE"] == "2", "\(provider.rawValue) without key must stay at step 2")
        }
        #expect(report["22_APPLE_AVAILABLE"] == "3", "Available Apple Intelligence must advance step 2")
        #expect(report["22_APPLE_NOTENABLED"] == "2", "Disabled Apple Intelligence must stay at step 2")
        #expect(report["22_AWS_READY"] == "3", "AWS Bedrock profile with credentials must advance step 2")
        #expect(report["22_AWS_NOCREDS"] == "2", "AWS profile without credentials must stay at step 2")
        #expect(report["22_AWS_MISSING"] == "2", "Missing AWS profile must stay at step 2")
        #expect(report["22_HOSTED_READY"] == "3", "Signed-in AllInOneIME Cloud must advance step 2")
        #expect(report["22_HOSTED_SIGNEDOUT"] == "2", "Signed-out AllInOneIME Cloud must stay at step 2")
    }

    /// Item 22 (window wiring): `StartWindow` feeds the chosen AI's readiness into `StartModel.aiReady(_:)` and
    /// refreshes the chosen CLI's sign-in when returning to step 2 (not only reading a stale in-memory cache).
    /// Source check only because `StartWindow.show()` binds to the host Mac's live `TISCopyCurrentKeyboardInputSource`,
    /// so offline tests cannot force it onto step 2 and return from Settings.
    @Test func startWindowWiresChosenAIAndCLIReadinessToStepTwo() throws {
        let window = try Self.source("Sources/AllInOneIME/StartWindow.swift")
        #expect(window.contains("model.aiReady("), "StartWindow must drive StartModel.aiReady(_:)")
        #expect(window.contains("settings.aiFacts.status(settings.config.ai, config: settings.config).isReady"),
                "StartWindow must observe readiness of the chosen AI")
        let refreshesCLI = window.contains("refreshSessions(") || window.contains("checkAvailability(")
        #expect(refreshesCLI,
                "StartWindow must probe the chosen CLI's sign-in when refreshing AI on step 2, not only read a stale cache")
    }

    // MARK: - Item 23: Fresh install opens guide; step 1 reacts when input source is added

    /// Item 23: `StartModel.inputSourceAdded(_:)` drives `StartView` step 1 between the "Add AllInOneIME first" view
    /// (with the Keyboard Settings default button) and the "Switch to AllInOneIME" view in both languages, and the
    /// installer's fresh-install arguments/copy launch `--start` while updates with a missing input source keep the old
    /// manual-add dialog.
    @Test func freshInstallOpensGuideAndStepOneUpdatesWhenInputSourceIsAdded() throws {
        let app = try ReviewUI076AppChild.report.get()
        #expect(app["23_KEYBOARD_URL"] == "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        for lang in ["en", "zh"] {
            #expect(app["23_\(lang)_NOT_ADDED_STATE"] == "1:0")
            #expect(app["23_\(lang)_BEFORE_HAS_KB_BTN"] == "1", "Step 1 must show Open Keyboard Settings as default button when not added (\(lang))")
            #expect(app["23_\(lang)_BEFORE_HAS_ADD_TITLE"] == "1", "Step 1 must show Add heading when not added (\(lang))")
            #expect(app["23_\(lang)_BEFORE_HAS_SWITCH_TITLE"] == "0", "Step 1 must not show Switch heading before input source is added (\(lang))")

            #expect(app["23_\(lang)_ADDED_STATE"] == "1:1")
            #expect(app["23_\(lang)_AFTER_HAS_KB_BTN"] == "0", "Open Keyboard Settings button must disappear once added (\(lang))")
            #expect(app["23_\(lang)_AFTER_HAS_SWITCH_TITLE"] == "1", "Step 1 must update to Switch heading once added (\(lang))")
            #expect(app["23_\(lang)_AFTER_HAS_ADD_TITLE"] == "0")

            #expect(app["23_\(lang)_SWITCHED_STATE"] == "2:1", "Selecting our input source must mark added and advance to step 2 (\(lang))")
        }

        for (lang, probe, expectedButton) in [("en", "Cancel", "Get Started"), ("zh", "取消", "开始使用")] {
            let installer = try ReviewUI076InstallerChild.run(interface: lang)
            try #require(installer["PROBE"] == probe, "Installer child not in \(lang)")
            #expect(installer["ARGS_FRESH"] == "--start", "Fresh install must pass --start (\(lang))")
            #expect(installer["ARGS_UPDATE"] == "", "Update must pass no arguments (\(lang))")
            let addInStart = try #require(installer["ADD_IN_START"])
            #expect(addInStart.contains(expectedButton), "Fresh-install missing-source copy must mention \(expectedButton) (\(lang)): \(addInStart)")
            let manualHint = try #require(installer["MANUAL_ADD_HINT"])
            #expect(!manualHint.isEmpty)
        }

        // Source checks only for OS-coupled seams that cannot run offline: `InstallerDelegate.installed()` reads the
        // host Mac's live Text Input Sources and presents a modal `NSAlert` + `NSApp.terminate`, and `StartWindow.show()`
        // subscribes to live `TIS` distributed notifications.
        let installerMain = try Self.source("Sources/AllInOneIMEInstaller/main.swift")
        let installed = try Self.between(installerMain, "func installed()", "/// The last dialog:")
        #expect(!installed.contains("guard state.enabled && state.listed else"),
                "Missing input source must not prevent a fresh install from launching --start")
        #expect(installed.contains("if !fresh, !added") || installed.contains("if !fresh && !added"),
                "An update with a missing input source must still get the old manual-add dialog")
        #expect(installed.contains("tr(\"开始使用\", \"Get Started\")"),
                "Fresh install's final button must be Get Started")
        #expect(installed.contains("Installer.settingsAppArguments(fresh: self.fresh)"),
                "Final button must pass Installer.settingsAppArguments(fresh:)")

        let startWindow = try Self.source("Sources/AllInOneIME/StartWindow.swift")
        #expect(startWindow.contains("kTISNotifyEnabledKeyboardInputSourcesChanged"),
                "StartWindow must observe enabled input source changes")
        #expect(startWindow.contains("model.inputSourceAdded("),
                "Enabled input source changes must update StartModel.inputSourceAdded(_:)")
    }

    // MARK: - Item 24: CLI Autocomplete state & provider note copy

    /// Item 24: with a CLI chosen and no faster AI, Settings → Common shows the Autocomplete switch off and disabled
    /// while keeping `config.autocomplete` as saved (on memory and disk), and enables it again once a faster AI is
    /// available; in both languages via `tr`, the note beside the AI cards says `@question` uses the CLI and does not
    /// claim every AI feature uses it.
    @Test func cliAutocompleteShowsOffAndDisabledWhilePreservingConfigAndProviderNoteMatchesRouting() throws {
        let report = try ReviewUI076AppChild.report.get()
        for (lang, settingsLink, forbidden) in [
            ("en", "Settings → AI", ["every ai feature", "all the ai features", "all ai features"]),
            ("zh", "设置 →「AI」", ["所有 ai 功能", "所有ai功能"]),
        ] {
            // Provider note via tr output in both languages and with a custom trigger.
            let cliNote = try #require(report["24_\(lang)_NOTE_CLI_AT"])
            let cliTilde = try #require(report["24_\(lang)_NOTE_CLI_TILDE"])
            let providerNote = try #require(report["24_\(lang)_NOTE_PROVIDER"])
            #expect(cliNote != providerNote, "CLI provider note must differ from non-CLI provider note (\(lang))")
            #expect(cliNote.contains("@question"), "CLI provider note must say @question uses the CLI (\(lang)): \(cliNote)")
            #expect(cliTilde.contains("~question") && !cliTilde.contains("@question"),
                    "CLI provider note must use the configured command trigger (\(lang)): \(cliTilde)")
            #expect(cliNote.contains("CLI"), "CLI provider note must mention CLI (\(lang)): \(cliNote)")
            for phrase in forbidden {
                #expect(!cliNote.lowercased().contains(phrase),
                        "CLI provider note must not claim '\(phrase)' (\(lang)): \(cliNote)")
            }

            // Rendered Settings → AI header displays the CLI note beside the AI cards.
            let aiHeader = try #require(report["24_\(lang)_AI_HEADER_TEXT"])
            #expect(aiHeader.contains(cliNote),
                    "Settings → AI header must display the CLI note when a CLI is chosen (\(lang)); got:\n\(aiHeader)")

            // Rendered Settings → Common Autocomplete switch with CLI and no faster AI.
            #expect(report["24_\(lang)_NOFAST_FASTCONFIG_NIL"] == "1")
            #expect(report["24_\(lang)_NOFAST_FOUND_TOGGLE"] == "1", "Autocomplete switch not found in SettingsView (\(lang))")
            #expect(report["24_\(lang)_NOFAST_TOGGLE_ON"] == "0",
                    "Autocomplete switch must show off with a CLI and no faster AI (\(lang))")
            #expect(report["24_\(lang)_NOFAST_TOGGLE_ENABLED"] == "0",
                    "Autocomplete switch must be disabled with a CLI and no faster AI (\(lang))")
            #expect(report["24_\(lang)_NOFAST_CONFIG_KEPT"] == "1",
                    "config.autocomplete in memory must remain as saved (\(lang))")
            #expect(report["24_\(lang)_NOFAST_DISK_KEPT"] == "1",
                    "config.autocomplete on disk must remain as saved (\(lang))")
            let commonText = try #require(report["24_\(lang)_NOFAST_TEXT"])
            #expect(commonText.contains(settingsLink),
                    "Autocomplete explanation must keep the \(settingsLink) pointer (\(lang)): \(commonText)")

            // Contrast: once a faster AI is available, the same saved setting shows on and enabled.
            #expect(report["24_\(lang)_WITHFAST_FASTCONFIG_PROVIDER"] == "apple")
            #expect(report["24_\(lang)_WITHFAST_TOGGLE_ON"] == "1",
                    "Autocomplete switch should show on once a faster AI is available (\(lang))")
            #expect(report["24_\(lang)_WITHFAST_TOGGLE_ENABLED"] == "1",
                    "Autocomplete switch should be enabled once a faster AI is available (\(lang))")
        }
    }

    /// Item 24 (agreement across surfaces, AGENTS.md rule 1): with a CLI chosen and no faster AI, the input menu's
    /// Autocomplete item must agree with Settings → Common (off and disabled), rather than claiming autocomplete is on.
    @Test func inputMenuAutocompleteAgreesWithSettingsWhenCLIHasNoFasterAI() throws {
        let report = try ReviewUI076AppChild.report.get()
        #expect(report["24_MENU_AUTOCOMPLETE_FOUND"] == "1", "Autocomplete menu item not found")
        #expect(report["24_MENU_AUTOCOMPLETE_ON"] == "0",
                "Input menu Autocomplete item still shows checked with a CLI and no faster AI: \(report["24_MENU_AUTOCOMPLETE_TITLE"] ?? "")")
        #expect(report["24_MENU_AUTOCOMPLETE_ENABLED"] == "0",
                "Input menu Autocomplete item stays enabled with a CLI and no faster AI: \(report["24_MENU_AUTOCOMPLETE_TITLE"] ?? "")")
    }
}
