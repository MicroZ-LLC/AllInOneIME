import Foundation
import Testing

/// Offline wiring checks for review items 21–24. These executable targets cannot be imported by the Mac test target;
/// the checked source is the menu, start guide, installer and Settings view that a user actually reaches.
struct ReviewUI076AcceptanceTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static func between(_ text: String, _ start: String, _ end: String) throws -> String {
        let first = try #require(text.range(of: start), "Missing \(start)")
        let last = try #require(text.range(of: end, range: first.upperBound..<text.endIndex), "Missing \(end)")
        return String(text[first.lowerBound..<last.lowerBound])
    }

    /// Item 21: the menu carries only the output-languages spot; `showPreferences` resolves its page through
    /// `SettingsSpot.page`. This source seam is the menu item's representedObject and its action, not a drawn menu.
    @Test func outputLanguageMenuFollowsItsSettingsSpot() throws {
        let menu = try Self.source("Sources/AllInOneIME/InputMenu.swift")
        let item = try Self.between(menu, "let addOutput =", "outputs.addItem(addOutput)")
        let route = try Self.between(menu, "override func showPreferences(", "@objc func checkForUpdates(")
        let spotOnly = item.contains("addOutput.representedObject = SettingsSpot.outputLanguages.rawValue")
        let dynamicPage = route.contains("spot.page")
        #expect(spotOnly, "The output-language menu still carries a fixed page")
        #expect(dynamicPage, "showPreferences does not resolve the destination from SettingsSpot.page")
    }

    /// Item 22: the start guide shares HostedService's Google availability, has one own-AI entry, and Email is the
    /// default action while Google is unavailable. The step-advance seam is `StartModel.aiReady(_:)`, called by
    /// `StartWindow` with `AIFacts.status` for the selected `Config.ai`, so a ready CLI, key or Apple choice advances.
    @Test func startGuideOffersOnlyAvailableAIChoicesAndAdvancesForTheChosenOne() throws {
        let view = try Self.source("Sources/AllInOneIME/StartView.swift")
        let window = try Self.source("Sources/AllInOneIME/StartWindow.swift")
        let google = try Self.between(view, "Button(tr(\"用 Google 登录\"", "Button(tr(\"用邮箱登录")
        let email = try Self.between(view, "Button(tr(\"用邮箱登录", "if settings.accountBusy")
        let own = try Self.between(view, "Text(tr(\"已经有自己的 AI？", "Spacer(minLength: 0)")
        let googleGated = view.contains("if HostedService.googleEnabled")
        let googleDefault = google.contains(".keyboardShortcut(.defaultAction)")
        let emailDefault = email.contains(".keyboardShortcut(.defaultAction)")
        let ownButtons = own.components(separatedBy: "ownAI(").count - 1
        let readinessCall = window.contains("model.aiReady(")
        let chosenStatus = window.contains("settings.aiFacts.status(settings.config.ai, config: settings.config).isReady")
        #expect(googleGated, "Google sign-in is shown even when the service disables it")
        #expect(!googleDefault, "Unavailable Google sign-in is the default action")
        #expect(emailDefault, "Email sign-in is not the default action")
        #expect(ownButtons == 1, "Three own-AI buttons still open the same provider row")
        #expect(readinessCall, "The guide advances only on hosted account sign-in")
        #expect(chosenStatus, "The guide does not observe readiness of the selected AI")
    }

    /// Item 23: `installed()` must reach `--start` on a fresh install even with the source absent. Step 1's source
    /// seam is `StartModel.inputSourceAdded(_:)`, fed by the enabled-source notification and shown with a Keyboard
    /// Settings button. This checks the route and live observation without opening a window or changing input sources.
    @Test func freshInstallOpensGuideBeforeInputSourceIsAdded() throws {
        let installer = try Self.source("Sources/AllInOneIMEInstaller/main.swift")
        let installed = try Self.between(installer, "func installed()", "/// The last dialog:")
        let view = try Self.source("Sources/AllInOneIME/StartView.swift")
        let window = try Self.source("Sources/AllInOneIME/StartWindow.swift")
        let earlyExit = installed.contains("guard state.enabled && state.listed else")
        let launchesStart = installed.contains("Installer.settingsAppArguments(fresh: self.fresh)")
        let keyboardButton = view.contains("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        let observesAdded = window.contains("kTISNotifyEnabledKeyboardInputSourcesChanged")
        let updatesStep = window.contains("inputSourceAdded(")
        #expect(!earlyExit, "Missing input source exits the installer before its --start launch")
        #expect(launchesStart, "Fresh install no longer launches --start")
        #expect(keyboardButton, "Step 1 has no button that opens Keyboard settings")
        #expect(observesAdded, "Step 1 does not detect when the input source is added")
        #expect(updatesStep, "The enabled-source change does not update Step 1")
    }

    /// Item 24: the provider heading must describe a CLI choice truthfully. With no fast provider, the existing
    /// Settings → AI explanation stays visible and the autocomplete Toggle itself is disabled. The Settings view's
    /// source is the seam for these two UI states; no window or provider probe is needed.
    @Test func cliProviderCopyAndAutocompleteAvailabilityAgreeWithRouting() throws {
        let search = try Self.source("Sources/AllInOneIME/SettingsSearch.swift")
        let settings = try Self.source("Sources/AllInOneIME/SettingsWindow.swift")
        let provider = try Self.between(settings, "SectionTitle(SettingsSpot.provider.title", "// Where `@note` saves")
        let autocomplete = try Self.between(settings, "var autocompleteSection:", "var commandsSection:")
        let genericClaim = search.contains("every AI feature uses it")
        let cliCopy = provider.contains("model.config.ai.agent")
        let settingsLink = autocomplete.contains("Settings → AI")
        let switchDisabled = autocomplete.contains(".disabled(model.fastConfig == nil")
        #expect(!genericClaim, "The provider row still claims every AI feature uses the CLI")
        #expect(cliCopy, "The provider heading does not distinguish a CLI choice")
        #expect(settingsLink, "The existing link to Settings → AI disappeared")
        #expect(switchDisabled, "The autocomplete switch remains usable with no fast provider")
    }
}
