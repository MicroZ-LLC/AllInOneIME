import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMERime
import AppKit
import AVFoundation
import Carbon
import InputMethodKit
import SwiftUI

/// Records what the input method does to a text field. With `selection` set, it behaves like NSTextView:
/// marked or inserted text takes the selection's place when nothing is marked (empty marked text too,
/// which deletes it), and goes where the selection was (`insertionPoint`).
class FakeTextClient: NSObject, IMKTextInput {
    var marked = ""
    var markedSelection = NSRange(location: 0, length: 0)
    var inserted: [String] = []
    var document = ""
    var selection: NSRange?
    /// Inserts that replaced a range of the document (`replacementRange`), as a typo is taken back.
    var replacements = 0
    /// False: like a field that knows no ranges, it tells no caret and reads nothing back.
    var knowsRanges = true
    /// True: like a field that reads back but ignores `replacementRange`, everything goes in at the end.
    var ignoresRanges = false
    /// Empty text with a replacement range never arrives, as through the input method connection (an NSTextView
    /// in the real-app test got none of them).
    var dropsEmptyReplacements = true

    /// Where marked and inserted text goes once selected text was typed over: where it was (nil: at the end).
    var insertionPoint: Int?
    /// `insertionPoint`, or the end of the document.
    private var point: Int { min(insertionPoint ?? .max, (document as NSString).length) }

    private func replaceSelection() {
        guard marked.isEmpty, let range = selection else { return }
        document = (document as NSString).replacingCharacters(in: range, with: "")
        if range.length > 0 { insertionPoint = range.location }
        selection = nil
    }
    /// Screen rect of the caret line, used to position the candidate panel.
    var caretRect = NSRect(x: 420, y: 560, width: 1, height: 18)

    private static func plain(_ value: Any?) -> String {
        if let s = value as? NSAttributedString { return s.string }
        return value as? String ?? ""
    }

    func insertText(_ string: Any!, replacementRange: NSRange) {
        let s = Self.plain(string)
        if s.isEmpty, replacementRange.location != NSNotFound, dropsEmptyReplacements { return }
        if knowsRanges, !ignoresRanges, marked.isEmpty, replacementRange.location != NSNotFound,
           NSMaxRange(replacementRange) <= (document as NSString).length {
            document = (document as NSString).replacingCharacters(in: replacementRange, with: s)
            inserted.append(s)
            replacements += 1
            selection = nil
            return
        }
        replaceSelection()
        inserted.append(s)
        if insertionPoint != nil {
            let at = point
            document = (document as NSString).replacingCharacters(in: NSRange(location: at, length: 0), with: s)
            insertionPoint = at + (s as NSString).length
        } else {
            document += s
        }
        marked = ""
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        replaceSelection()
        marked = Self.plain(string)
        markedSelection = selectionRange
    }

    func selectedRange() -> NSRange {
        guard knowsRanges else { return NSRange(location: NSNotFound, length: NSNotFound) }
        return selection ?? NSRange(location: point, length: 0)
    }

    func markedRange() -> NSRange {
        marked.isEmpty
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: point, length: (marked as NSString).length)
    }

    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        guard knowsRanges, range.location != NSNotFound, NSMaxRange(range) <= (document as NSString).length else { return nil }
        return NSAttributedString(string: (document as NSString).substring(with: range))
    }
    func length() -> Int { (document as NSString).length }

    func characterIndex(
        for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
        inMarkedRange: UnsafeMutablePointer<ObjCBool>!
    ) -> Int { NSNotFound }

    func attributes(
        forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!
    ) -> [AnyHashable: Any]! {
        lineRect?.pointee = caretRect
        return [:]
    }

    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }
    /// Pretend to be another application (nil: this one).
    var bundleIDOverride: String?
    func bundleIdentifier() -> String! { bundleIDOverride ?? Bundle.main.bundleIdentifier ?? "com.aipinyin.selftest" }
    func windowLevel() -> CGWindowLevel { CGWindowLevelForKey(.normalWindow) }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "allinoneime-selftest" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { nil }
    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect { caretRect }
}

/// Records what `@imessage` would send; sends nothing.
final class StandInSender: MessageSender, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [(text: String, to: Recipient)] = []
    private var _error: Error?
    var sent: [(text: String, to: Recipient)] { lock.withLock { _sent } }
    var error: Error? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    func send(_ text: String, to recipient: Recipient) async throws {
        if let error { throw error }
        lock.withLock { _sent.append((text, recipient)) }
    }
}

/// End-to-end check of the input controller without the system text input server.
@MainActor
enum SelfTest {
    static var failures = 0
    /// What the controller under test reads as its settings (the self-test's own config, adjusted per section).
    static var settings: Config = {
        var config = Config.default
        config.claudeInBackground = false  // @agent records a Terminal launch here; nothing starts in the background
        config.setOrder([Language.chinese, .english])  // pinyin first, Shift to English (a new install has English only)
        return config
    }()
    /// Live Bedrock calls with the self-test's own config (`useOwnConfig`), the translation languages English then
    /// Chinese like `settings`: the checks and the README images read English versions.
    static let liveConverter = Converter(loadConfig: {
        var config = try Config.load()
        config.setOrder([OutputLanguage.english, .chinese])
        return config
    })

    /// Counts a check, or, while this Mac can't give the section what it needs (`needing`), reports it skipped.
    static func check(_ condition: Bool, _ message: String) {
        if let skipping {
            print("– \(message) — skipped: \(skipping)")
            skipped[skipping, default: 0] += 1
            return
        }
        print("\(condition ? "✓" : "✗") \(message)")
        if condition { passed += 1 } else { failures += 1 }
        if !needs.isEmpty { checkedWithNeeds += 1 }
    }

    static let keyCodes: [Character: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
        "7": 0x1A, "8": 0x1C, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25,
        "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E, " ": 0x31, ",": 0x2B,
    ]

    static func event(
        _ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code)!
    }

    @discardableResult
    static func press(
        _ controller: AllInOneIMEInputController, _ client: FakeTextClient,
        _ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []
    ) -> Bool {
        controller.handle(event(characters, code: code, flags: flags), client: client)
    }

    static func type(_ text: String, _ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        for ch in text { press(controller, client, String(ch), code: keyCodes[ch] ?? 0) }
    }

    static func space(_ c: AllInOneIMEInputController, _ client: FakeTextClient) -> Bool {
        press(c, client, " ", code: VirtualKey.space)
    }

    /// ⌥Space as a US layout delivers it (it types a no-break space).
    static func optionSpace(_ c: AllInOneIMEInputController, _ client: FakeTextClient) -> Bool {
        press(c, client, "\u{A0}", code: VirtualKey.space, flags: .option)
    }

    /// Left Option pressed and released on its own, as the system reports it (with the device bit).
    static func tapOption(_ c: AllInOneIMEInputController, _ client: FakeTextClient) {
        let down = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | AllInOneIMEInputController.leftOptionBit)
        _ = c.handle(event("", code: VirtualKey.leftOption, flags: down, type: .flagsChanged), client: client)
        _ = c.handle(event("", code: VirtualKey.leftOption, flags: [], type: .flagsChanged), client: client)
    }

    /// Presses the action key the controller is set to.
    @discardableResult
    static func act(_ c: AllInOneIMEInputController, _ client: FakeTextClient) -> Bool {
        switch c.composer.actionKey {
        case .enter: return enter(c, client)
        case .optionSpace: return optionSpace(c, client)
        case .optionTap: tapOption(c, client); return true  // modifier changes always reach the app too
        case .space: return space(c, client)
        case let .shortcut(key):
            var flags: NSEvent.ModifierFlags = []
            if key.modifiers.contains(.shift) { flags.insert(.shift) }
            if key.modifiers.contains(.control) { flags.insert(.control) }
            if key.modifiers.contains(.option) { flags.insert(.option) }
            if key.modifiers.contains(.command) { flags.insert(.command) }
            return press(c, client, "", code: key.keyCode, flags: flags)
        }
    }

    /// ⇧Return: the draft as typed, without AI.
    static func shiftEnter(_ c: AllInOneIMEInputController, _ client: FakeTextClient) -> Bool {
        press(c, client, "\r", code: VirtualKey.returnKey, flags: .shift)
    }

    /// "@i" and Tab: an @improve draft ("@improve "), whose sentence the action key then improves.
    @discardableResult
    static func improve(_ c: AllInOneIMEInputController, _ client: FakeTextClient) -> Bool {
        press(c, client, "@", code: 0x13, flags: .shift)  // ⇧2
        type("i", c, client)
        press(c, client, "\t", code: VirtualKey.tab)
        return client.marked == "improve › "
    }

    /// The hint shown under a draft in `input`, for the current action key and interface language.
    static func draftHint(_ c: AllInOneIMEInputController, input: Language) -> PanelModel.Status {
        let key = c.composer.actionKey
        let how = key != .space ? UIText.name(key) : c.composer.spaceActs ? UIText.name(ActionKey.space) : tr("连按两次空格", "Space twice")
        return .hint("\(how) → " + UIText.action(input: input, config: settings))
    }

    static func enter(_ c: AllInOneIMEInputController, _ client: FakeTextClient) -> Bool {
        press(c, client, "\r", code: VirtualKey.returnKey)
    }

    static func escape(_ c: AllInOneIMEInputController, _ client: FakeTextClient) -> Bool {
        press(c, client, "\u{1B}", code: VirtualKey.escape)
    }

    /// Selected text survives a Shift tap and a field change (nothing of ours is marked, so no empty marked
    /// text is sent, which NSTextView puts in the selection's place); a Shift-click isn't a tap.
    static func testSelectionKept(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        section("Selected text left alone", needs: .composing)
        let (document, inserted) = (client.document, client.inserted)
        defer { (client.document, client.inserted, client.selection, client.insertionPoint) = (document, inserted, nil, nil) }
        let latin = controller.composer.engineState.isAsciiMode
        client.document = "hello world"
        client.selection = NSRange(location: 6, length: 5)
        tapShift(controller, client)
        check(client.document == "hello world" && client.selection != nil, "a Shift tap keeps the selected text (\(client.document))")
        tapShift(controller, client)  // back
        controller.commitComposition(client)
        controller.activateServer(client)
        check(client.document == "hello world" && client.selection != nil, "so does a field change (\(client.document))")
        // Shift held for a click that extends the selection: no switch.
        controller.services.pointerUsedWithin = { _ in true }
        tapShift(controller, client)
        controller.services.pointerUsedWithin = { _ in false }
        check(controller.composer.engineState.isAsciiMode == latin && client.document == "hello world",
              "a Shift-click doesn't switch Chinese and English")
        // Typing still replaces it, as typing over a selection does.
        type("ni", controller, client)
        check(!client.document.contains("world") && client.selection == nil,
              "typing replaces the selection (\(client.document)|\(client.marked))")
        _ = escape(controller, client)
    }

    /// Commands on the selected text (`Composer.selection`). The fake field models a selection as NSTextView does
    /// (marked text would take its place). "@" reads it, and the command is written in the panel: nothing is marked in
    /// the field, which keeps its text and its selection through pinyin, Esc, ⇧⏎, the field left and secure input; a
    /// selection moved meanwhile gives the command up; the setting off, or secure input on, it isn't read (marked as
    /// before). A result picked replaces exactly the selection, by its range, and where the field ignores ranges, as
    /// the selected text (`@js` here; `@improve` live on Bedrock).
    static func testCommandsOnSelection(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        section("commands on the selected text", needs: .composing)
        let (document, inserted, secureBefore) = (client.document, client.inserted, controller.services.secureInputActive)
        defer {
            (client.document, client.inserted, client.selection, client.insertionPoint, client.ignoresRanges) = (document, inserted, nil, nil, false)
            controller.services.secureInputActive = secureBefore
        }
        let text = "Dear team, this sentance have a error. Thanks!"
        let part = "this sentance have a error."
        let range = (text as NSString).range(of: part)
        func select(_ document: String = text, _ selected: NSRange? = nil) {
            controller.commitComposition(client)
            (client.document, client.selection, client.insertionPoint, client.marked) = (document, selected ?? range, nil, "")
        }
        /// The field as it was, its selection still selected, nothing marked.
        func untouched(_ document: String = text, _ selected: NSRange? = nil) -> Bool {
            client.document == document && client.selection == (selected ?? range) && client.marked.isEmpty
        }
        func command(_ letters: String) {
            press(controller, client, "@", code: 0x13, flags: .shift)
            type(letters, controller, client)
            press(controller, client, "\t", code: VirtualKey.tab)
        }
        // The fake field itself: marked text where the selection was, then the text inserted there.
        select()
        client.setMarkedText("x", selectionRange: NSRange(location: 1, length: 0), replacementRange: AllInOneIMEInputController.notFound)
        let markedAt = client.markedRange().location
        client.insertText("y", replacementRange: AllInOneIMEInputController.notFound)
        check(markedAt == range.location && client.document == "Dear team, y Thanks!",
              "the fake field models a selection: marked text takes its place, the text goes in there ('\(client.document)')")

        select()
        command("i")
        let model = controller.panelModel()
        check(controller.composer.draft == "@improve " && controller.composer.draftInPanel && untouched(),
              "\"@improve\" on the selection: nothing marked, the text and its selection untouched ('\(client.document)', marked '\(client.marked)')")
        check(model.inputText == "improve › ▏" && (model.headerText ?? "").contains(part) && (model.headerText ?? "").contains("27"),
              "the panel shows the command as typed, then the selection (\(model.inputText ?? "-") / \(model.headerText ?? "-"))")
        // Pinyin in the command's text: in the panel's input line, its candidates below; Space picks.
        type("nihao", controller, client)
        let pinyin = controller.panelModel()
        check(untouched() && pinyin.inputText?.hasPrefix("improve › ") == true && pinyin.inputText?.contains("ni") == true
              && pinyin.rows.contains { $0.text == "你好" },
              "pinyin is shown in the panel's input line with its candidates, not in the field (\(pinyin.inputText ?? "-"))")
        _ = space(controller, client)
        check(controller.composer.draft == "@improve 你好" && untouched(), "Space picks 你好 into the command (\(controller.composer.draft))")
        _ = escape(controller, client)
        check(untouched() && controller.composer.phase == .idle && !controller.composer.draftInPanel,
              "Esc gives it up: the field and its selection as they were ('\(client.document)')")

        select()
        command("i")
        let insertedBefore = client.inserted.count
        _ = shiftEnter(controller, client)
        check(untouched() && client.inserted.count == insertedBefore, "⇧⏎ inserts nothing: no @improve over the selection")

        select()
        command("i")
        controller.commitComposition(client)
        check(untouched() && client.inserted.count == insertedBefore, "the field left: nothing goes in")
        select()
        command("i")
        controller.perform(controller.composer.commitAsTyped(), client: client)
        check(untouched() && client.inserted.count == insertedBefore, "secure input turning on: nothing goes in")

        // The selection moved meanwhile (a click): the command is given up, and the key acts as usual (pinyin).
        select()
        command("i")
        client.selection = NSRange(location: 0, length: 4)
        type("a", controller, client)
        check(!controller.composer.draftInPanel && controller.composer.draft.isEmpty && client.marked == "a",
              "a selection moved meanwhile gives the command up; the key then types as usual (marked '\(client.marked)')")
        _ = escape(controller, client)

        // Never read during secure input, nor with the setting off: "@" is marked over it as before.
        select()
        controller.services.secureInputActive = { true }
        press(controller, client, "@", code: 0x13, flags: .shift)
        check(controller.composer.selection == nil && client.marked == "@", "not read while secure input is on (marked '\(client.marked)')")
        controller.services.secureInputActive = secureBefore
        _ = escape(controller, client)
        select()
        settings.useSelection = false
        press(controller, client, "@", code: 0x13, flags: .shift)
        check(controller.composer.selection == nil && client.marked == "@", "not read with \"Use the selected text\" off")
        settings.useSelection = true
        _ = escape(controller, client)

        // A result replaces exactly the selection: by its range, and where the field ignores ranges, as the selected text.
        for ignores in [false, true] {
            let sum = "Total: 6*7 apples"
            select(sum, (sum as NSString).range(of: "6*7"))
            client.ignoresRanges = ignores
            let replacementsBefore = client.replacements
            command("js")
            _ = enter(controller, client)
            _ = pump(timeout: 5) { controller.composer.phase == .choosing }
            _ = enter(controller, client)
            check(client.document == "Total: 42 apples" && client.marked.isEmpty
                  && (client.replacements > replacementsBefore) == !ignores,
                  "@js on \"6*7\" selected: 42 replaces it \(ignores ? "where the field ignores ranges" : "by its range") ('\(client.document)')")
            client.ignoresRanges = false
        }

        // @improve on it (live Bedrock): row 0 is the selection; the version picked replaces only it.
        needing([.composing, .bedrock])
        select()
        command("i")
        _ = enter(controller, client)
        if finishConversion(controller, "@improve on the selection") {
            check(controller.composer.choices.first?.text == part && untouched(), "row 0 is the selection; the field still untouched")
            let picked = controller.composer.choices[controller.composer.highlighted].text
            _ = enter(controller, client)
            check(client.document == "Dear team, " + picked + " Thanks!" && picked != part && client.marked.isEmpty,
                  "the version picked replaces the selection, the rest unchanged ('\(client.document)')")
        }
        // Esc in level two goes back to the command, Esc again gives it up: the field as it was.
        select()
        command("i")
        _ = enter(controller, client)
        _ = escape(controller, client)
        check(controller.composer.draft == "@improve " && !controller.composer.isLevelTwo && untouched(),
              "Esc in level two goes back to the command (\(controller.composer.draft))")
        _ = escape(controller, client)
        check(untouched() && controller.composer.phase == .idle, "Esc again: the field and its selection as they were")
        controller.commitComposition(client)
    }

    /// Shift pressed and released on its own.
    static func tapShift(_ c: AllInOneIMEInputController, _ client: FakeTextClient) {
        _ = c.handle(event("", code: VirtualKey.leftShift, flags: .shift, type: .flagsChanged), client: client)
        _ = c.handle(event("", code: VirtualKey.leftShift, flags: [], type: .flagsChanged), client: client)
    }

    static func pump(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { return false }
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
        return true
    }

    /// Settings window, run against a temporary copy of the config (the real file is never written).
    /// Dragging a language chip in the real settings form (offscreen; events posted to this app's own
    /// queue, so the pointer doesn't move): the mouse reaches the chip's drag handle, not the form's
    /// table view, and letting go left of the first chip makes it the default. Nothing is saved.
    /// Switching the interface language redraws the page at once, controls of its own too (the action key
    /// showed 「回车」 in English until the page was opened again).
    static func testLanguageSwitchRedraws(in directory: URL) {
        let pickedBefore = UIText.choice
        defer { UIText.choice = pickedBefore }
        UIText.choice = "zh"
        let model = SettingsModel(configURL: Config.defaultURL, persists: false)
        model.config.actionKey = .enter
        let host = NSHostingView(rootView: SettingsView(model: model, page: .general))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 880, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        _ = pump(timeout: 0.5) { false }
        model.setUILanguage("en")
        _ = pump(timeout: 0.6) { false }
        // The page as drawn now (the accessibility tree is empty offscreen): looked at for the action key's name.
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("settings-switched-to-english.png"))
        }
    }

    /// The settings window names commands with the trigger its settings have, as soon as it changes (`SettingsModel.
    /// triggered`), and its search finds a page by a command typed with it. Nothing is saved.
    static func testCommandTriggerText() {
        let pickedBefore = UIText.choice
        defer { UIText.choice = pickedBefore }
        UIText.choice = "en"
        let model = SettingsModel(configURL: Config.defaultURL, persists: false)
        model.config.commandTrigger = "@"
        let agent = tr("@agent 和 @reply 带上 Chrome 里的网页", "@agent and @reply take the Chrome page along")
        check(model.triggered(agent) == "@agent and @reply take the Chrome page along", "Settings names commands with @: \(model.triggered(agent))")
        model.config.commandTrigger = "~"
        check(model.triggered(agent) == "~agent and ~reply take the Chrome page along"
              && model.triggered(tr("自定义 @ 命令", "Custom @ Commands")) == "Custom ~ Commands",
              "…and with ~ once the trigger is ~: \(model.triggered(agent))")
        check(SettingsPage.agent.matches("~agent", trigger: "~") && SettingsPage.agent.matches("@agent", trigger: "~")
              && !SettingsPage.general.matches("~agent", trigger: "~") && !SettingsPage.agent.matches("~agent"),
              "the search finds ~agent's page with ~ the trigger")
        // The action key's note with the trigger picked in the menu, the process's still the one before (~ → #).
        let triggerBefore = UIText.commandTrigger
        defer { UIText.commandTrigger = triggerBefore }
        UIText.commandTrigger = "~"
        let note = SettingsView.actionKeyNote(.enter, trigger: "#")
        check(note == "Return runs an # command, also on pinyin not yet picked. Without #, Return is a normal Return."
              && SettingsView.actionKeyNote(.enter, trigger: "~").contains("Without ~,"),
              "the action key's note names the trigger the menu has: \(note)")
    }

    /// The candidate layout's picker (Input page) saves as soon as it changes, like the other settings: the input
    /// method reads it from the file when a text field becomes active. On a copy of the config, in `directory`.
    static func testCandidateLayoutSaves(in directory: URL) {
        let url = directory.appendingPathComponent("layout-config.json")
        defer { try? FileManager.default.removeItem(at: url) }
        var config = (try? Config.load()) ?? .default
        config.candidateLayout = .vertical
        try? config.write(to: url)
        let model = SettingsModel(configURL: url)
        let host = NSHostingView(rootView: SettingsView(model: model, page: .input))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 880, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        _ = pump(timeout: 0.5) { false }
        model.config.candidateLayout = .horizontal  // as the segmented control sets it
        let saved = pump(timeout: 2) { (try? Config.load(from: url))?.candidateLayout == .horizontal }
        check(saved, "the candidate layout is saved as soon as it changes (\((try? Config.load(from: url))?.candidateLayout.rawValue ?? "-"))")
        model.config.candidateLayout = .vertical
        let back = pump(timeout: 2) { (try? Config.load(from: url))?.candidateLayout == .vertical }
        check(back, "and back")
    }

    /// Interface text in a language besides Chinese and English: the catalog compiled into the app, and a stand-in app
    /// with a test fr.lproj/Localizable.strings of two entries (as the Makefile compiles the catalog), picked in the
    /// settings: that text in French (the core's too, through the same `InterfaceText.lookup`), what isn't translated in
    /// English, and Chinese for Simplified Chinese.
    static func testInterfaceTranslations(in directory: URL) {
        let english = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        check(english?.path(forResource: "Localizable", ofType: "strings") != nil
              && english.flatMap { InterfaceText.translate("None", key: "account.notSubscribed", in: $0) } == "None",
              "the app carries the compiled String Catalog (en.lproj/Localizable.strings; keys of their own have their English)")
        check(UIText.shipped.map(InterfaceLanguage.name) == ["English", "简体中文"] + interfaceLanguages.map(\.name),
              "the settings offer the shipped languages in their own names (\(UIText.shipped.map(InterfaceLanguage.name)))")

        let stand = directory.appendingPathComponent("interface-translations")
        let fr = stand.appendingPathComponent("fr.lproj")
        try? FileManager.default.removeItem(at: stand)
        try? FileManager.default.createDirectory(at: fr, withIntermediateDirectories: true)
        let table = (try? PropertyListSerialization.data(fromPropertyList: ["Stopped after %@ seconds": "Arrêté au bout de %@ secondes",
                                                                           "Vertical": "Verticale"],
                                                          format: .xml, options: 0)) ?? Data()
        try? table.write(to: fr.appendingPathComponent("Localizable.strings"))
        guard let bundle = Bundle(path: stand.path) else { return check(false, "a stand-in app with fr.lproj") }
        let (appBefore, pickedBefore) = (UIText.app, UIText.choice)
        defer { UIText.app = appBefore; UIText.choice = pickedBefore }
        UIText.app = bundle
        UIText.choice = "fr"
        let n = 12
        check(UIText.shipped.contains("fr") && UIText.language == "fr" && !UIText.chinese,
              "a shipped fr.lproj can be picked (\(UIText.shipped); \(UIText.language))")
        let translated = tr("运行超过 \(n) 秒，已停止", "Stopped after \(n) seconds"), untranslated = tr("打开设置", "Open the settings")
        check(translated == "Arrêté au bout de 12 secondes", "an interface text in French, from fr.lproj: \(translated)")
        check(untranslated == "Open the settings", "one that fr.lproj lacks shows in English: \(untranslated)")
        let core = AIConfig.Text(language: UIText.language).layout(.vertical)
        check(core == "Verticale", "the core's texts go through the same translations as tr: \(core)")
        UIText.choice = "zh"
        let chinese = tr("运行超过 \(n) 秒，已停止", "Stopped after \(n) seconds")
        check(UIText.language == "zh-Hans" && chinese == "运行超过 12 秒，已停止", "Simplified Chinese still comes from the code: \(chinese)")
        UIText.choice = "de"  // not shipped: follows the system
        check(UIText.language == UIText.systemLanguage, "a language that isn't shipped follows the system (\(UIText.language))")
    }

    /// The interface languages the app ships besides Simplified Chinese and English, each with its name in itself, and
    /// some of its text (the catalog's, compiled into `<code>.lproj`): "Interface language" and "General".
    static let interfaceLanguages: [(code: String, name: String, interfaceLanguage: String, general: String)] = [
        ("de", "Deutsch", "Sprache der Benutzeroberfläche", "Allgemein"),
        ("es", "Español", "Idioma de la interfaz", "General"),
        ("fr", "Français", "Langue de l’interface", "Général"),
        ("ja", "日本語", "表示言語", "一般"),
        ("ko", "한국어", "인터페이스 언어", "일반"),
        ("pt-BR", "Português (Brasil)", "Idioma da interface", "Geral"),
        ("zh-Hant", "繁體中文", "介面語言", "一般"),
    ]

    /// Each interface language besides Simplified Chinese and English, picked in the settings: its text from its
    /// `.lproj` (Traditional Chinese's too, never the Simplified Chinese of the code), the core's through the same
    /// lookup, and Settings → General and Translate & Rewrite drawn in it, to build/l10n-shots/<code>/ (next to the app)
    /// to look at: labels that don't fit, text left in English.
    static func testInterfaceLanguages() {
        let shots = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("l10n-shots")
        let pickedBefore = UIText.choice
        defer { UIText.choice = pickedBefore }
        for language in interfaceLanguages {
            UIText.choice = InterfaceLanguage.setting(for: language.code)
            let label = tr("界面语言", "Interface language"), general = SettingsPage.general.title
            // The core's text through the same lookup ("Vertical" is Spanish and Portuguese too: compared with the .lproj).
            let core = AIConfig.Text(language: UIText.language).layout(.vertical)
            let lproj = InterfaceText.bundle(language.code, app: .main).flatMap { InterfaceText.translate("Vertical", in: $0) }
            check(UIText.language == language.code && label == language.interfaceLanguage && general == language.general
                  && lproj != nil && core == lproj && core != "竖排",
                  "\(language.name): picked in the settings, its text from \(language.code).lproj (\(label), \(general), \(core))")
            if language.code == "zh-Hant" {
                let key = UIText.name(ActionKey.optionTap), french = UIText.name(Language.french)
                check(key == "單按 ⌥" && french == "法文" && UIText.chineseOnly("插件库的索引没有签名") == "插件庫的索引沒有簽名",
                      "Traditional Chinese, not the code's Simplified Chinese, where text only comes in Chinese and English (\(key), \(french))")
            }
            let folder = shots.appendingPathComponent(language.code)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for page in [SettingsPage.general, .writing] {
                let preview = SettingsModel(configURL: Config.defaultURL, persists: false)
                preview.profileShownAs = "default"  // never the user's own profile name in a picture
                SettingsImage.render(preview, page: page, to: folder.appendingPathComponent("\(page.rawValue).png")) { seconds in
                    _ = pump(timeout: seconds) { false }
                }
            }
            check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("general.png").path),
                  "\(language.name): Settings → General drawn in it (\(folder.path))")
            // The custom command editor: its "What it does" picker whole, segmented or a menu.
            let editor = folder.appendingPathComponent("command-editor.png")
            renderLight(CommandEditor(edit: CommandEdit(index: nil, command: CustomCommand(name: "sig", type: .snippet, text: "{name?}\n{date}")),
                                      others: []) { _ in true },
                        size: NSSize(width: 560, height: 520), to: editor)
            check(FileManager.default.fileExists(atPath: editor.path), "\(language.name): the custom command editor drawn in it")
        }
    }

    static func testLanguageDrag() {
        var config = (try? Config.load()) ?? .default
        // The translate languages are dragged into order (the input languages are a segmented bar now).
        let japanese = OutputLanguage("ja")
        config.setOrder([OutputLanguage.english, japanese])
        let model = SettingsModel(configURL: Config.defaultURL, persists: false)
        model.config = config
        let host = NSHostingView(rootView: SettingsView(model: model, page: .writing))  // its chips' page
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 880, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        _ = pump(timeout: 0.5) { false }
        defer { window.close() }
        func handles(in view: NSView) -> [NSView] {
            (String(describing: Swift.type(of: view)).contains("HandleView") ? [view] : []) + view.subviews.flatMap(handles)
        }
        // The translate languages' row is the top one: its two handles, left to right.
        let all = handles(in: host).map { ($0, $0.convert($0.bounds, to: nil)) }
        guard let top = all.map(\.1.midY).max() else { return check(false, "language chips have drag handles") }
        let row = all.filter { abs($0.1.midY - top) < 4 }.sorted { $0.1.minX < $1.1.minX }
        guard row.count == 2 else { return check(false, "two translate language chips (\(row.count))") }
        let (second, frame) = row[1]
        let start = NSPoint(x: frame.midX, y: frame.midY)
        let hit = host.superview.flatMap { window.contentView?.hitTest($0.convert(start, from: nil)) }
        check(hit.map { $0 === second || $0.isDescendant(of: second) } == true,
              "a click on a language chip reaches its drag handle (\(hit.map { String(describing: Swift.type(of: $0)) } ?? "nothing"))")
        func mouse(_ type: NSEvent.EventType, x: CGFloat) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: start.y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        let target = row[0].1.minX - 10  // left of the first chip
        for event in [mouse(.leftMouseDragged, x: start.x - 20), mouse(.leftMouseDragged, x: target), mouse(.leftMouseUp, x: target)] {
            if let event { NSApp.postEvent(event, atStart: false) }
        }
        if let down = mouse(.leftMouseDown, x: start.x) { second.mouseDown(with: down) }
        _ = pump(timeout: 1) { model.config.outputLanguages.first == japanese }
        check(model.config.outputLanguages == [japanese, .english],
              "dragging Japanese before English puts it first (\(model.config.outputLanguages.map(\.code)))")
    }

    static func testSettingsWindow(snapshotDirectory: URL) {
        section("settings window")
        let dir = snapshotDirectory.appendingPathComponent("settings-config")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        let own = (try? Config.load()) ?? .default  // the self-test's (`useOwnConfig`)
        try? own.write(to: url)
        let realBefore = try? Data(contentsOf: Config.userURL)

        let model = SettingsModel(configURL: url)
        check(model.canSave && model.config == own, "loads the config")
        // A custom command named like a built-in (a `note` from before @note was built in) is hidden by it: the
        // custom commands list marks it 「和内置命令重名，不会生效，请改名」.
        func custom(_ name: String) -> CustomCommand { CustomCommand(name: name, type: .prompt, prompt: "Reply.") }
        check(["note", "Reminder", "open", "settings"].map(custom).allSatisfy(SettingsView.hiddenByBuiltIn)
              && !["notes", "respond", "remind"].map(custom).contains(where: SettingsView.hiddenByBuiltIn),
              "custom commands a built-in hides are marked in the list, the others aren't")
        check(model.profiles.contains(own.awsProfile), "profile picker lists \(own.awsProfile) (\(model.profiles))")
        needing(.bedrock)
        model.aws.load(profile: model.config.awsProfile)
        check(model.credentialsReady, "credentials found: \(model.credentialStatus)")
        needing([])
        let casual = RewriteStyle.named("口语")!
        let wasOn = model.isStyleOn(casual)
        model.setStyle(casual, on: !wasOn)
        let saved = (try? Config.load(from: url))?.rewriteStyles ?? []
        check(saved.contains("口语") == !wasOn, "toggling 口语 saves at once (\(saved))")
        model.setStyle(casual, on: wasOn)
        let key = model.config.actionKey
        model.config.actionKey = key == .optionSpace ? .space : .optionSpace
        model.save()
        check((try? Config.load(from: url))?.actionKey == model.config.actionKey, "the action key is saved")
        model.config.actionKey = key
        model.save()
        // Changed elsewhere while the window is open (the input method's menu): read again, so the window's
        // next save doesn't put the old value back.
        if var outside = try? Config.load(from: url) {
            outside.improveTranslates.toggle()
            try? outside.write(to: url)
            model.reloadIfChanged()
            model.save()
            check((try? Config.load(from: url))?.improveTranslates == outside.improveTranslates,
                  "a change made elsewhere survives the window's next save")
            outside.improveTranslates.toggle()
            try? outside.write(to: url)
            model.reloadIfChanged()
        }

        // The test button makes a live request with the window's settings.
        needing(.bedrock)
        model.runTest()
        _ = pump(timeout: 20) { model.testStatus != .running }
        if case let .passed(text) = model.testStatus {
            check(true, "测试连接 works: \(text.replacingOccurrences(of: "\n", with: " / "))")
        } else {
            check(false, "测试连接 failed: \(model.testStatus)")
        }
        needing([])

        // Rendered offscreen (nothing appears on screen) for a visual check and the README: the
        // self-test's config, read-only, with a live Test Connection (测试连接) result.
        let list = dir.appendingPathComponent("jargon.txt")
        try? Data("# 我们组的\nbandwidth：精力\nLP\tLeadership Principles\n抓手 - 着力点\n".utf8).write(to: list)
        model.config.jargonFile = list.path
        model.refreshJargon()
        check(model.jargonExists && model.jargonCount == 3, "the user's jargon list is counted (\(model.jargonCount) terms)")
        // The window follows the system language among those the app ships (its .lproj folders): Chinese only when it
        // comes before English, Traditional Chinese in Traditional Chinese, a region in its language.
        let shipped = UIText.shipped
        let picks = [(["en-US", "zh-Hans-US"], "en"), (["zh-Hans-CN", "en-US"], "zh-Hans"), (["zh-Hant-TW", "en"], "zh-Hant"),
                     (["zh-HK"], "zh-Hant"), (["ja-JP", "zh-Hant-TW", "en"], "ja"), (["ko-KR"], "ko"), (["de-AT"], "de"),
                     (["es-MX"], "es"), (["fr-CA"], "fr"), (["pt-BR"], "pt-BR"), (["pt-PT", "en"], "pt-BR"), (["ru-RU"], "en")]
        let wrong = picks.filter { InterfaceLanguage.pick(preferred: $0.0, shipped: shipped) != $0.1 }
        check(shipped == InterfaceLanguage.builtIn + interfaceLanguages.map(\.code).sorted() && wrong.isEmpty,
              "the settings language follows the preferred languages (\(shipped); wrong: \(wrong); this Mac: \(UIText.systemLanguage))")
        // Unless one is picked in the window: it applies at once and is saved.
        let pickedBefore = UIText.choice
        defer { UIText.choice = pickedBefore }
        for picked in ["en", "zh"] {
            model.setUILanguage(picked)
            // The profile's line (keys found, where they are) in that language too.
            check(UIText.chinese == (picked == "zh") && (try? Config.load(from: url))?.uiLanguage == picked
                  && model.credentialsReady == bedrockReady,
                  "界面语言 \(picked): applies at once and is saved (\(model.credentialStatus))")
        }
        model.setUILanguage(nil)
        check(UIText.language == UIText.systemLanguage && (try? Config.load(from: url))?.uiLanguage == nil,
              "界面语言 跟随系统 is saved as null")
        func render(_ name: String, chinese: Bool) {
            UIText.choice = chinese ? "zh" : "en"
            let preview = SettingsModel(configURL: Config.defaultURL, persists: false)
            preview.profileShownAs = "default"  // README images are public: not the user's own profile name
            if !chinese {
                // The English README's: someone who writes English, translating into Spanish, French and German.
                preview.config.setOrder([Language.english])
                preview.config.setOrder(["es", "fr", "de"].map(OutputLanguage.init))
                preview.config.uiLanguage = "en"
            }
            preview.runTest()
            _ = pump(timeout: 20) { preview.testStatus != .running }
            // The AI provider page, with the connection test's result: what the README's setup shows.
            SettingsImage.render(preview, page: .provider, to: snapshotDirectory.appendingPathComponent("\(name).png")) { seconds in
                _ = pump(timeout: seconds) { false }
            }
        }
        render("6-settings", chinese: true)  // README
        render("6-settings-en", chinese: false)  // README (docs/en)
        UIText.choice = pickedBefore
        testLanguageDrag()
        testLanguageSwitchRedraws(in: snapshotDirectory)
        testInterfaceTranslations(in: snapshotDirectory)
        testInterfaceLanguages()
        testCandidateLayoutSaves(in: snapshotDirectory)
        testCommandTriggerText()
        check(SettingsView.version?.isEmpty == false, "the window ends with the version (AllInOneIME \(SettingsView.version ?? "?"))")

        // A config file that doesn't parse is shown as an error and never overwritten.
        try? Data("{ broken".utf8).write(to: url)
        let broken = SettingsModel(configURL: url)
        broken.setStyle(casual, on: true)
        broken.save()
        check(!broken.canSave && broken.loadError != nil
              && (try? String(contentsOf: url, encoding: .utf8)) == "{ broken",
              "a broken config file is reported, not overwritten")
        check((try? Data(contentsOf: Config.userURL)) == realBefore, "the real config file was not touched")
    }

    /// Runs `work` while pumping the main run loop (the self-test is synchronous main-thread code).
    static func runAsync<T>(_ timeout: TimeInterval, _ work: @escaping () async throws -> T) -> T? {
        var result: T?
        var done = false
        Task { @MainActor in
            result = try? await work()
            done = true
        }
        _ = pump(timeout: timeout) { done }
        return result
    }

    /// Waits for a live conversion to finish; returns false (and records a failure) if it failed.
    static func finishConversion(_ controller: AllInOneIMEInputController, _ what: String) -> Bool {
        let started = Date()
        _ = pump(timeout: 20) { if case .translating = controller.composer.phase { return false } else { return true } }
        if case let .failed(message) = controller.composer.phase {
            check(false, "\(what) failed: \(message)")
            return false
        }
        check(controller.composer.phase == .choosing, String(format: "\(what) finished in %.2fs", Date().timeIntervalSince(started)))
        for choice in controller.composer.choices { print("  \(choice.label) \(choice.text)\(choice.kind.isRewrite ? "  [\(choice.kind)]" : "")") }
        return controller.composer.phase == .choosing
    }

    /// Refining the results: @improve a long English sentence, then "shorter" typed in level two and ⇧⏎ asks again with
    /// the results as context; the new versions are shorter, the header names the step, Esc goes back to the results
    /// before it, secure input refuses a refine like any request, and a pick inserts the refined text.
    static func testRefine(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("refine the results: shorter (live Bedrock)", needs: [.composing, .bedrock])
        func versions() -> [String] { controller.composer.choices.filter { $0.kind == .version }.map(\.text) }
        func average(_ lines: [String]) -> Double { lines.isEmpty ? 0 : Double(lines.map(\.count).reduce(0, +)) / Double(lines.count) }
        tapShift(controller, client)  // English: the sentence and the instruction are typed as letters
        improve(controller, client)
        let sentence = "i wanted to let you know that the meeting we planned for tomorrow morning has been moved to "
            + "three in the afternoon because the big room was not available and several people could not join earlier"
        type(sentence, controller, client)
        _ = act(controller, client)
        guard finishConversion(controller, "@improve on a long sentence") else {
            controller.commitComposition(client)
            tapShift(controller, client)
            return
        }
        let before = versions(), beforeResult = controller.composer.result
        type("shorter", controller, client)
        let typing = controller.panelModel()
        check(controller.composer.refineLine == "shorter" && typing.inputText == "修改 › shorter▏" && controller.composer.phase == .choosing,
              "letters start the refine line, the results stay (\(typing.inputText ?? "no line"))")
        check(typing.footer.hasPrefix("⇧⏎ 修改 · ⏎ 上屏"), "the footer says ⇧⏎ refines, ⏎ inserts (\(typing.footer))")
        readmeSnapshot("refine-typing", controller, client, in: snapshotDirectory)  // release notes
        check(shiftEnter(controller, client) && controller.composer.isRefining, "⇧⏎ runs the refine")
        if finishConversion(controller, "refine: shorter") {
            let after = versions()
            check(after.count >= 2 && average(after) < average(before),
                  String(format: "the refined versions are shorter (%.0f → %.0f characters on average)", average(before), average(after)))
            let header = controller.panelModel().headerText ?? ""
            check(header == "已修改：shorter", "the header names the step (\(header))")
            readmeSnapshot("refine", controller, client, in: snapshotDirectory)  // release notes
            check(controller.panelModel().footer.contains("Esc 上一版"), "the footer offers the step back (\(controller.panelModel().footer))")
            // Esc: the results before it, as they were.
            _ = escape(controller, client)
            check(controller.composer.result == beforeResult && controller.composer.refineHistory.isEmpty
                  && controller.composer.phase == .choosing, "Esc goes back to the results before the refine")
            // The same refine again comes from the cache.
            type("shorter", controller, client)
            _ = shiftEnter(controller, client)
            _ = pump(timeout: 2) { controller.composer.phase == .choosing }
            check(controller.composer.phase == .choosing && versions() == after, "the same refine again is answered from the cache")
            // Secure input refuses a refine like any request: the results stay, the instruction comes back.
            controller.services.secureInputActive = { true }
            type("warmer", controller, client)
            _ = shiftEnter(controller, client)
            let refusal = controller.composer.refineError ?? ""
            check(refusal.contains("安全输入") && versions() == after && controller.composer.refineText == "warmer"
                  && controller.panelModel().status == .error(refusal), "secure input refuses the refine (\(refusal))")
            controller.services.secureInputActive = { false }
            _ = escape(controller, client)  // clears the line
            let first = controller.composer.choices[controller.composer.highlighted].text
            _ = press(controller, client, "1", code: 0x12)
            check(client.inserted.last == first && client.marked.isEmpty && !controller.composer.isComposing,
                  "1 inserts the refined version: \(client.inserted.last ?? "")")
        }
        controller.commitComposition(client)
        tapShift(controller, client)  // back to Chinese
        _ = pump(timeout: 3) { controller.panelModel().detail == nil }  // the 中 (Chinese mode) notice
    }

    /// @improve with English typed in English mode → English polish (and English rewrites, incl. jargon,
    /// 黑话); Chinese output; the default input mode.
    static func testEnglishAndOutput(_ controller: AllInOneIMEInputController, _ client: FakeTextClient,
                                     snapshotDirectory: URL) {
        section("English input → English polish + 黑话 (live Bedrock)", needs: [.composing, .bedrock])
        settings.rewriteStyles = ["润色", "简洁", "黑话"]
        let english = settings
        controller.services.converter = Converter(loadConfig: { english })
        tapShift(controller, client)
        let sentence = "this is a blocker bug your team need fix it asap"
        improve(controller, client)
        type(sentence, controller, client)
        check(client.marked == "improve › " + sentence && controller.composer.isLatinDraft,
              "English collects into the @improve draft (\(client.marked))")
        check(space(controller, client) && controller.composer.draft.hasSuffix(" ") && !controller.composer.isLevelTwo,
              "Space after a word is a space")
        check(controller.panelModel().status == draftHint(controller, input: .english),
              "the hint names the action key (\(controller.panelModel().status))")
        snapshot("7a-english-draft", in: snapshotDirectory)
        // ← moves the cursor in the command's text, and the app's caret with it; End back to the end.
        let end = client.markedSelection.location
        for _ in 0..<4 { _ = press(controller, client, "", code: VirtualKey.left) }
        check(client.markedSelection.location == end - 4 && client.marked == "improve › " + sentence + " ",
              "← moves the caret in the command's text (\(client.markedSelection.location) of \(end))")
        _ = press(controller, client, "", code: VirtualKey.end)
        check(client.markedSelection.location == end, "End puts it back at the end")
        check(act(controller, client), "the action key sends it")
        if finishConversion(controller, "English polish") {
            let choices = controller.composer.choices
            let versions = choices.filter { $0.kind == .version }
            check(versions.count == 3 && versions.allSatisfy { !$0.text.containsHan && $0.text.wordingKey != sentence.wordingKey },
                  "3 polished English versions")
            let rewrites = choices.filter { $0.kind.isRewrite }
            check(!rewrites.isEmpty && rewrites.allSatisfy { !$0.text.containsHan }, "rewrites stay in English")
            check(rewrites.contains { $0.kind == .rewrite("黑话") }, "黑话 rewrite present")
            readmeSnapshot("7-english-light", controller, client, in: snapshotDirectory)
            // The user's own jargon list: the jargon (黑话) row notes what the list's terms in it mean.
            let jargonFile = snapshotDirectory.appendingPathComponent("jargon.txt"), jargonBefore = settings.jargonFile
            try? Data("bandwidth：精力、时间\nminor issue：小问题（其实很严重）\n".utf8).write(to: jargonFile)
            settings.jargonFile = jargonFile.path
            if let row = choices.firstIndex(where: { $0.kind == .rewrite(RewriteStyle.jargonName) }) {
                let note = JargonLibrary.annotation(for: choices[row].text, entries: JargonLibrary.load(from: jargonFile))
                let comment = controller.panelModel().rows[row].comment
                check(comment == (note.map { "黑话 · \($0)" } ?? "黑话"), "黑话 row explains the user's terms: \(comment)")
            }
            settings.jargonFile = jargonBefore  // the self-test's (none), never the user's
            try? FileManager.default.removeItem(at: jargonFile)
            _ = space(controller, client)
            check(client.inserted.last == versions.first?.text, "Space inserts the first polished version")
        }
        tapShift(controller, client)

        section("output Chinese (live Bedrock)", needs: [.composing, .bedrock])
        settings.outputLanguage = .chinese
        settings.rewriteStyles = ["简洁", "黑话"]
        let chinese = settings
        controller.services.converter = Converter(loadConfig: { chinese })
        improve(controller, client)
        type("zhegexiangmudejindutaimanle", controller, client)
        _ = space(controller, client)
        let typed = controller.composer.sentText
        check(typed.containsHan, "Chinese sentence confirmed (\(typed))")
        act(controller, client)
        if finishConversion(controller, "Chinese polish") {
            let versions = controller.composer.choices.filter { $0.kind == .version }
            check(versions.count >= 2 && versions.allSatisfy { $0.text.containsHan && $0.text.wordingKey != typed.wordingKey },
                  "versions in Chinese, none just repeating the input (\(versions.count) shown)")
            check(controller.panelModel().rows.count == controller.composer.choices.count, "panel shows every row")
            readmeSnapshot("7b-chinese-output", controller, client, in: snapshotDirectory)
            let highlighted = controller.composer.choices[controller.composer.highlighted].text
            _ = enter(controller, client)
            check(client.inserted.last == highlighted, "Enter inserts the highlighted line (\(highlighted))")
        }
        if controller.composer.isComposing { controller.commitComposition(client) }  // after a failure
        settings.outputLanguage = .english

        section("default input mode", needs: .composing)
        settings.defaultInput = .english
        controller.applySettings()
        check(controller.composer.engineState.isAsciiMode, "changing the default to English switches an idle field")
        tapShift(controller, client)
        controller.applySettings()
        check(!controller.composer.engineState.isAsciiMode, "a Shift toggle sticks until the setting changes again")
        settings.defaultInput = .chinese
        controller.applySettings()
        check(!controller.composer.engineState.isAsciiMode, "default back to Chinese")
    }

    /// Hold the right Option key: audio (synthesized speech played from a file instead of the
    /// microphone) is recognized on the Mac and inserted, or continues an @improve draft.
    static func testVoice(_ controller: AllInOneIMEInputController, _ client: FakeTextClient,
                          snapshotDirectory: URL) {
        section("voice input (on-device recognition of synthesized speech)", needs: .composing)
        guard #available(macOS 26.0, *), VoiceInput.isSupported else {
            print("  SpeechAnalyzer not available on this macOS; skipped")
            return
        }
        settings.rewriteStyles = RewriteStyle.defaultNames
        controller.services.loadSettings = { SelfTest.settings }
        controller.applySettings()
        let voiced = settings
        controller.services.converter = Converter(loadConfig: { voiced })
        for language in [Language.chinese, .english] {
            if runAsync(5, { await VoiceInput.isModelInstalled(language) }) == true {
                check(true, "\(language.displayName) speech model installed")
                continue
            }
            print("  downloading the \(language.displayName) speech model (one time)…")
            var last = -1
            let ok = runAsync(900) {
                try await VoiceInput.downloadModel(language) { p in
                    let percent = Int(p * 100)
                    if percent / 20 > last / 20 { print("    \(percent)%"); last = percent }
                }
                return true
            }
            check(ok == true && runAsync(5, { await VoiceInput.isModelInstalled(language) }) == true,
                  "\(language.displayName) speech model downloaded")
        }

        func speech(_ text: String, voice: String, name: String) -> URL? {
            let url = snapshotDirectory.appendingPathComponent("\(name).aiff")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", voice, "-o", url.path, text]
            guard (try? say.run()) != nil else { return nil }
            say.waitUntilExit()
            return say.terminationStatus == 0 ? url : nil
        }
        var holding = false
        controller.services.isVoiceKeyHeld = { holding }
        defer { controller.services.isVoiceKeyHeld = { NSEvent.modifierFlags.contains(.option) && NSEvent.pressedMouseButtons == 0 } }
        func optionKey(down: Bool) {
            holding = down
            // As the system reports it: the Option flag plus the right-Option device bit.
            let flags = down ? NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue
                                                     | AllInOneIMEInputController.rightOptionBit) : []
            _ = controller.handle(event("", code: VirtualKey.rightOption, flags: flags, type: .flagsChanged), client: client)
        }
        /// Holds the key for the length of the file, then releases it and waits for the transcript.
        /// With `sendWhileHolding`, ⌥Space is pressed before the key is released: the recording stops
        /// and the sentence goes to the model once the transcript is final.
        func dictate(_ url: URL, snapshotName: String? = nil, snapshotAt: Int = 4, sendWhileHolding: Bool = false) -> Bool {
            controller.voiceFile = (url, speed: 1)
            let seconds = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 2
            optionKey(down: true)
            let started = pump(timeout: 1) { if case .listening = controller.composer.voice { return true } else { return false } }
            guard started else {
                check(false, "holding right ⌥ starts listening (\(controller.composer.voice))")
                return false
            }
            var snapped = false
            _ = pump(timeout: seconds + 0.6) {
                if let snapshotName, !snapped, controller.composer.voice.text.count >= snapshotAt {
                    snapped = true
                    readmeSnapshot(snapshotName, controller, client, in: snapshotDirectory)
                }
                return false
            }
            check(!controller.composer.voice.text.isEmpty, "live transcript while listening: \(controller.composer.voice.text)")
            let released = Date()
            if sendWhileHolding {
                check(optionSpace(controller, client) && controller.composer.actsAfterVoice,
                      "⌥Space while holding right ⌥ stops the recording and sends once it's recognized")
            }
            optionKey(down: false)
            let done = pump(timeout: 8) { controller.composer.voice == .off }
            check(done, String(format: "final transcript %.2fs after releasing the key", Date().timeIntervalSince(released)))
            controller.voiceFile = nil
            return done
        }

        guard let chineseAudio = speech("我今天有点不舒服", voice: "Tingting", name: "voice-zh"),
              let englishAudio = speech("This is a blocker bug, your team needs to fix it as soon as possible.",
                                        voice: "Samantha", name: "voice-en")
        else {
            check(false, "could not synthesize test audio with say")
            return
        }
        defer {
            try? FileManager.default.removeItem(at: chineseAudio)
            try? FileManager.default.removeItem(at: englishAudio)
        }

        // A tap is not dictation: released before the hold is confirmed, nothing is recorded.
        controller.voiceFile = (chineseAudio, speed: 1)
        optionKey(down: true)
        optionKey(down: false)
        let tapNotice = controller.panelModel().detail
        _ = pump(timeout: 0.5) { false }  // past the arming delay
        controller.voiceFile = nil
        check(controller.composer.voice == .off && controller.composer.draft.isEmpty && tapNotice == "按住右 ⌥ 说话",
              "a quick tap of right ⌥ records nothing and shows the hint")
        _ = pump(timeout: 3) { controller.panelModel().detail == nil }  // let the hint expire

        // Without a command, what was said goes straight into the text.
        if dictate(chineseAudio) {
            check(client.inserted.last?.wordingKey.contains("不舒服") == true && client.marked.isEmpty
                  && !controller.composer.isComposing, "without a command the transcript is inserted: \(client.inserted.last ?? "")")
        }

        // Chinese mode: Chinese speech continues an @improve draft, the action key translates it.
        needing([.composing, .bedrock])
        improve(controller, client)
        let before = controller.composer.draft
        if dictate(chineseAudio, snapshotName: "8-voice") {
            let draft = controller.composer.draft
            check(draft.hasPrefix(before) && draft.wordingKey.contains("不舒服"), "transcript continues the draft: \(draft)")
            check(client.marked == draft.replacingOccurrences(of: "@improve ", with: "improve › "), "draft shown inline")
            act(controller, client)
            if finishConversion(controller, "voice → translation") {
                check(controller.composer.choices.filter { $0.kind == .version }.count >= 2, "polished versions of the spoken sentence")
            }
        }
        controller.commitComposition(client)

        // English mode with ⌥Space as the action key: English speech continues an English @improve
        // draft; ⌥Space while still holding right ⌥ sends it as soon as it is recognized.
        settings.actionKey = .optionSpace
        controller.applySettings()
        tapShift(controller, client)
        improve(controller, client)
        if dictate(englishAudio, snapshotName: "8-voice-english", snapshotAt: 17, sendWhileHolding: true) {  // README (docs/en)
            let draft = controller.composer.draft
            check(controller.composer.isLatinDraft && draft.lowercased().contains("blocker"), "English transcript: \(draft)")
            if finishConversion(controller, "voice + ⌥Space → English polish") {
                check(controller.composer.choices.filter { $0.kind == .version }.allSatisfy { !$0.text.containsHan },
                      "English versions of the spoken sentence")
            }
        }
        _ = enter(controller, client)
        check(client.marked.isEmpty && !controller.composer.isComposing, "Return inserts the highlighted line")
        tapShift(controller, client)
        settings.actionKey = .enter
        controller.applySettings()
        needing(.composing)

        // An ⌥ shortcut (a key while right ⌥ is down) is not dictation.
        controller.voiceFile = (chineseAudio, speed: 1)
        optionKey(down: true)
        _ = press(controller, client, "∑", code: 0x0D, flags: .option)
        _ = pump(timeout: 0.5) { false }  // past the arming delay
        check(controller.composer.voice == .off, "an ⌥ shortcut doesn't start a recording")
        optionKey(down: false)
        // A key during dictation cancels it.
        optionKey(down: true)
        _ = pump(timeout: 1) { if case .listening = controller.composer.voice { return true } else { return false } }
        _ = escape(controller, client)
        check(controller.composer.voice == .off && client.marked.isEmpty, "Esc while holding right ⌥ cancels the recording")
        optionKey(down: false)
        controller.voiceFile = nil
        controller.commitComposition(client)
    }

    /// @ commands through the controller, with ⏎ as the action key: the palette, @question (live
    /// Bedrock) and ⌘C, @agent (starts nothing here), @open as you type (real Spotlight and folder
    /// listings; nothing is opened), and "@name" mentions.
    static func testCommands(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("@ commands (live Bedrock, Spotlight)", needs: .composing)
        var opened: [String] = [], terminal: [String] = [], copied: [String] = []
        let saved = (openItem: controller.openItem, runInTerminal: controller.services.runInTerminal, copyText: controller.copyText)
        controller.openItem = { opened.append($0) }
        var agentArguments: [[String]] = []
        controller.services.runInTerminal = { agentArguments.append($0); terminal.append($1) }
        controller.services.startAgent = { _ in "selftest" }  // never a real background task
        controller.copyText = { copied.append($0) }
        controller.services.programInstalled = { _ in true }  // @agent runs here even without its agent
        controller.setCommands(Command.catalog(controller.services.loadSettings().customCommands), recheck: true)
        controller.composer.commands = Command.catalog(controller.services.loadSettings().customCommands)
        defer {
            controller.openItem = saved.openItem
            controller.services.runInTerminal = saved.runInTerminal
            controller.copyText = saved.copyText
        }
        func at() { _ = press(controller, client, "@", code: 0x13, flags: .shift) }  // ⇧2
        func copy() { _ = press(controller, client, "c", code: 0x08, flags: .command) }
        func live(_ what: String) -> [SearchResult] {
            _ = pump(timeout: 5) { !controller.composer.currentLiveResults.isEmpty }
            return controller.composer.currentLiveResults
        }
        // Lets a notice from before (the 中 / 英 mode switch, Claude Code opened in Terminal) expire: not in the README images.
        func settle() { _ = pump(timeout: 6) { controller.panelModel().detail == nil } }

        settle()
        at()
        let commands = controller.panelModel().rows.map(\.text)
        check(client.marked == "@" && commands == ["@improve", "@translate", "@question", "@agent", "@open"],
              "@ opens the command palette (\(commands))")
        readmeSnapshot("10-palette", controller, client, in: snapshotDirectory)
        type("q", controller, client)
        _ = enter(controller, client)
        check(client.marked == "question › ", "⏎ picks @question ('\(client.marked)')")
        type("shenmeshiliangzijisuan", controller, client)  // 什么是量子计算: what is quantum computing
        needing([.composing, .bedrock])
        _ = enter(controller, client)  // converts the pinyin and asks
        if finishConversion(controller, "@question") {
            let answer = controller.composer.choices.last
            check(answer?.kind == .answer && answer?.text.containsHan == true && controller.composer.chatRounds.first?.question.hasPrefix("什么") == true,
                  "a Chinese answer to the question: \(answer?.text.prefix(50) ?? "")")
            readmeSnapshot("11-question", controller, client, in: snapshotDirectory)
            copy()
            check(copied == [answer?.text ?? ""] && controller.composer.phase == .choosing, "⌘C copies the answer and keeps it up")
            _ = enter(controller, client)
            check(client.inserted.last == answer?.text && client.marked.isEmpty, "⏎ inserts the answer")
        }
        controller.commitComposition(client)
        needing(.composing)

        at()
        type("ag", controller, client)
        _ = space(controller, client)
        type("bangwoxiegeshellxiaojiaoben", controller, client)  // 帮我写个shell小脚本: write me a small shell script
        let insertedBefore = client.inserted
        _ = enter(controller, client)
        check(terminal.count == 1 && terminal.first?.hasPrefix("帮我写") == true && client.inserted == insertedBefore
              && client.marked.isEmpty && !controller.composer.isComposing,
              "@agent starts a Claude Code session with the text, inserts nothing (\(terminal) | \(controller.panelModel().detail ?? "-"))")
        check(agentArguments.first == ["claude", "--"], "…as `claude -- <text>` (\(agentArguments))")
        // While secure input is on it doesn't start: the text stays in the draft until it is off.
        let secureInput = controller.services.secureInputActive
        controller.services.secureInputActive = { true }
        at()
        type("ag", controller, client)
        _ = space(controller, client)
        type("nihao", controller, client)
        _ = enter(controller, client)
        check(terminal.count == 1 && client.marked == "agent › 你好",
              "@agent doesn't start Claude Code while secure input is on (\(client.marked))")
        controller.services.secureInputActive = secureInput
        _ = enter(controller, client)
        check(terminal.count == 2 && terminal.last == "你好" && client.marked.isEmpty,
              "…and starts it once secure input is off (\(terminal))")
        // Another agent picked in Settings whose program isn't on this Mac: @agent goes with the next key, without the
        // text field becoming active again; picked back, it's there again.
        let installedBefore = controller.services.programInstalled
        controller.services.programInstalled = { $0 == "claude" }
        func nextKey() {
            type("a", controller, client)
            controller.commitComposition(client)
        }
        SelfTest.settings.agent = .gemini
        nextKey()
        let goneForGemini = pump(timeout: 3) { !controller.composer.commands.contains(.agent) }
        SelfTest.settings.agent = .claude
        nextKey()
        let backForClaude = pump(timeout: 3) { controller.composer.commands.contains(.agent) }
        check(goneForGemini && backForClaude, "@agent is offered for the agent picked: not for Gemini CLI missing, again for Claude Code")
        controller.services.programInstalled = installedBefore
        check(TerminalLauncher.shellQuote("it's $HOME `x`") == "'it'\\''s $HOME `x`'", "the prompt is passed as one quoted word")

        settle()
        at()
        type("o", controller, client)
        _ = press(controller, client, "\t", code: VirtualKey.tab)
        check(controller.composer.engineState.isAsciiMode, "@open types letters for names and paths")
        type("calculator", controller, client)
        let found = live("calculator")
        check(found.first?.path == "/System/Applications/Calculator.app",
              "@open shows Calculator as you type (\(found.prefix(3).map(\.path)))")
        let shownAs = controller.panelModel().rows.first?.text
        check(shownAs == "计算器", "…under its Chinese name in a Chinese interface (\(shownAs ?? "-"))")
        // README images are public: the panel shows only what ships with macOS, never the user's own files.
        let shipped = found.filter { $0.path.hasPrefix("/System/Applications/") }
        controller.perform(controller.composer.receiveLive(shipped, for: controller.composer.liveQuery ?? ""), client: client)
        readmeSnapshot("12-open", controller, client, in: snapshotDirectory)
        let userHistory = UserDefaults.standard.data(forKey: OpenHistoryStore.key)  // only read
        _ = enter(controller, client)
        check(opened == ["/System/Applications/Calculator.app"] && client.marked.isEmpty
              && !controller.composer.engineState.isAsciiMode, "⏎ opens it, inserts nothing, and Chinese is back")
        check(controller.services.loadOpenHistory().entries.map(\.path) == ["/System/Applications/Calculator.app"]
              && UserDefaults.standard.data(forKey: OpenHistoryStore.key) == userHistory,
              "…and keeps it in the test's own @open history, not the user's")

        at()
        type("o", controller, client)
        _ = press(controller, client, "\t", code: VirtualKey.tab)
        func typePath(_ path: String) { for ch in path { press(controller, client, String(ch), code: keyCodes[ch] ?? 0x2C) } }
        typePath("/System/Applications/")
        let listed = live("/System/Applications/")
        check(listed.first?.name == "Utilities" && listed.first?.isFolder == true
              && listed.dropFirst().allSatisfy { $0.path.hasSuffix(".app") },
              "a path lists the folder, folders first (\(listed.map(\.name)))")
        readmeSnapshot("12b-open-path", controller, client, in: snapshotDirectory)  // only macOS's own apps in there
        typePath("Util")
        let folders = live("/System/Applications/Util")
        check(folders.first?.name == "Utilities" && folders.first?.isFolder == true, "typing narrows it (\(folders.map(\.name)))")
        _ = press(controller, client, "\t", code: VirtualKey.tab)
        check(controller.composer.draft == "@open /System/Applications/Utilities/", "Tab completes the folder path")
        type("term", controller, client)
        let inside = live("term")
        check(inside.first?.path == "/System/Applications/Utilities/Terminal.app", "and lists what is inside (\(inside.map(\.name)))")
        copy()
        check(copied.last == "/System/Applications/Utilities/Terminal.app", "⌘C copies the path")
        _ = enter(controller, client)
        check(opened.last == "/System/Applications/Utilities/Terminal.app", "⏎ opens it")

        // A web address: "https://…" is only the browser's row; ⏎ opens it there, and it isn't kept in
        // the @open history (what that history ranks are files).
        at()
        type("o", controller, client)
        _ = press(controller, client, "\t", code: VirtualKey.tab)
        typePath("https://example.com")
        let web = live("https://example.com")
        check(web.map(\.path) == ["https://example.com"] && controller.panelModel().rows.first?.comment == "在浏览器中打开",
              "a web address is the only row, to open in the browser (\(web.map(\.path)))")
        _ = enter(controller, client)
        check(opened.last == "https://example.com" && !controller.services.loadOpenHistory().entries.contains { $0.path.hasPrefix("https:") },
              "⏎ opens it in the browser, not kept in the history")

        // Apps by their Chinese names (Spotlight knows them by the system language's only), several keywords
        // across those names too, and Finder and the standard folders by theirs; an app or folder found, so no
        // full-text search adds the user's documents. An English interface shows each as Finder names it (Image
        // Playground, not its bundle's "Playground"). ⌃V puts the Chinese into the draft (a stand-in clipboard).
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let finderApp = "/System/Library/CoreServices/Finder.app", imagePlayground = "/System/Applications/Image Playground.app"
        var byChineseName = [("计算器", "/System/Applications/Calculator.app", "计算器"),
                             ("终端", "/System/Applications/Utilities/Terminal.app", "终端"),
                             ("系统 设置", "/System/Applications/System Settings.app", "系统设置"),
                             ("访达", finderApp, "访达"), ("下载", home + "/Downloads", "下载"), ("桌面", home + "/Desktop", "桌面")]
        if FileManager.default.fileExists(atPath: imagePlayground) { byChineseName.append(("图乐园", imagePlayground, "图乐园")) }
        for (query, app, name) in byChineseName {
            at()
            type("o", controller, client)
            _ = press(controller, client, "\t", code: VirtualKey.tab)
            controller.readClipboard = { .text(query) }
            _ = press(controller, client, "v", code: 0x09, flags: .control)
            _ = pump(timeout: 1) { controller.composer.draft != "@open " }
            let results = live(query)
            let shown = controller.panelModel().rows.first?.text
            settings.uiLanguage = "en"
            controller.applySettings()
            let english = controller.panelModel().rows.first?.text
            settings.uiLanguage = "zh"
            controller.applySettings()
            check(controller.composer.draft == "@open " + query && results.first?.path == app && shown == name
                  && english == FileManager.default.displayName(atPath: app) && !results.contains(where: \.matchedContent),
                  "@open \(query) shows \(shown ?? "nothing") first, \(english ?? "nothing") in English (\(results.count) results)")
            _ = escape(controller, client)
        }
        controller.readClipboard = { .none }
        // Typed in letters, Finder (listed with the apps first), and nothing from Python's folders (compiled
        // files, caches, packages) that is named like it.
        at()
        type("o", controller, client)
        _ = press(controller, client, "\t", code: VirtualKey.tab)
        type("finder", controller, client)
        let finder = live("finder")
        check(finder.contains { $0.path == finderApp } && finder.prefix { $0.path != finderApp }.allSatisfy { $0.path.hasSuffix(".app") }
              && !finder.contains { FileSearchRanking.isNoise($0.path) },
              "@open finder shows Finder, nothing from Python's folders (\(finder.prefix(3).map(\.path)))")
        _ = escape(controller, client)
        // One letter isn't searched as it is typed (most paths have an "a" in them: seconds of Spotlight); ⏎ searches it.
        // The rows after ⏎ are drawn as when typing: a web address opens in the browser, a content match says so.
        let searchFiles = controller.services.searchFiles
        var searched: [String] = []
        let mention = SearchResult(name: "notes.txt", path: "/tmp/notes.txt", matchedContent: true)
        controller.services.searchFiles = { @MainActor query, _ in
            searched.append(query)
            return query == "a" ? [SearchResult.web("example.com")!, mention] : [mention]
        }
        at()
        type("o", controller, client)
        _ = press(controller, client, "\t", code: VirtualKey.tab)
        type("a", controller, client)
        _ = pump(timeout: 0.5) { !searched.isEmpty }
        check(searched.isEmpty && controller.composer.draft == "@open a",
              "@open a: not searched as it is typed ('\(controller.composer.draft)', \(searched))")
        _ = enter(controller, client)
        _ = pump(timeout: 1) { controller.composer.phase == .choosing }
        let listedRows = controller.panelModel().rows.map(\.comment)
        check(searched == ["a"] && listedRows == ["在浏览器中打开", "内容 · /tmp"],
              "…⏎ searches it, its rows drawn as when typing (\(searched), \(listedRows))")
        _ = escape(controller, client)
        _ = escape(controller, client)
        check(client.marked.isEmpty, "Esc twice: back to the draft, then nothing")
        // Only content matches as you type: ⏎ doesn't open the first, it lists them to pick from.
        at()
        type("o", controller, client)
        _ = press(controller, client, "\t", code: VirtualKey.tab)
        type("xyz", controller, client)
        let mentions = live("xyz")
        let liveFooter = controller.panelModel().footer
        _ = enter(controller, client)
        _ = pump(timeout: 1) { controller.composer.phase == .choosing }
        check(mentions == [mention] && liveFooter.hasPrefix("⏎ 列出来选") && opened.last != mention.path
              && controller.composer.choices.map(\.label) == ["1"] && searched.suffix(2) == ["xyz", "xyz"],
              "only content matches: ⏎ lists them to pick from, opens nothing (\(liveFooter))")
        _ = escape(controller, client)
        _ = escape(controller, client)
        controller.services.searchFiles = searchFiles
        check(client.marked.isEmpty, "…Esc twice: nothing left")

        // "@" with a letter no command starts with is a mention: it goes in as typed.
        at()
        type("z", controller, client)
        check(client.inserted.last == "@" && controller.composer.engineState.isComposing, "@z: '@' goes in, z is pinyin")
        _ = escape(controller, client)
        controller.commitComposition(client)
    }

    /// @note and @reminder through the controller, with stand-ins for Notes and Reminders (nothing is
    /// saved or added for real): what they get, the notices, the reminder's row to confirm (read by
    /// the real parser, by the real clock), that secure input doesn't hold them back, and that a text that
    /// couldn't be saved comes back: into the draft, or onto the clipboard when something else is being
    /// typed or its text field is gone.
    static func testNotesAndReminders(_ controller: AllInOneIMEInputController, _ client: FakeTextClient,
                                      snapshotDirectory: URL) {
        section("@note, @reminder (stand-ins for Notes and Reminders)", needs: .composing)
        var notes: [String] = [], reminders: [ReminderDraft] = [], copied: [String] = []
        var failure: Error?
        var held = false  // a save waits while this is set (something is typed meanwhile)
        let saved = (controller.services.noteDestination, controller.services.addReminder, controller.services.parseReminder, controller.services.secureInputActive,
                     controller.readClipboard, controller.copyText)
        // Notes, as the settings have it by default: a stand-in for it.
        controller.services.noteDestination = { _ in
            StandInNotes { text in
                while held { try await Task.sleep(nanoseconds: 10_000_000) }
                if let failure { throw failure }
                notes.append(text)
            }
        }
        controller.services.addReminder = { @MainActor reminder in
            while held { try await Task.sleep(nanoseconds: 10_000_000) }
            if let failure { throw failure }
            reminders.append(reminder)
        }
        controller.copyText = { copied.append($0) }
        // The menu bar panel hears of saves from Notes and Reminders themselves, never from these stand-ins.
        @MainActor final class Tally { var count = 0 }
        let posted = Tally()
        let observers = [Notification.Name.allInOneIMENoteSaved, .allInOneIMEReminderAdded].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { posted.count += 1 }
            }
        }
        defer {
            (controller.services.noteDestination, controller.services.addReminder, controller.services.parseReminder, controller.services.secureInputActive,
             controller.readClipboard, controller.copyText) = saved
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
        func at() { _ = press(controller, client, "@", code: 0x13, flags: .shift) }
        func tab() { _ = press(controller, client, "\t", code: VirtualKey.tab) }
        /// "@n", Tab and `pinyin` typed into `field`.
        func note(_ pinyin: String, in c: AllInOneIMEInputController, _ field: FakeTextClient) {
            _ = press(c, field, "@", code: 0x13, flags: .shift)
            type("n", c, field)
            _ = press(c, field, "\t", code: VirtualKey.tab)
            type(pinyin, c, field)
        }
        func notice() -> String? { controller.panelModel().detail }
        func settle() { _ = pump(timeout: 6) { notice() == nil } }
        let insertedBefore = client.inserted
        // Times with the 24-hour clock: pinned for the README images (`UIText.clock24`; checked below unpinned).
        let clock24 = UIText.clock24 ?? ReminderDraft.systemUses24HourClock
        func clock(_ hour: Int) -> String { ReminderDraft.clock(hour: hour, minute: 0, chinese: true, clock24: clock24) }

        // @note: "@n" offers it, ⏎ saves, nothing goes in.
        settle()
        at()
        type("n", controller, client)
        let offered = controller.panelModel().rows.first
        check(offered?.text == "@note" && offered?.comment == "存一条笔记到备忘录",
              "@n offers @note first (\(offered?.text ?? "-") \(offered?.comment ?? ""))")
        tab()
        type("nihao", controller, client)
        _ = space(controller, client)
        check(client.marked == "note › 你好" && controller.panelModel().status == .hint("⏎ → 存到备忘录"),
              "the hint says ⏎ saves it to Notes (\(controller.panelModel().status))")
        _ = enter(controller, client)
        check(client.marked.isEmpty && client.inserted == insertedBefore && !controller.composer.isComposing
              && notice() == "正在存到备忘录…",
              "⏎ inserts nothing, clears the draft and says 「正在存到备忘录…」 at once (\(notice() ?? "no notice"))")
        check(pump(timeout: 2) { notice() == "已存到备忘录" } && notes == ["你好"],
              "the text goes to Notes, then 「已存到备忘录」 (\(notes), \(notice() ?? "no notice"))")
        // Secure input on (a password field elsewhere) doesn't hold it back: nothing goes to a model.
        controller.services.secureInputActive = { true }
        note("nihao", in: controller, client)
        _ = enter(controller, client)  // converts the pinyin and saves
        check(pump(timeout: 2) { notes.count == 2 } && notes.last == "你好", "…also while secure input is on (\(notes))")
        controller.services.secureInputActive = saved.3
        // ⌃V takes the clipboard's text, its lines too, shown with 「 ↵ 」; ⏎ saves it as it was.
        controller.readClipboard = { .text("牛奶\n鸡蛋\n面包") }
        note("", in: controller, client)
        check(press(controller, client, "v", code: 0x09, flags: .control) && pump(timeout: 1) { client.marked == "note › 牛奶 ↵ 鸡蛋 ↵ 面包" } && notes.count == 2,
              "⌃V in an empty @note shows the clipboard's text in it, a line per 「↵」 (\(client.marked))")
        controller.readClipboard = saved.4
        _ = enter(controller, client)
        check(pump(timeout: 2) { notes.count == 3 } && notes.last == "牛奶\n鸡蛋\n面包",
              "…and ⏎ again saves its three lines (\(notes.last.map { $0.replacingOccurrences(of: "\n", with: "⏎") } ?? "-"))")
        // The note's body is escaped HTML, a line per line, its runs of spaces kept; the text reaches a script
        // as its argument, never as its source, off the main thread; the scripts compile (none is sent to Notes here).
        check(NotesBridge.html("a<b> & \"c\"\n\nd") == "<div>a&lt;b&gt; &amp; &quot;c&quot;</div><div><br></div><div>d</div>"
              && NotesBridge.html("牛奶\r\n鸡蛋  面包") == "<div>牛奶</div><div>鸡蛋&nbsp;&nbsp;面包</div>",
              "the note's body is escaped HTML, a line per line")
        let tricky = "\" & (do shell script \"echo pwned\") & \"\n第二行 \\ <b>"
        let echoed = runAsync(10) {
            try await NotesBridge.run("on run argv\n  return item 1 of argv\nend run", [tricky]) { ($0.stringValue, Thread.isMainThread) }
        }
        check(echoed?.0 == tricky && echoed?.1 == false, "a script gets the text as an argument, off the main thread")
        check(NotesBridge.scripts.allSatisfy { source in
            var error: NSDictionary?
            return NSAppleScript(source: source)?.compileAndReturnError(&error) == true
        }, "the Notes scripts compile")

        // @reminder: read by the real parser, shown to confirm, then added.
        settle()
        at()
        type("r", controller, client)
        let both = controller.panelModel().rows.map(\.text)
        // @read is off for now (`Command.off`): @reply, then @reminder.
        check(both.prefix(2) == ["@reply", "@reminder"] && !both.contains("@read"), "@r offers @reply and @reminder first, not @read (\(both))")
        type("em", controller, client)
        let rows = controller.panelModel().rows
        check(rows.map(\.text) == ["@reminder"] && rows.first?.comment == "加到提醒事项，时间直接写在里面",
              "@rem offers @reminder (\(rows.first?.comment ?? "-"))")
        tab()
        controller.readClipboard = { .text("明天下午3点给张三打电话") }
        check(press(controller, client, "v", code: 0x09, flags: .command)
              && pump(timeout: 1) { client.marked == "reminder › 明天下午3点给张三打电话" },
              "⌘V puts the text in (\(client.marked))")
        controller.readClipboard = saved.4
        check(controller.panelModel().status == .hint("⏎ → 看一下再加到提醒事项"),
              "the hint says it is checked first (\(controller.panelModel().status))")
        _ = enter(controller, client)
        let confirm = controller.panelModel()
        let tomorrowAt3 = "明天 " + clock(15)
        check(controller.composer.phase == .choosing && confirm.rows.map(\.text) == ["给张三打电话"]
              && confirm.rows.first?.comment == tomorrowAt3 && confirm.highlighted == 0,
              "one row to confirm, the time read (\(clock24 ? 24 : 12)-hour clock): "
                + "\(confirm.rows.map { "\($0.text) | \($0.comment)" })")
        check(confirm.footer == "⏎ / 空格 加到提醒事项 · Esc 返回修改 · ⌘C 复制", "footer: \(confirm.footer)")
        readmeSnapshot("13-reminder", controller, client, in: snapshotDirectory)
        _ = press(controller, client, "c", code: 0x08, flags: .command)
        check(copied == ["给张三打电话"] && controller.composer.phase == .choosing, "⌘C copies the title (\(copied))")
        _ = escape(controller, client)
        check(controller.composer.phase == .drafting && client.marked == "reminder › 明天下午3点给张三打电话",
              "Esc goes back to the text (\(client.marked))")
        _ = enter(controller, client)
        _ = enter(controller, client)
        check(notice() == "正在加到提醒事项…", "⏎ says 「正在加到提醒事项…」 at once (\(notice() ?? "no notice"))")
        let calendar = ReminderParser.localCalendar
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        let threePMDate = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: tomorrow)!
        let threePM = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: threePMDate)
        check(pump(timeout: 2) { !reminders.isEmpty }
              && reminders == [ReminderDraft(title: "给张三打电话", due: threePM, hasTime: true, date: threePMDate)]
              && client.marked.isEmpty && !controller.composer.isComposing,
              "⏎ adds it, due tomorrow 15:00 (\(reminders.map { "\($0.title) · \(UIText.when($0))" }))")
        check(pump(timeout: 2) { notice() == "已加到提醒事项：" + tomorrowAt3 }, "notice: \(notice() ?? "none")")
        // The clock override: the README images' 24-hour times on any Mac; unpinned (nil), the Mac's own setting
        // (System Settings → General → Date & Time), as for the user.
        let added = ReminderDraft(title: "给张三打电话", due: threePM, hasTime: true, date: threePMDate)
        let pinnedClock = UIText.clock24
        let shown = [nil, false, true].map { (clock: Bool?) -> String in
            UIText.clock24 = clock
            return UIText.when(added)
        }
        UIText.clock24 = pinnedClock
        check(pinnedClock == true && shown[2] == "明天 15:00" && shown[1] == "明天 下午3:00"
              && shown[0] == (ReminderDraft.systemUses24HourClock ? shown[2] : shown[1]),
              "times: 24-hour when pinned, 12-hour when set so, the Mac's otherwise (this Mac: \(shown[0]))")

        // How the row shows a day, no date and a time that is over (stand-ins for the parser); Space, 1
        // and ⏎ add it; secure input doesn't hold it back.
        func confirmRow(_ reminder: ReminderDraft) -> PanelModel.Row? {
            controller.services.parseReminder = { _ in reminder }
            at()
            type("rem", controller, client)
            tab()
            type("nihao", controller, client)
            _ = enter(controller, client)
            return controller.composer.phase == .choosing ? controller.panelModel().rows.first : nil
        }
        controller.services.secureInputActive = { true }
        let noDate = ReminderDraft(title: "买牛奶")
        check(confirmRow(noDate)?.comment == "未设时间", "no date: 「未设时间」, also while secure input is on")
        controller.services.secureInputActive = saved.3
        _ = press(controller, client, "1", code: 0x12)
        check(pump(timeout: 2) { reminders.count == 2 && notice() == "已加到提醒事项" } && reminders.last == noDate,
              "1 adds it: \(notice() ?? "no notice")")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let yesterday9 = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: yesterday)!
        let over = ReminderDraft(title: "交报告", due: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: yesterday9),
                                 hasTime: true, date: yesterday9)
        let overText = "昨天 \(clock(9)) · 已过"
        check(confirmRow(over)?.comment == overText, "a time that is over: 「已过」 (\(controller.panelModel().rows.first?.comment ?? "-"))")
        _ = space(controller, client)
        check(pump(timeout: 2) { reminders.count == 3 && notice() == "已加到提醒事项：" + overText }, "Space adds it: \(notice() ?? "-")")
        let later = calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: Date()))!
        let day = ReminderDraft(title: "交房租", due: calendar.dateComponents([.year, .month, .day], from: later))
        let dayComment = confirmRow(day)?.comment ?? ""
        check(dayComment.range(of: "^([0-9]+年)?[0-9]+月[0-9]+日 周[一二三四五六日]$", options: .regularExpression) != nil,
              "a day: 「\(dayComment)」")
        _ = enter(controller, client)
        check(pump(timeout: 2) { reminders.count == 4 } && reminders.last == day, "⏎ adds it")
        // Only a time: nothing to be reminded of. ⏎ and Space go back to the text, like Esc (they don't type the
        // time into the app).
        check(confirmRow(ReminderDraft(title: "", due: threePM, hasTime: true)) == nil
              && controller.composer.phase == .failed(Composer.Messages.chinese.reminderWithoutTitle)
              && controller.panelModel().footer == "Esc 返回修改",
              "only a time asks what for (\(controller.composer.phase))")
        _ = enter(controller, client)
        check(controller.composer.phase == .drafting && client.marked == "reminder › 你好" && client.inserted == insertedBefore,
              "⏎ goes back to the text (\(client.marked))")
        _ = enter(controller, client)  // read again: still only a time
        _ = space(controller, client)
        check(controller.composer.phase == .drafting && client.inserted == insertedBefore, "so does Space")
        _ = enter(controller, client)
        _ = escape(controller, client)
        check(controller.composer.phase == .drafting, "and Esc")
        _ = escape(controller, client)

        // What couldn't be saved is never lost. Not allowed to control Notes: the note comes back as the draft it
        // was, the notice says where to allow it (and stays up longer); ⏎ then saves it. Going to System Settings
        // takes the focus, which commits the draft: its text is on the clipboard too, and the notice says so.
        failure = NotesBridge.NotesError.notPermitted
        var copies = copied.count
        note("nihao", in: controller, client)
        _ = enter(controller, client)
        let notAllowed = "没有权限控制「备忘录」：在 系统设置 → 隐私与安全性 → 自动化 里允许 AllInOneIME"
        check(pump(timeout: 2) { client.marked == "note › 你好" && notice() == "原文也复制到了剪贴板。" + notAllowed } && notes.count == 3
              && controller.composer.draft == "@note 你好" && copied.count == copies + 1 && copied.last == "你好",
              "without permission the note comes back into the draft, and onto the clipboard: \(client.marked) | \(notice() ?? "no notice")")
        failure = nil
        _ = enter(controller, client)
        check(pump(timeout: 2) { notes.count == 4 } && notes.last == "你好" && client.marked.isEmpty, "…and ⏎ saves it then")
        // Not allowed to use Reminders: the text it was read from comes back, and goes onto the clipboard.
        failure = RemindersBridge.RemindersError.notPermitted
        copies = copied.count
        _ = confirmRow(day)
        _ = enter(controller, client)
        let remindersNotAllowed = "没有权限使用「提醒事项」：在 系统设置 → 隐私与安全性 → 提醒事项 里允许 AllInOneIME"
        check(pump(timeout: 2) { client.marked == "reminder › 你好" && notice() == "原文也复制到了剪贴板。" + remindersNotAllowed }
              && reminders.count == 4 && copied.count == copies + 1 && copied.last == "你好",
              "without permission the reminder's text comes back, and onto the clipboard: \(client.marked) | \(notice() ?? "-")")
        _ = escape(controller, client)
        // No account for reminders (the Reminders app has to set one up first): the same.
        failure = RemindersBridge.RemindersError.noAccount
        copies = copied.count
        _ = confirmRow(day)
        _ = enter(controller, client)
        let noAccount = "没有能放提醒事项的账户：先打开「提醒事项」App 看看"
        check(pump(timeout: 2) { client.marked == "reminder › 你好" && notice() == "原文也复制到了剪贴板。" + noAccount }
              && reminders.count == 4 && copied.count == copies + 1 && copied.last == "你好",
              "no account: the reminder's text comes back, and onto the clipboard (\(notice() ?? "-"))")
        _ = escape(controller, client)
        // A failure the user can't fix (a script error): back in the draft only.
        failure = NotesBridge.NotesError.failed(number: -1743)
        copies = copied.count
        note("nihao", in: controller, client)
        _ = enter(controller, client)
        check(pump(timeout: 2) { client.marked == "note › 你好" && notice() == "没有存到备忘录（错误 -1743）" } && copied.count == copies,
              "a script error: back in the draft, not on the clipboard (\(notice() ?? "no notice"))")
        _ = escape(controller, client)
        // Something else is being typed when it fails: the text goes to the clipboard, and the notice says so.
        held = true
        failure = NotesBridge.NotesError.failed(number: -1728)
        copies = copied.count
        note("nihao", in: controller, client)
        _ = enter(controller, client)
        type("wo", controller, client)
        held = false
        let onClipboard = "没有存上，原文已复制到剪贴板。没有存到备忘录（错误 -1728）"
        check(pump(timeout: 2) { copied.count == copies + 1 && copied.last == "你好" && notice() == onClipboard } && client.marked == "wo",
              "while something else is typed, it goes to the clipboard: \(notice() ?? "no notice") (typing: \(client.marked))")
        _ = escape(controller, client)
        // Its text field went away meanwhile (IMK closed that controller): the clipboard too, the notice near the
        // pointer, and nothing kept the controller alive.
        held = true
        let otherClient = FakeTextClient()
        var other = AllInOneIMEInputController(server: controller.server(), delegate: nil, client: nil)
        weak let closed = other
        if let field = other {
            field.clientOverride = otherClient
            field.services.loadSettings = { SelfTest.settings }
            field.services.loadCommandUsage = { CommandUsage() }
            field.services.saveCommandUsage = { _ in }
            field.services.secureInputActive = { false }
            field.readClipboard = { .text("买牛奶") }
            field.copyText = { copied.append($0) }
            field.services.noteDestination = controller.services.noteDestination
            field.ensureEngine()
            field.applySettings()
            note("", in: field, otherClient)
            _ = press(field, otherClient, "v", code: 0x09, flags: .control)  // ⌃V: the clipboard's text in
            _ = pump(timeout: 1) { otherClient.marked == "note › 买牛奶" }
            _ = enter(field, otherClient)
            field.inputControllerWillClose()
        }
        other = nil
        held = false
        check(pump(timeout: 2) { copied.last == "买牛奶" && CandidatePanel.shared.view.model.status == .hint(onClipboard) },
              "its text field gone, it goes to the clipboard and the notice shows by itself (\(copied.last ?? "-"))")
        check(closed == nil, "the save kept no controller alive")
        failure = nil
        // A note with line breaks is never typed into the app as it is (in a terminal each line would run as a
        // command): when the app ends the composition, the field loses focus or ⇧⏎ asks for it as typed, its text
        // goes to the clipboard and a notice says the note wasn't saved. In a terminal's field of its own.
        let terminalClient = FakeTextClient()
        terminalClient.bundleIDOverride = "com.mitchellh.ghostty"
        if let terminal = AllInOneIMEInputController(server: controller.server(), delegate: nil, client: nil) {
            let lines = "cd ~/project\nrm -rf build\nmake install"
            terminal.clientOverride = terminalClient
            terminal.services.loadSettings = { SelfTest.settings }
            terminal.services.loadCommandUsage = { CommandUsage() }
            terminal.services.saveCommandUsage = { _ in }
            terminal.services.secureInputActive = { false }
            terminal.readClipboard = { .text(lines) }
            terminal.copyText = { copied.append($0) }
            terminal.services.noteDestination = controller.services.noteDestination
            terminal.services.addReminder = controller.services.addReminder
            terminal.activateServer(terminalClient)
            /// ⌃V in an empty @note: the clipboard's lines in the draft.
            func pending() -> Bool {
                note("", in: terminal, terminalClient)
                _ = press(terminal, terminalClient, "v", code: 0x09, flags: .control)
                return pump(timeout: 1) { terminalClient.marked == "note › cd ~/project ↵ rm -rf build ↵ make install" }
            }
            let unsaved = "笔记还没存，原文已复制到剪贴板"
            func keptOnClipboard(_ how: String, _ end: () -> Void) {
                let before = copied.count
                guard pending() else { return check(false, "\(how): the note's lines didn't come in (\(terminalClient.marked))") }
                end()
                check(terminalClient.inserted.isEmpty && terminalClient.marked.isEmpty && !terminal.composer.isComposing
                      && copied.count == before + 1 && copied.last == lines
                      && terminal.panelModel().detail == unsaved && CandidatePanel.shared.view.model.status == .hint(unsaved),
                      "\(how): the note's lines aren't typed in, its text goes to the clipboard (\(terminalClient.inserted), "
                        + "\(terminal.panelModel().detail ?? "no notice"))")
            }
            keptOnClipboard("the app ends the composition") { terminal.commitComposition(terminalClient) }
            keptOnClipboard("the field loses focus") { terminal.deactivateServer(terminalClient) }
            terminal.activateServer(terminalClient)
            keptOnClipboard("⇧⏎") { _ = shiftEnter(terminal, terminalClient) }
            // ⌘V there is the terminal's: it pastes the clipboard as it is (no note put there first); the note stays.
            let before = copied.count
            if pending() {
                check(!press(terminal, terminalClient, "v", code: 0x09, flags: .command) && copied.count == before
                      && terminalClient.inserted.isEmpty && terminal.composer.draft == "@note " + lines,
                      "⌘V in a terminal is the terminal's; the note stays (\(terminalClient.inserted))")
            }
            _ = escape(terminal, terminalClient)
            terminal.inputControllerWillClose()
        }
        controller.activateServer(client)  // the field being typed in again
        // A slow save (Notes launching, the first permission prompt): 「正在存到备忘录…」 stays up until the outcome
        // replaces it, longer than a notice of its length (about 1.7 s), at most `progressNoticeLimit`.
        held = true
        note("nihao", in: controller, client)
        _ = enter(controller, client)
        _ = pump(timeout: 2.5) { false }
        check(notice() == "正在存到备忘录…", "a slow save: 「正在存到备忘录…」 still up after 2.5 s (\(notice() ?? "no notice"))")
        held = false
        check(pump(timeout: 2) { notes.count == 5 && notice() == "已存到备忘录" }, "…until it is saved (\(notice() ?? "no notice"))")
        let limit = AllInOneIMEInputController.progressNoticeLimit
        AllInOneIMEInputController.progressNoticeLimit = 1
        held = true
        note("nihao", in: controller, client)
        _ = enter(controller, client)
        check(notice() == "正在存到备忘录…" && pump(timeout: 3) { notice() == nil } && notes.count == 5,
              "…for \(Int(limit)) s at most (1 s here)")
        held = false
        AllInOneIMEInputController.progressNoticeLimit = limit
        check(pump(timeout: 2) { notes.count == 6 }, "…and saved after all (\(notes.count) notes)")
        // Told elsewhere when its field lost focus meanwhile (near the pointer here): 「正在存到备忘录…」 goes then too.
        held = true
        note("nihao", in: controller, client)
        _ = enter(controller, client)
        controller.deactivateServer(client)
        held = false
        check(pump(timeout: 2) { notes.count == 7 && CandidatePanel.shared.view.model.status == .hint("已存到备忘录") } && notice() == nil,
              "its field gone, the outcome shows by itself and the progress notice is taken down (\(notice() ?? "none"))")
        controller.activateServer(client)
        _ = pump(timeout: 3) { !CandidatePanel.shared.isShowing }  // the notice near the pointer goes before the next section
        check(posted.count == 0, "the stand-ins post nothing for the menu bar panel (\(posted.count))")
        check(client.inserted == insertedBefore && !controller.composer.isComposing, "@note and @reminder inserted nothing")
        controller.commitComposition(client)
    }

    /// `@imessage` with stand-ins for Contacts and Messages: nothing is read from the address book and
    /// nothing is sent.
    /// `@reportissue`: ⏎ shows what the page will hold (versions, kinds, counts: nothing of the user's), Esc goes back
    /// to the title, ⏎ ⏎ opens GitHub's new-issue page with it (recorded here, never opened); nothing is inserted.
    static func testReportIssue(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("@reportissue (nothing opened)", needs: .composing)
        _ = pump(timeout: 8) { controller.panelModel().detail == nil }  // a notice from before: not in the image
        var opened: [String] = []
        let saved = controller.openItem
        controller.openItem = { opened.append($0) }
        controller.setCommands(Command.catalog([]), recheck: true)
        controller.composer.commands = Command.catalog([])
        controller.composer.setInputMode(.english)
        defer {
            controller.openItem = saved
            controller.commitComposition(client)
            controller.composer.setInputMode(settings.defaultInput)
        }
        let inserted = client.inserted.count
        press(controller, client, "@", code: 0x13, flags: .shift)
        type("reporti", controller, client)
        press(controller, client, "\t", code: VirtualKey.tab)
        type("panel stuck", controller, client)
        check(client.marked == "reportissue › panel stuck", "@reporti Tab picks @reportissue, the title after it (\(client.marked))")
        _ = enter(controller, client)
        let model = controller.panelModel()
        // What it fills in besides the title, as the panel says it (a list under the hint).
        let shown = model.statusText ?? ""
        check(controller.composer.phase == .choosing && opened.isEmpty && model.rows.first?.text == "panel stuck",
              "⏎ shows the issue first, nothing opened (\(model.rows.map(\.text)))")
        check(shown.contains("AllInOneIME: \(AppVersion.string)") && shown.contains("macOS: ") && shown.contains("Input languages: ")
              && shown.contains("Custom commands: "), "the panel lists what goes with it (\(shown.split(separator: "\n").count) lines)")
        check(!shown.contains(NSHomeDirectory()) && (NSUserName().count < 4 || !shown.contains(NSUserName())), "no home folder or user name in it")
        check(shown.contains("Hide sensitive info: on") || shown.contains("Hide sensitive info: off"), "it says whether sensitive info is hidden, nothing more")
        snapshot("report-issue", in: snapshotDirectory)
        _ = escape(controller, client)
        check(client.marked == "reportissue › panel stuck" && opened.isEmpty, "Esc goes back to the title (\(client.marked))")
        _ = enter(controller, client)
        _ = enter(controller, client)
        let url = opened.first ?? ""
        check(opened.count == 1 && url.hasPrefix(IssueReport.newIssueAddress + "?title=panel%20stuck&body=") && url.count <= IssueReport.maxURLLength,
              "⏎ ⏎ opens GitHub's new-issue page with the title (\(url.prefix(90))…, \(url.count) characters)")
        check(client.inserted.count == inserted && client.marked.isEmpty, "nothing is typed into the text field")
    }

    static func testIMessage(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        section("@imessage (stand-in contacts and sender)", needs: .composing)
        let sender = StandInSender()
        var recent: [String] = []
        var contacts: [Contact]? = [Contact(name: "张三", handles: ["+1 555 0100", "zhangsan@example.com"]),
                                    Contact(name: "李四", handles: ["+86 139 0000 2222"])]
        controller.services.loadContacts = { @MainActor in contacts }
        controller.services.messageSender = sender
        controller.services.loadRecentHandles = { recent }
        controller.services.saveRecentHandles = { recent = $0 }
        controller.services.programInstalled = { _ in true }
        controller.setCommands(Command.catalog([]), recheck: true)
        controller.composer.commands = Command.catalog([])
        defer {
            controller.services.loadContacts = { [] }
            controller.services.messageSender = StandInSender()
            controller.services.loadRecentHandles = { [] }
            controller.services.saveRecentHandles = { _ in }
        }
        func at() { _ = press(controller, client, "@", code: 0x13, flags: .shift) }
        func start() {
            at()
            type("ime", controller, client)
            _ = press(controller, client, "\t", code: VirtualKey.tab)
        }
        func found() -> [Recipient] {
            _ = pump(timeout: 3) { !controller.composer.currentRecipients.isEmpty || controller.composer.recipientNote != nil }
            return controller.composer.currentRecipients
        }
        let insertedBefore = client.inserted

        start()
        check(client.marked == "imessage › " && controller.composer.engineState.isAsciiMode, "@imessage: the recipient is typed as letters ('\(client.marked)')")
        type("zs", controller, client)
        let rows = found()
        check(rows.map(\.handle) == ["+1 555 0100", "zhangsan@example.com"]
              && controller.panelModel().rows.first?.text == "张三" && controller.panelModel().rows.first?.comment == "+1 555 0100",
              "zs finds 张三, one row per handle (\(controller.panelModel().rows.map(\.text)))")
        _ = enter(controller, client)
        check(client.marked == "imessage › 张三 › " && !controller.composer.engineState.isAsciiMode && sender.sent.isEmpty,
              "⏎ picks the recipient, Chinese is back, nothing sent ('\(client.marked)')")
        type("nihao", controller, client)
        _ = space(controller, client)
        _ = enter(controller, client)
        let confirm = controller.panelModel()
        check(controller.composer.phase == .choosing && confirm.rows.first?.text == "发给 张三（+1 555 0100）：你好" && sender.sent.isEmpty,
              "⏎ shows the message to confirm (\(confirm.rows.first?.text ?? "-"))")
        _ = space(controller, client)
        check(sender.sent.isEmpty && controller.composer.phase == .choosing, "Space doesn't send it")
        _ = escape(controller, client)
        check(controller.composer.phase == .drafting && client.marked == "imessage › 张三 › 你好", "Esc goes back to editing")
        _ = enter(controller, client)
        _ = enter(controller, client)
        _ = pump(timeout: 3) { !sender.sent.isEmpty && !recent.isEmpty && controller.panelModel().detail != nil }
        check(sender.sent.map(\.text) == ["你好"] && sender.sent.first?.to.handle == "+1 555 0100", "⏎ again sends it (stand-in)")
        check(client.inserted == insertedBefore && client.marked.isEmpty && !controller.composer.isComposing,
              "nothing is inserted, the draft is gone")
        check(recent == ["+1 555 0100"], "the handle is remembered for next time")
        _ = pump(timeout: 6) { controller.panelModel().detail == nil }

        // The recent one comes first with nothing typed.
        start()
        check(found() == [Recipient(name: "张三", handle: "+1 555 0100")], "the recent recipient is offered at once")
        // A number typed in full, without Contacts access.
        contacts = nil
        type("+15550199", controller, client)
        let typed = found()
        check(typed == [Recipient(name: "", handle: "+15550199")]
              && controller.panelModel().status == .hint(tr("没有通讯录权限：系统设置 → 隐私与安全性 → 通讯录 → 打开 AllInOneIME；也可以直接输入手机号或邮箱",
                                                         "No access to Contacts: System Settings → Privacy & Security → Contacts → turn on AllInOneIME; or type a phone number or email")),
              "without Contacts: says so, a typed number still works (\(typed.map(\.handle)))")
        _ = enter(controller, client)
        // Not allowed to control Messages: the notice says where to allow it.
        sender.error = MessageSendError.notPermitted
        type("hi", controller, client)
        _ = space(controller, client)
        _ = enter(controller, client)
        _ = enter(controller, client)
        _ = pump(timeout: 3) { controller.panelModel().detail?.contains("自动化") == true }
        check(controller.panelModel().detail?.contains("自动化") == true && sender.sent.count == 1,
              "-1743: tells how to allow controlling Messages (\(controller.panelModel().detail ?? "-"))")
        sender.error = nil
        _ = pump(timeout: 8) { controller.panelModel().detail == nil }

        // Secure input: not sent.
        contacts = []
        let secureInput = controller.services.secureInputActive
        controller.services.secureInputActive = { true }
        start()
        type("+15550199", controller, client)
        _ = found()
        _ = enter(controller, client)
        type("hi", controller, client)
        _ = space(controller, client)
        _ = enter(controller, client)
        check(controller.composer.phase == .drafting && sender.sent.count == 1, "nothing is sent while secure input is on")
        controller.services.secureInputActive = secureInput
        _ = escape(controller, client)
        controller.commitComposition(client)
        check(client.inserted == insertedBefore, "nothing went into the text field")
    }

    /// The candidates in a row (`candidateLayout`): the panel is a line of cells under the caret, ← → move the
    /// highlight and ↑↓ turn the page; in a column, → stays librime's (the cursor in the pinyin). Nothing is picked,
    /// so nothing is learned.
    static func testHorizontalCandidates(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("candidates in a row", needs: .composing)
        let panel = CandidatePanel.shared
        func arrow(_ code: UInt16) { press(controller, client, "", code: code) }
        type("nihao", controller, client)
        arrow(VirtualKey.right)
        check(controller.composer.engineState.highlighted == 0 && !controller.panelModel().horizontal,
              "in a column, → doesn't move the highlight (highlighted \(controller.composer.engineState.highlighted))")
        let columnSize = panel.view.contentSize
        _ = escape(controller, client)
        settings.candidateLayout = .horizontal
        controller.applySettings()
        defer {
            _ = escape(controller, client)
            settings.candidateLayout = .vertical
            controller.applySettings()
        }
        type("nihao", controller, client)
        let size = panel.view.contentSize
        check(controller.panelModel().horizontal && size.width > size.height && size.height < columnSize.height,
              "the candidates are in a row (\(Int(size.width))×\(Int(size.height)); a column: \(Int(columnSize.width))×\(Int(columnSize.height)))")
        let caretX = client.caretRect.minX, textX = panel.frame.minX + panel.view.textInset
        check(panel.isShowing && abs(textX - caretX) < 1 && panel.frame.maxY <= client.caretRect.minY,
              "under the caret, the first candidate's text at the caret (\(Int(textX)) / \(Int(caretX)))")
        readmeSnapshot("1b-pinyin-horizontal", controller, client, in: snapshotDirectory)
        snapshot("1b-pinyin-horizontal-dark", in: snapshotDirectory, appearance: .darkAqua)
        arrow(VirtualKey.right)
        arrow(VirtualKey.right)
        check(controller.composer.engineState.highlighted == 2, "→ → highlight the third (\(controller.composer.engineState.highlighted))")
        arrow(VirtualKey.left)
        check(controller.composer.engineState.highlighted == 1, "← back to the second (\(controller.composer.engineState.highlighted))")
        let first = controller.composer.engineState.candidates.first?.text
        arrow(VirtualKey.down)
        check(controller.composer.engineState.pageNumber == 1 && controller.composer.engineState.candidates.first?.text != first,
              "↓ turns the page (page \(controller.composer.engineState.pageNumber + 1))")
        arrow(VirtualKey.up)
        check(controller.composer.engineState.pageNumber == 0, "↑ turns it back (page \(controller.composer.engineState.pageNumber + 1))")
        check(client.marked.replacingOccurrences(of: " ", with: "") == "nihao" && client.inserted.last != first,
              "nothing was picked on the way (\(client.marked))")

        // A long candidate is cut with "…", its cell no wider than what's left of it.
        let long = String(repeating: "这是一个很长很长的句子", count: 6)
        let fitted = CandidateView.fitted(NSAttributedString(string: long, attributes: [.font: CandidateView.Fonts.candidate]),
                                          width: CandidateView.Metrics.maxCellTextWidth)
        let width = fitted.size().width
        check(fitted.string.hasSuffix("…") && width <= CandidateView.Metrics.maxCellTextWidth
              && width > CandidateView.Metrics.maxCellTextWidth - CandidateView.Fonts.candidate.pointSize * 2,
              "a long candidate is cut to fit, no gap after the … (\(Int(width)) of \(Int(CandidateView.Metrics.maxCellTextWidth)) pt)")
        panel.show(PanelModel(rows: ["你好", long, "拟好"].enumerated().map {
            PanelModel.Row(label: "\($0.offset + 1)", text: $0.element, kind: .candidate)
        }, highlighted: 1, footer: "空格 选词 · 开头打 @ 用命令", horizontal: true), anchor: client.caretRect)
        snapshot("1c-pinyin-horizontal-long", in: snapshotDirectory)
        // The setting is on the Input page (with the input languages), and the search finds it there.
        check(SettingsPage.input.matches("candidate layout") && SettingsPage.input.matches("横排") && !SettingsPage.general.matches("横排"),
              "searching for the candidate layout finds the Input page, not General")
        // @agent's settings are on a page of their own.
        check(SettingsPage.agent.matches("kiro") && SettingsPage.agent.matches("后台 通知") && SettingsPage.agent.matches("claude tasks")
              && !SettingsPage.general.matches("kiro") && !SettingsPage.general.matches("后台"),
              "searching for the agents or Claude Code's background finds the Agent page, not General")
    }

    /// Height of the content of the outermost scroll view in `view` (what a SwiftUI form scrolls).
    static func scrolledHeight(_ view: NSView) -> CGFloat? {
        if let scroll = view as? NSScrollView, let document = scroll.documentView { return document.frame.height }
        return view.subviews.lazy.compactMap(scrolledHeight).first
    }

    static func snapshot(_ name: String, in directory: URL, appearance: NSAppearance.Name = .aqua) {
        let view = CandidatePanel.shared.view
        view.appearance = NSAppearance(named: appearance)
        view.drawsBackground = true  // nothing behind an offscreen image to blur
        defer {
            view.appearance = nil
            view.drawsBackground = false
        }
        let url = directory.appendingPathComponent("\(name).png")
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil {
            print("  snapshot \(url.path)")
        }
    }

    /// The English README's images (docs/en, `en-*`): what someone who writes English sees, not the
    /// Chinese scenes with the interface in English. English is the only input language, @translate goes
    /// into Spanish, French and German, and the interface is English. Live requests; the settings it
    /// started with come back afterwards.
    static func englishReadmeScenes(_ controller: AllInOneIMEInputController, _ client: FakeTextClient,
                                    in snapshotDirectory: URL) {
        section("the English README's scenes (live Bedrock)", needs: [.composing, .bedrock])
        let (converterBefore, settingsBefore, loadBefore) = (controller.services.converter, settings, controller.services.loadSettings)
        defer {
            controller.commitComposition(client)
            (controller.services.converter, settings, controller.services.loadSettings) = (converterBefore, settingsBefore, loadBefore)
            controller.applySettings()
            controller.composer.setInputMode(settings.defaultInput)
        }
        let languages = ["es", "fr", "de"].map(OutputLanguage.init)
        settings = (try? Config.load()) ?? .default
        (settings.typeOut, settings.typeOutMistakes) = (false, false)  // inserted at once, no typos
        settings.setOrder([Language.english])
        settings.setOrder(languages)
        settings.uiLanguage = "en"
        settings.actionKey = .enter
        controller.services.loadSettings = { SelfTest.settings }
        controller.applySettings()
        controller.services.converter = Converter(loadConfig: {
            var config = try Config.load()
            config.setOrder([Language.english])
            config.setOrder(languages)
            return config
        })
        controller.composer.setInputMode(.english)
        _ = pump(timeout: 6) { controller.panelModel().detail == nil }  // a notice from before isn't in the images
        func shown() -> Bool {
            let model = controller.panelModel()
            return !([model.footer, model.detail ?? ""] + model.rows.map(\.comment)).joined().containsHan
        }

        // @translate: one sentence into each language added.
        press(controller, client, "@", code: 0x13, flags: .shift)
        type("t", controller, client)
        press(controller, client, "\t", code: VirtualKey.tab)
        let late = "running 10 minutes late, start without me"
        type(late, controller, client)
        check(client.marked == "translate › " + late, "English README: an English @translate draft (\(client.marked))")
        snapshot("en-translate-draft", in: snapshotDirectory)
        _ = enter(controller, client)
        if finishConversion(controller, "English README @translate") {
            let lines = controller.composer.choices.filter { if case .translation = $0.kind { return true } else { return false } }
            check(lines.count == 3 && controller.panelModel().rows.allSatisfy { !$0.text.containsHan },
                  "English README: Spanish, French and German lines (\(lines.map(\.text)))")
            snapshot("en-translate", in: snapshotDirectory)
        }
        _ = escape(controller, client)
        _ = escape(controller, client)
        controller.commitComposition(client)

        // @improve: English polished, plus rewrites, in English.
        improve(controller, client)
        let rough = "this is a blocker bug your team need fix it asap"
        type(rough, controller, client)
        snapshot("en-improve-draft", in: snapshotDirectory)
        _ = enter(controller, client)
        if finishConversion(controller, "English README @improve") {
            check(controller.panelModel().rows.allSatisfy { !$0.text.containsHan }, "English README: English polish and rewrites")
            snapshot("en-improve", in: snapshotDirectory)
            snapshot("en-improve-dark", in: snapshotDirectory, appearance: .darkAqua)
        }
        _ = escape(controller, client)
        _ = escape(controller, client)
        controller.commitComposition(client)

        // The command list, then @question asked in English.
        press(controller, client, "@", code: 0x13, flags: .shift)
        snapshot("en-palette", in: snapshotDirectory)
        type("q", controller, client)
        _ = enter(controller, client)
        type("what is quantum computing", controller, client)
        _ = enter(controller, client)
        if finishConversion(controller, "English README @question") {
            let answer = controller.composer.choices.last
            check(answer?.kind == .answer && answer?.text.containsHan == false, "English README: an English answer (\(answer?.text.prefix(50) ?? ""))")
            snapshot("en-question", in: snapshotDirectory)
        }
        _ = escape(controller, client)
        _ = escape(controller, client)
        check(shown(), "English README: an English interface throughout")
    }

    /// A panel the README shows: snapshotted as it is (Chinese interface, docs/), then the same state
    /// with the English interface as `<name>-en` (docs/en), so both show the same results and no
    /// request is made twice.
    static func readmeSnapshot(_ name: String, _ controller: AllInOneIMEInputController, _ client: FakeTextClient,
                               in directory: URL, appearance: NSAppearance.Name = .aqua) {
        snapshot(name, in: directory, appearance: appearance)
        let language = settings.uiLanguage
        settings.uiLanguage = "en"
        controller.applySettings()
        var model = controller.panelModel()
        // A notice still up keeps the words it was shown with; an English interface shows the English ones.
        if let detail = model.detail, let english = englishNotices[detail] { model.detail = english }
        let interface = [model.footer, model.detail ?? ""] + model.rows.map(\.comment)
        check(!interface.joined().containsHan, "\(name)-en: English interface (\(model.footer) | \(model.detail ?? "-"))")
        CandidatePanel.shared.show(model, anchor: client.caretRect)
        snapshot(name + "-en", in: directory, appearance: appearance)
        // The text line above the panel, for the README image (a transcript isn't known beforehand).
        try? Data(client.marked.utf8).write(to: directory.appendingPathComponent("\(name).marked.txt"))
        settings.uiLanguage = language
        controller.applySettings()
        CandidatePanel.shared.show(controller.panelModel(), anchor: client.caretRect)
    }

    /// @py, @js and @search through the controller, with ⏎ as the action key: results come back as
    /// candidates (@py and @js from their child processes), output with several lines goes in as printed
    /// (in a terminal as one line), and @search without a key says where to add one (nothing is sent). The
    /// search key is a stand-in: the user's keychain is never read here.
    /// Typed out with typos fixed on the way (`Config.typeOutMistakes`): the field ends up with exactly the text,
    /// each typo taken back by its range. Esc or another key while a typo is in the field leaves none behind. No
    /// typos in a terminal, nor in a field that tells no caret. Seeded "random" numbers, short pauses.
    static func testTypos(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, clear: () -> Void) {
        let (mistakesBefore, sleepBefore, documentBefore) = (settings.typeOutMistakes, controller.typeOutSleep, client.document)
        settings.typeOutMistakes = true
        controller.applySettings()
        // The apps remembered for not keeping a fix: the self-test's own (the user's stay as they are).
        let memoryBefore = TypoMemory.defaults
        let suite = "com.aipinyin.selftest.typos"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        TypoMemory.defaults = UserDefaults(suiteName: suite) ?? .standard
        defer {
            settings.typeOutMistakes = mistakesBefore
            controller.applySettings()
            (controller.typeOutSleep, controller.typeOutRandom) = (sleepBefore, nil)
            (client.document, client.selection, client.bundleIDOverride, client.knowsRanges, client.ignoresRanges) = (documentBefore, nil, nil, true, false)
            TypoMemory.defaults = memoryBefore
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        let text = "Thanks for the quick reply, I will look into it tomorrow morning and get back to you. "
            + "See https://example.com/docs or write to ops@example.com, order 1042. 好的，明天下午三点见！"
        func seeded(_ seed: UInt64) -> () -> Double {
            var state = seed &* 0x9E37_79B9_7F4A_7C15
            return {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(state >> 11) / Double(UInt64(1) << 53)
            }
        }
        /// Types `text` out after "Re: " in the field; how many typos were taken back.
        func typeOut(_ text: String, until stop: (() -> Bool)? = nil) -> Int {
            (client.document, client.selection, client.replacements) = ("Re: ", nil, 0)
            controller.perform([.typeOut(text)], client: client)
            _ = pump(timeout: 20) { !controller.isTypingOut || stop?() == true }
            return client.replacements
        }
        controller.typeOutSleep = { _ in try? await Task.sleep(nanoseconds: 2_000_000) }
        var fixed: [Int] = []
        var exact = true
        for seed in UInt64(1)...4 {
            controller.typeOutRandom = seeded(seed)
            fixed.append(typeOut(text))
            exact = exact && client.document == "Re: " + text
        }
        check(exact && fixed.reduce(0, +) > 0, "typed out with typos fixed on the way: the text exact (\(fixed) taken back)")

        // A typo in the field when typing stops: taken out first. "Random" 0: one wherever one may be.
        controller.typeOutRandom = { 0.001 }
        controller.typeOutSleep = { _ in try? await Task.sleep(nanoseconds: 30_000_000) }
        let intended = "Re: " + text
        let typo = { !intended.hasPrefix(client.document) }
        let caught = typeOut(text, until: typo) == 0 && typo()
        _ = escape(controller, client)
        check(caught && !controller.isTypingOut && intended.hasPrefix(client.document) && client.document.count > 4,
              "Esc while a typo is in the field takes it out and stops there ('\(client.document)')")
        if typeOut(text, until: typo) == 0, typo() {
            press(controller, client, "a", code: keyCodes["a"] ?? 0)  // the typo out, the rest at once, then the key
            check(!controller.isTypingOut && client.document.hasPrefix(intended),
                  "another key while a typo is in the field: it's taken out and the rest typed (\(client.document.count - intended.count) more)")
            clear()
        } else {
            check(false, "a typo to stop at")
        }

        // The caret moved while a typo is in the field (a click): the typo is taken out where it was typed, the
        // rest typed plainly; every character there once.
        if typeOut(text, until: typo) == 0, typo() {
            client.selection = NSRange(location: 4, length: 0)
            _ = pump(timeout: 20) { !controller.isTypingOut }
            check(client.document.sorted() == intended.sorted() && client.replacements > 0,
                  "the caret moved while a typo is in the field: it's taken out, every character there once ('\(client.document)')")
        } else {
            check(false, "a typo to move the caret at")
        }

        // A field that reads back but ignores replacement ranges: the typo can't be taken back, so it stays (one
        // character off at most, nothing more added), and its app is remembered: no typos there the next time.
        controller.typeOutSleep = { _ in try? await Task.sleep(nanoseconds: 1_000_000) }
        (client.bundleIDOverride, client.ignoresRanges) = ("com.example.ignores-ranges", true)
        controller.typeOutRandom = seeded(1)
        _ = typeOut(text)
        let firstRun = client.document
        let remembered = TypoMemory.contains( "com.example.ignores-ranges")
        check(oneEditApart(firstRun, intended) && remembered && !TypoMemory.remember(""),
              "a field ignoring replacement ranges: one typo stays at most, its app remembered (\(remembered)): '\(firstRun)'")
        _ = typeOut(text)
        check(client.document == intended, "…the next time, no typos there: the text exact")
        TypoMemory.forget()
        check(TypoMemory.apps.isEmpty, "…until forgotten (Settings → General); never an app without a bundle identifier")
        (client.bundleIDOverride, client.ignoresRanges) = (nil, false)

        // No typos where they couldn't be taken back.
        client.bundleIDOverride = "com.mitchellh.ghostty"
        let inTerminal = typeOut(text)
        check(inTerminal == 0 && client.document == intended, "no typos in a terminal (\(inTerminal) taken back)")
        client.bundleIDOverride = nil
        client.knowsRanges = false
        let noRanges = typeOut(text)
        check(noRanges == 0 && client.document == intended, "no typos in a field that tells no caret (\(noRanges) taken back)")
    }

    /// Whether `a` and `b` are the same, or one character substituted, added or left out.
    static func oneEditApart(_ a: String, _ b: String) -> Bool {
        let (x, y) = (Array(a), Array(b))
        if x == y { return true }
        let prefix = zip(x, y).prefix { $0 == $1 }.count
        let suffix = zip(x.reversed(), y.reversed()).prefix { $0 == $1 }.count
        return max(x.count, y.count) - min(prefix + suffix, min(x.count, y.count)) <= 1
    }

    /// An answer with line breaks (code) in a terminal: they go in as a paste, which the shell or Claude Code
    /// takes as text, not as Return; typed out, the characters are typed and each line break pasted. Without
    /// that (no Accessibility permission) on one line. A live @question; the paste is recorded here.
    static func testAnswerLinesInTerminal(_ controller: AllInOneIMEInputController, _ client: FakeTextClient,
                                          start: (String) -> Bool, typeText: (String) -> Void, clear: () -> Void) {
        var pasted: [String] = []
        controller.canPasteInTerminal = { true }
        controller.pasteInTerminal = { pasted.append($0) }
        defer {
            controller.canPasteInTerminal = { false }
            controller.pasteInTerminal = { _ in }
        }
        func ask() -> String? {
            guard start("question") else { check(false, "@question is picked from the list ('\(client.marked)')"); return nil }
            typeText("yongpythonxiekuaisupaixu")  // 用 python 写快速排序: code, several lines
            _ = act(controller, client)
            guard finishConversion(controller, "@question in a terminal") else { clear(); return nil }
            return controller.composer.choices.first { $0.kind == .answer }?.text
        }
        let before = client.inserted
        if let answer = ask() {
            _ = enter(controller, client)
            _ = pump(timeout: 1) { !pasted.isEmpty }
            check(answer.contains("\n") && pasted == [answer] && client.inserted == before,
                  "an answer with line breaks goes into a terminal as a paste (\(pasted.map { $0.replacingOccurrences(of: "\n", with: "\\n") }))")
        }
        // Typed out: characters typed, line breaks pasted one at a time.
        settings.typeOut = true
        controller.applySettings()
        let sleep = controller.typeOutSleep
        controller.typeOutSleep = { _ in try? await Task.sleep(nanoseconds: 5_000_000) }
        (pasted, client.inserted) = ([], [])
        if let answer = ask() {
            _ = enter(controller, client)
            _ = pump(timeout: 10) { !controller.isTypingOut }
            let breaks = answer.filter { $0 == "\n" }.count
            check(breaks > 0 && pasted == Array(repeating: "\n", count: breaks)
                  && client.inserted.allSatisfy { $0.count == 1 && $0 != "\n" }
                  && client.inserted.joined() == answer.replacingOccurrences(of: "\n", with: ""),
                  "…typed out: the characters typed, each of the \(breaks) line breaks pasted (\(pasted.count) pastes)")
        }
        settings.typeOut = false
        controller.applySettings()
        controller.typeOutSleep = sleep
        client.inserted = before
        clear()
    }

    static func testToolCommands(_ controller: AllInOneIMEInputController, _ client: FakeTextClient,
                                 snapshotDirectory: URL) {
        section("@py, @js, @search", needs: .composing)
        // These commands run nothing while secure input is on, and a locked screen holds it. Nothing typed
        // here is secret, and the secure input refusal has its own checks, so this section runs without it.
        let (secureInput, installed, commands, searchKey) =
            (controller.services.secureInputActive, controller.services.programInstalled, controller.composer.commands, controller.services.loadSearchKey)
        controller.services.secureInputActive = { false }
        controller.services.programInstalled = { CommandRunner.isInstalled($0, path: ShellEnvironment.current["PATH"]) }
        controller.services.loadSearchKey = { nil }
        defer {
            controller.services.secureInputActive = secureInput
            controller.services.programInstalled = installed
            controller.services.loadSearchKey = searchKey
            controller.setCommands(commands)
        }
        // Only the built-in commands, so the user's own can't come first in the list.
        controller.setCommands(Command.catalog([]), recheck: true)
        let python = CommandRunner.isInstalled("python3", path: ShellEnvironment.current["PATH"])
        check(pump(timeout: 10) { controller.composer.commands.contains(.py) == python },
              "@py is offered only with python3 installed (python3: \(python))")
        // A check of the programs that ends while a command is being written applies once that's done.
        controller.services.programInstalled = { $0 != Command.py.program }
        press(controller, client, "@", code: 0x13, flags: .shift)  // composing: the list is up
        controller.setCommands(Command.catalog([]), recheck: true)
        _ = pump(timeout: 1) { false }  // the check runs in the background meanwhile
        let keptWhileComposing = controller.composer.commands.contains(.py) == python
        _ = escape(controller, client)
        press(controller, client, "@", code: 0x13, flags: .shift)  // the next key outside a command applies it
        check(keptWhileComposing && !controller.composer.commands.contains(.py),
              "a program check that ended while a command was written hides @py once it's done")
        _ = escape(controller, client)
        controller.services.programInstalled = { CommandRunner.isInstalled($0, path: ShellEnvironment.current["PATH"]) }
        controller.setCommands(Command.catalog([]), recheck: true)
        _ = pump(timeout: 10) { controller.composer.commands.contains(.py) == python }

        // Symbols with their US-layout keys (`type` sends key code 0 for anything not in `keyCodes`).
        let symbols: [Character: (UInt16, NSEvent.ModifierFlags)] = [
            "*": (0x1C, .shift), "/": (0x2C, []), "+": (0x18, .shift), ".": (0x2F, []),
            "(": (0x19, .shift), ")": (0x1D, .shift), ";": (0x29, []),
        ]
        func start(_ name: String) -> Bool {
            press(controller, client, "@", code: 0x13, flags: .shift)  // ⇧2
            type(name, controller, client)
            press(controller, client, "\t", code: VirtualKey.tab)
            return client.marked == name + " › "
        }
        func typeText(_ text: String) {
            for ch in text {
                let (code, flags) = symbols[ch] ?? (keyCodes[ch] ?? 0, [])
                press(controller, client, String(ch), code: code, flags: flags)
            }
        }
        func waitForEnd() {
            _ = pump(timeout: 20) { if case .translating = controller.composer.phase { return false } else { return true } }
        }
        func failure() -> String? {
            if case let .failed(message) = controller.composer.phase { return message } else { return nil }
        }
        func clear() {
            for _ in 0..<4 where controller.composer.isComposing { _ = escape(controller, client) }
        }
        /// Runs `@name text` and inserts its result; true if `expected` was inserted.
        func insertsResult(_ name: String, _ text: String, _ expected: String) -> Bool {
            guard start(name) else {
                check(false, "@\(name) is picked from the list ('\(client.marked)')")
                return false
            }
            typeText(text)
            _ = act(controller, client)
            guard finishConversion(controller, "@\(name) \(text)") else { clear(); return false }
            let answer = controller.composer.choices.last
            _ = enter(controller, client)
            return answer?.kind == .answer && answer?.text == expected && client.inserted.last == expected
                && client.marked.isEmpty && !controller.composer.isComposing
        }

        // Typed out (`Config.typeOut`): the result goes in one character at a time; Esc stops it there,
        // another key types the rest at once. Short pauses here.
        let (typedBefore, mistakesBefore, sleepBefore) = (settings.typeOut, settings.typeOutMistakes, controller.typeOutSleep)
        (settings.typeOut, settings.typeOutMistakes) = (true, false)  // one character at a time, no typos (`testTypos` has those)
        controller.applySettings()
        controller.typeOutSleep = { _ in try? await Task.sleep(nanoseconds: 40_000_000) }
        func typedOut(_ text: String) -> Bool {
            guard start("js") else { return false }
            typeText(text)
            _ = act(controller, client)
            guard finishConversion(controller, "@js \(text)") else { clear(); return false }
            let before = client.inserted.count
            _ = enter(controller, client)
            return client.inserted.count == before && controller.isTypingOut  // nothing at once: it's being typed
        }
        var before = client.inserted.count
        if typedOut("2**40") {  // 1099511627776
            _ = pump(timeout: 3) { !controller.isTypingOut }
            let typed = Array(client.inserted.dropFirst(before))
            check(typed.joined() == "1099511627776" && typed.allSatisfy { $0.count == 1 },
                  "the result is typed out one character at a time (\(typed.count) inserts)")
        } else {
            check(false, "the result starts typing out instead of going in at once")
        }
        before = client.inserted.count
        if typedOut("2**40") {
            _ = pump(timeout: 0.2) { client.inserted.count >= before + 2 }
            _ = escape(controller, client)
            _ = pump(timeout: 0.3) { false }
            let typed = client.inserted.dropFirst(before).joined()
            check(!controller.isTypingOut && !typed.isEmpty && typed.count < 13 && "1099511627776".hasPrefix(typed),
                  "Esc stops it there (\(typed))")
        }
        before = client.inserted.count
        if typedOut("2**40") {
            _ = pump(timeout: 0.2) { client.inserted.count >= before + 2 }
            press(controller, client, "a", code: keyCodes["a"] ?? 0)  // another key: the rest at once, then the key
            let typed = client.inserted.dropFirst(before).joined()
            check(!controller.isTypingOut && typed.hasPrefix("1099511627776"), "another key types the rest at once (\(typed))")
            clear()
        }
        testTypos(controller, client, clear: clear)
        (settings.typeOut, settings.typeOutMistakes) = (typedBefore, mistakesBefore)
        controller.applySettings()
        controller.typeOutSleep = sleepBefore

        if python {
            check(insertsResult("py", "2**100", "1267650600228229401496703205376"),
                  "@py 2**100 inserts the value from python3 (\(client.inserted.last ?? ""))")
            if start("py") {
                typeText("1/0")
                _ = act(controller, client)
                waitForEnd()
                check(failure()?.contains("ZeroDivisionError") == true, "@py shows Python's error (\(failure() ?? "no error"))")
            }
            clear()
        }
        check(insertsResult("js", "6*7", "42"), "@js 6*7 inserts 42 from the JavaScriptCore child process (\(client.inserted.last ?? ""))")

        // Output with several lines: inserted as printed, except in a terminal, which would run all but the
        // last line. (Terminals refuse composing while secure input is on, so that check needs it off.)
        func shown(_ text: String?) -> String { (text ?? "").replacingOccurrences(of: "\n", with: "\\n") }
        if python {
            check(insertsResult("py", "print(1);print(2)", "1\n2"), "@py output keeps its lines in other apps (\(shown(client.inserted.last)))")
            if SecureInput.ownerPID() == nil {
                client.bundleIDOverride = "com.mitchellh.ghostty"
                controller.activateServer(client)
                check(insertsResult("py", "print(1);print(2)", "1 2"),
                      "…and goes in as one line in a terminal (\(shown(client.inserted.last)))")
                let local = needing([.composing, .bedrock])  // a live @question
                testAnswerLinesInTerminal(controller, client, start: start, typeText: typeText, clear: clear)
                needing(local)
                client.bundleIDOverride = nil
                controller.activateServer(client)
            } else {
                print("  secure input is on (\(SecureInput.ownerDescription())): no terminal check")
            }
        }

        testExtensions(controller, client, start: start, typeText: typeText, waitForEnd: waitForEnd, clear: clear)

        // Without a key nothing is sent: the error says where to add one. (No live search here.) @search is
        // off for now (`Command.webSearchOffered`): then it isn't in the list at all.
        if !Command.webSearchOffered {
            press(controller, client, "@", code: 0x13, flags: .shift)
            type("sea", controller, client)
            check(!controller.composer.paletteMatches.contains(.webSearch), "@search isn't offered (off for now)")
            clear()
        } else if start("search") {
            type("pingguo", controller, client)  // 苹果: apple
            _ = act(controller, client)
            waitForEnd()
            let expected = UIText.describe(WebSearch.SearchError.missingKey(variable: WebSearch.backend.keyVariables[0]))
            check(failure() == expected, "@search without a key says where to add one (\(failure() ?? "no error"))")
        } else {
            check(false, "@search is picked from the list ('\(client.marked)')")
        }
        clear()
        check(!controller.composer.isComposing && client.marked.isEmpty, "nothing left composing")
    }

    /// Script extensions, made in a temporary folder (never the user's own): one that takes no input completes
    /// on Tab and runs on the action key, its line goes in; a Raycast silent one inserts nothing; a missing
    /// argument runs nothing; a list as you type, its row picked; a bundle's preference and the language reach
    /// the script; a background one notifies when it's done.
    static func testExtensions(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, start: (String) -> Bool,
                               typeText: (String) -> Void, waitForEnd: () -> Void, clear: () -> Void) {
        section("script extensions (a temporary folder)", needs: .composing)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-selftest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("stbundle"), withIntermediateDirectories: true)
        let (loadExtensions, notify, ask) = (controller.services.loadExtensions, controller.scriptTasks.notify, controller.scriptTasks.askToNotify)
        // Preferences that take a while to read (as the keychain may): a key never waits for them.
        let preferences = controller.services.extensionPreferences
        controller.services.extensionPreferences = { bundle, _ in
            Thread.sleep(forTimeInterval: 0.3)
            return bundle.values([:])
        }
        var notified: [String] = []
        controller.scriptTasks.notify = { _, title, body in notified.append(title + " | " + body) }
        controller.scriptTasks.askToNotify = {}
        defer {
            try? FileManager.default.removeItem(at: folder)
            controller.services.loadExtensions = loadExtensions
            controller.scriptTasks.notify = notify
            controller.scriptTasks.askToNotify = ask
            controller.services.extensionPreferences = preferences
            controller.composer.setInputMode(settings.defaultInput)
        }
        func add(_ name: String, _ prefix: String, _ metadata: [String], _ body: String) {
            let text = (["#!/bin/bash", "# @\(prefix).schemaVersion 1"] + metadata.map { "# @\(prefix)." + $0 } + [body]).joined(separator: "\n")
            let file = folder.appendingPathComponent(name)
            try? Data(text.utf8).write(to: file)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        add("sthello.sh", "allinoneime", ["title Self-test Hello", "input none"], #"echo working; echo "hello from $(basename "$PWD") in $ALLINONEIME_LANGUAGE""#)
        add("stquiet.sh", "raycast", ["title Self-test Quiet", "mode silent"], "echo quiet")
        add("stneeds.sh", "allinoneime", ["title Self-test Needs", #"argument1 {"type": "text", "placeholder": "city"}"#], #"echo "$1""#)
        add("stlist.sh", "allinoneime", ["title Self-test List", "output list", "queryDelay 10"],
            #"printf '{"items": [{"title": "first %s", "arg": "picked-%s"}, {"title": "info", "valid": false}]}' "$1" "$1""#)
        add("stwait.sh", "allinoneime", ["title Self-test Wait", "input none", "background true"], #"sleep 0.3; echo '{"summary": "waited", "detail": "0.3 s"}'"#)
        add("stbundle/greet.sh", "allinoneime", [], #"echo "$ALLINONEIME_PREF_GREETING, $1""#)
        let manifest = #"{"schemaVersion": 1, "name": "stbundle", "title": "Self-test Bundle", "version": "1.0", "#
            + #""preferences": [{"name": "greeting", "type": "textfield", "title": "Greeting", "default": "hi"}], "#
            + #""commands": [{"script": "greet.sh", "name": "stgreet", "title": "Self-test Greet", "input": "optional"}]}"#
        try? Data(manifest.utf8).write(to: folder.appendingPathComponent("stbundle/extension.json"))
        var index = ExtensionStore.load([.init(path: folder.path, found: false)])
        index.generation = 1_000_000  // another than the empty one's: the command list is built again for it
        check(index.commands.map(\.name) == ["stgreet", "sthello", "stlist", "stneeds", "stwait", "stquiet"] && index.skipped.isEmpty,
              "extensions read from a folder: the bundle's first, Raycast's last (\(index.commands.map(\.name)), \(index.skipped.count) skipped)")
        // A copy of the folder found by Spotlight (another checkout): only its Raycast script is read, and that is
        // a copy of one loaded, left out without a warning.
        let copy = folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + "-copy")
        try? FileManager.default.copyItem(at: folder, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let withCopy = ExtensionStore.load([.init(path: folder.path, found: false), .init(path: copy.path, found: true)])
        check(withCopy.commands == index.commands && withCopy.bundles == index.bundles && withCopy.skipped.isEmpty
              && withCopy.identical.map(\.path) == [copy.appendingPathComponent("stquiet.sh").path],
              "a found copy of the folder adds nothing and warns of nothing (\(withCopy.identical.map(\.lastPathComponent)), \(withCopy.skipped.count) skipped)")
        controller.services.loadExtensions = { _, _ in index }
        controller.composer.setInputMode(.english)  // the texts below are typed as letters

        let before = client.inserted.count
        if start("sthello") {
            check(!controller.composer.isLevelTwo, "Tab only completes a command that takes no input")
            _ = act(controller, client)
            waitForEnd()
            let answer = controller.composer.choices.first
            _ = enter(controller, client)
            let expected = "working\nhello from " + folder.lastPathComponent + " in " + (UIText.chinese ? "zh" : "en")
            check(answer?.text == expected && client.inserted.last == expected && !controller.composer.isComposing,
                  "…the action key runs it; its output goes in, with the folder and the language it was told (\(client.inserted.last ?? ""))")
        } else {
            check(false, "@sthello is picked from the list ('\(client.marked)')")
        }
        clear()
        let count = client.inserted.count
        if start("stquiet") {
            _ = act(controller, client)
            _ = pump(timeout: 5) { !controller.composer.isComposing }
            check(client.inserted.count == count && client.marked.isEmpty && !controller.composer.isComposing,
                  "a Raycast silent script inserts nothing")
        }
        clear()
        if start("stneeds") {
            _ = act(controller, client)
            check(!controller.composer.isLevelTwo && client.marked == "stneeds › ", "a script missing its argument doesn't run (\(client.marked))")
        }
        clear()
        if start("stlist") {
            let typing = Date()
            typeText("abc")
            let took = Date().timeIntervalSince(typing)
            check(took < 0.25, String(format: "typing a list's text doesn't wait for its environment (3 keys in %.0f ms)", took * 1000))
            _ = pump(timeout: 5) { controller.composer.currentList != nil }
            let rows = controller.panelModel().rows.map(\.text)
            check(rows == ["first abc", "info"], "a list runs as the text is typed, its rows shown (\(rows))")
            _ = act(controller, client)
            check(client.inserted.last == "picked-abc" && !controller.composer.isComposing,
                  "the action key does the highlighted row's action: inserts its arg (\(client.inserted.last ?? ""))")
        }
        clear()
        if start("stgreet") {
            typeText("bob")
            _ = act(controller, client)
            waitForEnd()
            _ = enter(controller, client)
            check(client.inserted.last == "hi, bob", "a bundle's preference reaches its script (\(client.inserted.last ?? ""))")
        }
        clear()
        if start("stwait") {
            _ = act(controller, client)
            check(!controller.composer.isComposing && client.marked.isEmpty, "a background command starts and the draft is done")
            _ = pump(timeout: 5) { !notified.isEmpty }
            check(notified.first?.hasSuffix("| waited\n0.3 s") == true && controller.scriptTasks.background.first?.outcome == .done,
                  "…it notifies with its summary and detail when done, and the menu bar panel lists it (\(notified))")
            controller.scriptTasks.background.forEach { controller.scriptTasks.remove($0.id) }
            // Started from no text field at all (as when the field's controller is gone while the environment is
            // made): ScriptTasks holds it, and it runs.
            notified = []
            let wait = index.commands.first { $0.name == "stwait" }!
            controller.scriptTasks.startInBackground(wait, arguments: [], prepare: {
                try? await Task.sleep(nanoseconds: 200_000_000)
                return .success(ShellEnvironment.current)
            }, say: { notified.append($0) })
            _ = pump(timeout: 5) { !notified.isEmpty }
            check(notified.first?.hasSuffix("| waited\n0.3 s") == true, "…and one started without its text field still runs (\(notified))")
            controller.scriptTasks.background.forEach { controller.scriptTasks.remove($0.id) }
        }
        clear()
        check(client.inserted.count == before + 3, "only the extensions' results went in")
    }

    /// The composer's notices (`Composer.Messages`): Chinese wording → English wording.
    static let englishNotices: [String: String] = Dictionary(
        zip(Mirror(reflecting: Composer.Messages.chinese).children.compactMap { $0.value as? String },
            Mirror(reflecting: Composer.Messages.english).children.compactMap { $0.value as? String }),
        uniquingKeysWith: { first, _ in first })

    static func run(snapshotDirectory: URL, typingLagOnly: Bool = false, autocompleteOnly: Bool = false) -> Int32 {
        waitForOtherSelfTests()
        _ = NSApplication.shared
        // The recent @questions in a file of the self-test's own: the user's are neither listed nor changed.
        QuestionHistoryStore.url = snapshotDirectory.appendingPathComponent("recent-questions.json")
        QuestionHistoryStore.clear()  // none left from a run before
        // Voice tests play audio files; the microphone and its permission prompt are never used.
        AllInOneIMEInputController.microphoneAllowed = false
        try? FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        // A config of its own (`useOwnConfig`): the user's is read for its AWS profile and region, and to check that
        // nothing touched it; its settings windows never ask the user's keychain or shell which keys there are.
        let userConfig = try? Data(contentsOf: Config.userURL)
        useOwnConfig(in: snapshotDirectory)
        SettingsModel.looksUpKeys = false
        // Sync through iCloud, if anything starts it, with the self-test's config and folders of its own: never the
        // user's iCloud Drive, config or sync record.
        ICloudSyncController.shared.engine = ICloudSyncEngine(
            folder: ICloudSyncFolder(url: snapshotDirectory.appendingPathComponent("icloud-unused/CloudDocs/AllInOneIME")),
            configURL: Config.defaultURL, stateURL: snapshotDirectory.appendingPathComponent("icloud-unused/state.json"),
            questionsURL: QuestionHistoryStore.url, machineID: MachineIdentity.syncID)
        // Keys saved, read or removed by anything it runs go to a keychain in memory: the user's is never touched (nor
        // moved between the login keychain and iCloud Keychain when a section turns sync on).
        APIKeys.keychain = .inMemory()
        ICloudSyncController.shared.keys = nil
        // Autocomplete learns and counts in memory, never in the input method's defaults; its cloud question is answered
        // "On This Mac Only" (its own section shows the real one, invisible); its suggestion is drawn invisible, and the
        // user's clicks don't take it down.
        AutocompleteSwitch.store = AutocompleteStore()
        AutocompleteSwitch.askCloud = { _, _, answered in answered(false) }
        (GhostOverlay.invisible, GhostOverlay.watchesPointer, AutocompleteConsentPanel.invisible) = (true, false, true)
        _ = secureInputGoes()  // held elsewhere just now (a password field): a while for it to go

        let className = Bundle.main.object(forInfoDictionaryKey: "InputMethodServerControllerClass") as? String ?? ""
        check(NSClassFromString(className) == AllInOneIMEInputController.self,
              "Info.plist controller class '\(className)' resolves")

        // Level one: the Chinese data (`--rime-data`, which `make selftest` passes, else the installed pack)
        // with a throw-away user directory.
        guard let shared = RimeDirectories.shared, FileManager.default.fileExists(atPath: shared.path) else {
            print("✗ no Rime data: pass --rime-data ThirdParty/rime-data or install the Chinese pack")
            return 1
        }
        // A downloaded pack has no Lua of its own: the app's is linked in, as at launch.
        if FileManager.default.fileExists(atPath: shared.appendingPathComponent("install.json").path) {
            check((try? LanguagePackStore(directory: shared.deletingLastPathComponent())
                .linkCode(.chinesePinyin, from: RimeDirectories.code)) != nil, "the app's Rime scripts linked into the pack")
        }
        let userDir = snapshotDirectory.appendingPathComponent("rime-user")
        let logDir = snapshotDirectory.appendingPathComponent("rime-log")
        try? FileManager.default.removeItem(at: userDir)
        defer {
            try? FileManager.default.removeItem(at: userDir)
            try? FileManager.default.removeItem(at: logDir)
        }
        let deployStart = Date()
        do {
            try RimeService.shared.start(sharedDataDir: shared, userDataDir: userDir, logDir: logDir)
        } catch {
            print("✗ Rime did not start: \(error)")
            return 1
        }
        check(RimeService.shared.waitUntilReady(timeout: 60),
              String(format: "Rime deployed in %.2fs (librime %@)", Date().timeIntervalSince(deployStart), RimeService.shared.version))

        guard let server = IMKServer(
            name: "com.aipinyin.inputmethod.AIPinyin_SelfTest_Connection",
            bundleIdentifier: Bundle.main.bundleIdentifier)
        else {
            print("✗ IMKServer could not be created (run from inside AllInOneIME.app)")
            return 1
        }
        let client = FakeTextClient()
        guard let controller = AllInOneIMEInputController(server: server, delegate: nil, client: nil) else {
            print("✗ could not create AllInOneIMEInputController")
            return 1
        }
        // The self-test's config, but results inserted at once: checks read what went in right away (the
        // typing-out section turns it on for itself).
        controller.services.loadSettings = {
            var config = LiveConfig.current
            config.typeOut = false
            return config
        }
        controller.clientOverride = client
        // No keys posted, the clipboard left alone: line breaks into a terminal go in on one line unless a
        // check pastes them itself.
        controller.canPasteInTerminal = { false }
        controller.pasteInTerminal = { _ in }
        controller.services.pointerUsedWithin = { _ in false }  // the user's own clicks meanwhile aren't Shift-clicks
        controller.selectionByAccessibility = false  // the fake field's selection only, never the user's frontmost app's
        controller.services.loadCommandUsage = { CommandUsage() }  // leave the user's command order alone
        controller.services.loadExtensions = { _, _ in .empty }  // never the user's own extensions (the extension check makes its own)
        controller.services.saveCommandUsage = { _ in }
        controller.recordApp = { _ in }  // the user's recent apps (Settings → Apps) left alone
        controller.services.takeRenameNotice = { _ in nil }  // the user's own rename notice left for them (the @reply section has its own)
        controller.warmsUpVision = false  // the real clipboard's types left alone (the @reply section reads its own)
        giveUp = { for _ in 0..<4 where controller.composer.isComposing { _ = escape(controller, client) } }
        testTypingLag(controller, client)
        if typingLagOnly {
            check((try? Data(contentsOf: Config.userURL)) == userConfig, "the user's config was left unchanged")
            return summary()
        }
        if autocompleteOnly {
            // The self-test's settings, as the sections below have them, and nothing else (no AI requests).
            controller.services.loadSettings = { SelfTest.settings }
            controller.services.secureInputActive = { false }
            CandidatePanel.shared.alphaValue = 0
            CandidatePanel.shared.ignoresMouseEvents = true
            controller.ensureEngine()
            controller.applySettings()
            testAutocomplete(controller, client, snapshotDirectory: snapshotDirectory)
            controller.deactivateServer(client)
            check((try? Data(contentsOf: Config.userURL)) == userConfig, "the user's config was left unchanged")
            return summary()
        }
        // @translate: into the output languages but the sentence's own; with @improve, one request. For the
        // README image the live requests translate into English only (three versions).
        // It runs before `settings` is pinned below: its own settings here (the README's Chinese interface,
        // English only), and the self-test's back afterwards.
        section("@translate for the README (live Bedrock)", needs: [.composing, .bedrock])
        let (converterBefore, settingsBefore, loadBefore) = (controller.services.converter, settings, controller.services.loadSettings)
        settings = (try? Config.load()) ?? .default
        (settings.typeOut, settings.typeOutMistakes) = (false, false)  // inserted at once, no typos
        settings.setOrder([OutputLanguage.english])  // the hint under the draft says the same
        settings.setOrder([Language.chinese, .english])  // pinyin first
        settings.uiLanguage = "zh"
        controller.services.loadSettings = { SelfTest.settings }
        controller.applySettings()
        controller.services.converter = Converter(loadConfig: {
            var config = try Config.load()
            config.setOrder([OutputLanguage.english])
            return config
        })
        press(controller, client, "@", code: 0x13, flags: .shift)
        type("t", controller, client)
        press(controller, client, "\t", code: VirtualKey.tab)
        type("wojintianyoudianbushufu", controller, client)
        readmeSnapshot("2-translate-pinyin", controller, client, in: snapshotDirectory)  // README: the first image
        _ = enter(controller, client)
        if finishConversion(controller, "@translate") {
            readmeSnapshot("3-translate", controller, client, in: snapshotDirectory)
            // Three versions with one translation language, a line each with several.
            let lines = controller.composer.choices.filter {
                if case .translation = $0.kind { return true }
                return $0.kind == .version
            }
            check(lines.count >= 2 && lines.allSatisfy { $0.text != "我今天有点不舒服" }
                  && !controller.composer.choices.contains { if case .rewrite = $0.kind { return true } else { return false } },
                  "@translate: translated lines, no rewrites (\(lines.map(\.text)))")
            _ = escape(controller, client)
            _ = escape(controller, client)
        }
        controller.commitComposition(client)
        (controller.services.converter, settings, controller.services.loadSettings) = (converterBefore, settingsBefore, loadBefore)
        controller.applySettings()
        englishReadmeScenes(controller, client, in: snapshotDirectory)
        testNothingToTranslateInto(controller, client, in: snapshotDirectory)
        // @open's history in memory: the user's is neither read (it would reorder the results checked
        // here) nor changed (what the test opens would come first in their searches).
        var openHistory = OpenHistory()
        controller.services.loadOpenHistory = { openHistory }
        controller.services.recordOpen = { openHistory.record($0) }
        controller.readClipboard = { .none }  // never the real clipboard; the ⌘V section supplies its text
        // Never the real Contacts or Messages, nor the user's recent recipients (the @imessage section has its own).
        controller.services.loadContacts = { [] }
        controller.services.messageSender = StandInSender()
        controller.services.loadRecentHandles = { [] }
        controller.services.saveRecentHandles = { _ in }
        // The self-test's config (Bedrock with the user's AWS profile and region, all else the defaults) with the
        // options the checks rely on pinned; sections below change `settings` and the controller follows (nothing
        // is written to disk).
        settings = (try? Config.load()) ?? .default
        (settings.typeOut, settings.typeOutMistakes) = (false, false)  // inserted at once, no typos
        settings.setOrder([OutputLanguage.english, .chinese])
        settings.setOrder([Language.chinese, .english])  // Shift switches
        settings.claudeInBackground = false  // @agent records a Terminal launch; nothing starts in the background
        settings.voiceInput = true
        settings.actionKey = .enter  // the default; the action key section tries the others
        settings.uiLanguage = "zh"  // README images; the interface language section tries English
        settings.claudeInBackground = false  // @agent records a Terminal launch; nothing starts in the background
        // In a column (horizontal is the default): the checks and README images below read the candidates one under
        // the other; `testHorizontalCandidates` tries the row.
        settings.candidateLayout = .vertical
        controller.services.loadSettings = { SelfTest.settings }
        controller.services.converter = liveConverter
        // README images read the same on every Mac: times with the 24-hour clock, whatever this one uses.
        let clockBefore = UIText.clock24
        UIText.clock24 = true
        defer { UIText.clock24 = clockBefore }
        section("the Rime session")
        controller.ensureEngine()
        controller.applySettings()
        check(controller.composer.engine != nil, "Rime session created")
        let panel = CandidatePanel.shared
        // Invisible and click-through while testing (someone may be using the Mac); snapshots
        // render the view directly, so they are unaffected.
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true

        section("secure input (password fields)")
        if SecureInput.ownerPID() != nil {
            // Another app (e.g. the lock screen) holds it: that must not stop us from composing here. When macOS
            // can't tell who holds it, composing stops everywhere (`SecureInput.blocksComposing`): nothing to check.
            print("  secure input is \(SecureInput.ownerDescription()); checking it doesn't block other apps")
            if SecureInput.ownerPID() == -1 { skipping = secureInputOn }
            type("ni", controller, client)
            check(client.marked == "ni" || client.marked == "n i", "composing still works (\(client.marked))")
            _ = escape(controller, client)
            skipping = nil
        } else {
            _ = EnableSecureEventInput()
            if SecureInput.ownerPID() != getpid() {
                // While the lock screen is up, macOS attributes secure input to loginwindow.
                print("  macOS attributes secure input to \(SecureInput.ownerDescription()), not this process; "
                      + "skipping the owner checks")
            } else {
                check(!press(controller, client, "a", code: 0x00), "letters pass through in the app holding secure input")
                check(client.marked.isEmpty && !controller.composer.isComposing, "nothing is composed")
                _ = DisableSecureEventInput()
                type("ni", controller, client)
                _ = EnableSecureEventInput()
                check(!press(controller, client, "d", code: 0x02), "key passes through when secure input turns on mid-composition")
                check(client.inserted.last == "ni" && client.marked.isEmpty, "pending letters committed as typed")
            }
            _ = DisableSecureEventInput()
        }
        controller.commitComposition(client)  // start the next section from a clean state
        client.inserted.removeAll()
        // Its notice goes by itself (its timer, in the run loop's default mode), as any notice does. Nothing below runs the
        // run loop before the README scene of the next sentence (1b-sentence-pinyin): the notice would still be on its footer.
        check(pump(timeout: 5) { controller.notice == nil }, "the secure input notice goes by itself (\(controller.notice ?? "-"))")

        section("pass-through when idle", needs: .composing)
        check(!press(controller, client, "1", code: 0x12), "digit passes through")
        check(!press(controller, client, "c", code: 0x08, flags: .command), "⌘C passes through")
        check(!enter(controller, client), "Enter passes through")
        check(press(controller, client, ",", code: 0x2B) && client.inserted.last == "，", "',' types a Chinese comma")

        section("regular input method, @improve (live Bedrock)", needs: .composing)
        type("nihao", controller, client)
        _ = space(controller, client)
        check(client.inserted.last == "你好" && client.marked.isEmpty, "Space inserts 你好 straight into the text")
        type("nihao", controller, client)
        _ = enter(controller, client)
        check(client.inserted.last == "nihao" && client.marked.isEmpty, "⏎ while composing inserts the letters, no AI")
        check(!enter(controller, client), "⏎ with nothing pending is the app's")
        press(controller, client, "@", code: 0x13, flags: .shift)
        type("i", controller, client)
        _ = enter(controller, client)
        check(client.marked == "improve › ", "@i ⏎ picks @improve ('\(client.marked)')")
        type("wojintianyoudianbushufu", controller, client)
        check(controller.panelModel().footer == "空格 选词 · ⏎ 润色 / 改写", "the footer names the command (\(controller.panelModel().footer))")
        readmeSnapshot("1b-sentence-pinyin", controller, client, in: snapshotDirectory)
        needing([.composing, .bedrock])
        _ = enter(controller, client)  // converts the pinyin and runs @improve
        if finishConversion(controller, "@improve") {
            // @improve polishes in the sentence's own language (a version only re-punctuating it is hidden).
            let versions = controller.composer.choices.filter { $0.kind == .version }
            check(versions.count >= 2 && versions.allSatisfy { $0.text.containsHan } && controller.composer.choices.first?.text == "我今天有点不舒服",
                  "polished Chinese versions of 我今天有点不舒服, not translated")
            readmeSnapshot("4-final-light", controller, client, in: snapshotDirectory)
            readmeSnapshot("4-final-dark", controller, client, in: snapshotDirectory, appearance: .darkAqua)
            let first = controller.composer.choices[controller.composer.highlighted].text
            _ = enter(controller, client)
            check(client.inserted.last == first, "⏎ inserts the first version")
        }
        controller.commitComposition(client)

        // ⌘V in the command: the clipboard's text (a fake one here) goes into it, not the document.
        section("@improve + ⌘V (live Bedrock)", needs: .composing)
        let clipboard = "这个项目的进度太慢了\n我们需要尽快想办法"
        controller.readClipboard = { .text(clipboard) }
        press(controller, client, "@", code: 0x13, flags: .shift)
        type("i", controller, client)
        _ = enter(controller, client)
        let insertedBefore = client.inserted.count
        check(press(controller, client, "v", code: 0x09, flags: .command), "⌘V in the command is the input method's (the app doesn't paste)")
        _ = pump(timeout: 1) { client.marked != "improve › " }  // the clipboard is read once the key is answered
        check(client.marked == "improve › 这个项目的进度太慢了我们需要尽快想办法" && client.inserted.count == insertedBefore,
              "the clipboard's text goes into the command, as one line ('\(client.marked)')")
        needing([.composing, .bedrock])
        _ = enter(controller, client)
        if finishConversion(controller, "@improve on pasted text") {
            check(controller.composer.choices.first?.text == "这个项目的进度太慢了我们需要尽快想办法"
                  && controller.composer.choices.contains { $0.kind == .version && $0.text.containsHan },
                  "the pasted text is improved (polished, still Chinese)")
            _ = enter(controller, client)
        }
        controller.readClipboard = { .none }
        check(!press(controller, client, "v", code: 0x09, flags: .command), "⌘V with nothing pending is the app's")
        controller.commitComposition(client)
        needing(.composing)
        // In a terminal (it pastes on ⌘V itself) ⌘V stays the terminal's. ⏎ on the empty command only hints:
        // the clipboard isn't read (⌃V brings its text in).
        client.bundleIDOverride = "com.mitchellh.ghostty"
        controller.activateServer(client)
        var clipboardReads = 0
        controller.readClipboard = { clipboardReads += 1; return .text(clipboard) }
        press(controller, client, "@", code: 0x13, flags: .shift)
        type("i", controller, client)
        _ = enter(controller, client)  // picks @improve
        check(controller.panelModel().status == .hint("写点内容，或按 ⌃V 粘贴"), "the hint says to write or paste (\(controller.panelModel().status))")
        _ = enter(controller, client)
        _ = pump(timeout: 0.5) { false }
        check(clipboardReads == 0 && client.marked == "improve › " && !controller.composer.isLevelTwo
              && controller.panelModel().detail == "在命令后面写上内容",
              "⏎ on the empty command only hints; the clipboard isn't read (\(client.marked))")
        check(!press(controller, client, "v", code: 0x09, flags: .command) && client.inserted.last == "@improve ",
              "in a terminal ⌘V reaches the terminal (no second copy in the command)")
        controller.commitComposition(client)
        // ⌃V works in a terminal too (it doesn't paste on ⌃V itself), also after text already typed.
        press(controller, client, "@", code: 0x13, flags: .shift)
        type("i", controller, client)
        _ = enter(controller, client)
        check(controller.panelModel().footer == "⌃V 粘贴 · ⌫ 删字 · Esc 清除", "the footer names ⌃V (\(controller.panelModel().footer))")
        type("nihao", controller, client)
        let insertedBeforeControlV = client.inserted.count
        check(press(controller, client, "v", code: 0x09, flags: .control)
              && pump(timeout: 1) { client.marked.hasSuffix("想办法") }
              && client.marked == "improve › 你好这个项目的进度太慢了我们需要尽快想办法" && client.inserted.count == insertedBeforeControlV,
              "in a terminal ⌃V adds the clipboard's text after what was typed (\(client.marked))")
        _ = escape(controller, client)
        client.bundleIDOverride = nil
        controller.activateServer(client)
        controller.readClipboard = { .none }
        // What is taken from a clipboard, on private pasteboards (the real one is never read here).
        func reads(_ fill: (NSPasteboard) -> Void) -> ClipboardContent {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            board.clearContents()
            fill(board)
            return AllInOneIMEInputController.clipboardContent(board)
        }
        check(reads { $0.setString("plain text", forType: .string) } == .text("plain text"), "plain text is taken")
        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"] {
            let item = NSPasteboardItem()
            item.setString("secret", forType: .string)
            item.setString("", forType: NSPasteboard.PasteboardType(rawValue: marker))
            check(reads { $0.writeObjects([item]) } == .none, "a password marked \(marker) is not taken")
        }
        check(reads { $0.setData(Data([0x49, 0x49, 0x2A, 0]), forType: .tiff) } == .image(Data([0x49, 0x49, 0x2A, 0])),
              "an image is taken as one: its text is read on this Mac (the screenshot section reads it)")

        _ = pump(timeout: 3) { controller.panelModel().detail == nil }

        section("level one: local pinyin", needs: .composing)
        type("nihao", controller, client)
        let state = controller.composer.engineState
        check(state.candidates.first?.text == "你好", "first candidate for 'nihao' is 你好 (\(state.candidates.prefix(5).map(\.text)))")
        check(client.marked.replacingOccurrences(of: " ", with: "") == "nihao", "pinyin is marked inline (\(client.marked))")
        check(panel.isShowing, "candidate panel is visible")
        snapshot("1-pinyin", in: snapshotDirectory)
        check(escape(controller, client) && client.marked.isEmpty && !controller.composer.isComposing, "Esc cancels the pinyin")

        // A click on a row (the panel's own handler, as its mouseDown calls it) picks it, as its digit would. On
        // today's date ("rq", rime-ice's Lua): a word picked would be learned, and move up in the checks below.
        type("rq", controller, client)
        let clicked = controller.composer.engineState.candidates.dropFirst().first?.text ?? "-"
        panel.onSelect?(1)
        check(client.inserted.last == clicked && client.marked.isEmpty, "a click on the second row inserts \(clicked) (\(client.inserted.last ?? "-"))")
        testHorizontalCandidates(controller, client, snapshotDirectory: snapshotDirectory)

        type("rq", controller, client)
        let year = String(Calendar(identifier: .gregorian).component(.year, from: Date()))
        let dates = controller.composer.engineState.candidates.map(\.text)
        check(dates.contains { $0.contains(year) }, "Lua plugin works: 'rq' offers today's date (\(dates.prefix(3)))")
        _ = escape(controller, client)

        check(improve(controller, client), "@i Tab starts an @improve draft ('\(client.marked)')")
        type("nihao", controller, client)
        _ = space(controller, client)
        check(client.marked == "improve › 你好" && controller.composer.draft == "@improve 你好",
              "Space confirms 你好 into the command (not inserted yet)")
        check(controller.panelModel().status == draftHint(controller, input: .chinese),
              "the hint names the action key (\(controller.panelModel().status))")
        snapshot("2-draft-hint", in: snapshotDirectory)
        check(shiftEnter(controller, client) && client.inserted.last == "@improve 你好" && client.marked.isEmpty,
              "⇧⏎ inserts the command as typed")

        section("⇧Space is Space", needs: .composing)
        func shiftSpace() -> Bool { press(controller, client, " ", code: VirtualKey.space, flags: .shift) }
        type("nihao", controller, client)
        check(shiftSpace() && client.inserted.last == "你好" && client.marked.isEmpty, "⇧Space picks 你好, like Space")
        check(!shiftSpace() && controller.panelModel().detail == nil,
              "with nothing pending ⇧Space is the app's (it types the space) and switches nothing")
        improve(controller, client)
        type("nihao", controller, client)
        _ = shiftSpace()
        check(shiftSpace() && controller.composer.draft == "@improve 你好 " && !controller.composer.isLevelTwo,
              "in a command ⇧Space picks, then types a space ('\(controller.composer.draft)')")
        _ = escape(controller, client)

        testEnglishWords(controller, client, snapshotDirectory: snapshotDirectory)
        testEnglishWordsSettings(snapshotDirectory: snapshotDirectory)

        section("Shift switches Chinese / English", needs: .composing)
        tapShift(controller, client)
        check(controller.composer.engineState.isAsciiMode, "Shift alone switches to English")
        check(!press(controller, client, "a", code: 0x00), "letters go straight to the app")
        improve(controller, client)
        type("ok", controller, client)
        check(client.marked == "improve › ok" && controller.composer.isLatinDraft, "after @improve, letters go into the command")
        check(shiftEnter(controller, client) && client.inserted.last == "@improve ok" && client.marked.isEmpty,
              "⇧⏎ inserts the English command as typed")
        improve(controller, client)
        type("hi", controller, client)
        check(!press(controller, client, "a", code: 0x00, flags: .command) && client.inserted.last == "@improve hi",
              "⌘A inserts the English command first, then reaches the app")
        tapShift(controller, client)
        check(!controller.composer.engineState.isAsciiMode, "Shift alone switches back to Chinese")

        section("no AI while secure input is on", needs: .composing)
        controller.services.secureInputActive = { true }
        improve(controller, client)
        type("nihao", controller, client)
        act(controller, client)
        if case let .failed(message) = controller.composer.phase {
            check(message.contains("安全输入"), "translation refused without a request: \(message)")
        } else {
            check(false, "expected the translation to be refused, got \(controller.composer.phase)")
        }
        check(press(controller, client, "0", code: 0x1D) && client.inserted.last == "你好", "0 still inserts the Chinese")
        // The rest exercises the normal state (the real flag may be on now, e.g. while the screen is locked).
        controller.services.secureInputActive = { false }
        _ = pump(timeout: 3) { controller.panelModel().detail == nil }  // the 中/英 (Chinese/English) notice, not in the README images

        section("level two: translate + polish (live Bedrock)", needs: [.composing, .bedrock])
        improve(controller, client)
        type("wojintianyoudianbushufu", controller, client)
        let sentence = controller.composer.engineState.candidates.first?.text ?? ""
        check(sentence == "我今天有点不舒服", "whole-sentence candidate (\(sentence))")
        _ = space(controller, client)
        check(controller.composer.sentText == sentence, "Space confirms the sentence")
        snapshot("2b-sentence-draft", in: snapshotDirectory)
        let started = Date()
        check(act(controller, client), "the action key starts the translation")
        check(panel.isShowing && client.marked == "improve › " + sentence, "panel visible, the command stays marked")
        var streamingSnapshotTaken = false
        let finished = pump(timeout: 20) {
            if !streamingSnapshotTaken, case .translating = controller.composer.phase,
               controller.composer.choices.count >= 2 {
                streamingSnapshotTaken = true
                print(String(format: "  first rows after %.2fs", Date().timeIntervalSince(started)))
                snapshot("3-streaming", in: snapshotDirectory)
            }
            if case .translating = controller.composer.phase { return false }
            return true
        }
        check(finished, String(format: "translation finished in %.2fs", Date().timeIntervalSince(started)))
        if case let .failed(message) = controller.composer.phase {
            check(false, "translation failed: \(message)")
            if skipping == nil { return 1 }  // what follows reads its results (skipped, it runs on, counting nothing)
        }
        let choices = controller.composer.choices
        for choice in choices { print("  \(choice.label) \(choice.text)") }
        check(choices.filter { $0.kind == .version && !$0.text.isEmpty }.count >= 2, "polished versions")
        check(choices.first?.kind == .original && choices.first?.text == sentence, "row 0 is the sentence as typed")
        // Rewrite rows are only shown when their wording differs from the original (and from each other).
        let rewrites = choices.filter { $0.kind.isRewrite }
        check(!rewrites.isEmpty && rewrites.allSatisfy { $0.text.wordingKey != sentence.wordingKey },
              "Chinese rewrites really reword the sentence (\(rewrites.map { "\($0.label) \($0.kind) \($0.text)" }))")
        check(controller.composer.highlighted == 1, "first English version highlighted")
        let second = choices.count > 2 ? choices[2].text : ""
        check(press(controller, client, "2", code: 0x13), "digit 2 consumed")
        check(client.inserted.last == second && !second.isEmpty, "digit 2 commits '\(second)'")
        check(client.marked.isEmpty && !panel.isShowing, "marked text cleared and panel hidden")

        section("cache hit + Space commits", needs: [.composing, .bedrock])
        improve(controller, client)
        type("wojintianyoudianbushufu", controller, client)
        check(act(controller, client) && controller.composer.sentText == sentence,
              "the action key right on the pinyin converts it and sends it")
        _ = pump(timeout: 2) { controller.composer.phase == .choosing }
        check(controller.composer.phase == .choosing, "same sentence answered from cache")
        _ = space(controller, client)
        check(choices.count > 1 && client.inserted.last == choices[1].text, "Space commits the highlighted English")

        testRefine(controller, client, snapshotDirectory: snapshotDirectory)

        section("typing more in level two continues the sentence", needs: [.composing, .bedrock])
        improve(controller, client)
        type("nihao", controller, client)
        _ = space(controller, client)
        act(controller, client)  // translation starts
        type("ma", controller, client)  // keep typing instead of choosing
        check(controller.composer.phase == .drafting && client.marked.hasPrefix("improve › 你好"), "back to the draft (\(client.marked))")
        _ = space(controller, client)
        check(controller.composer.draft == "@improve 你好吗", "sentence is now 你好吗 (\(controller.composer.draft))")
        _ = shiftEnter(controller, client)
        check(client.inserted.last == "@improve 你好吗", "⇧⏎ inserts it as typed")

        // The cached sentence again, so these need no requests.
        section("action key setting: a tap of ⌥, ⌥Space, Space", needs: [.composing, .bedrock])
        improve(controller, client)
        type("nihao", controller, client)
        _ = space(controller, client)
        _ = space(controller, client)
        check(controller.composer.draft == "@improve 你好 " && !controller.composer.isLevelTwo,
              "with ⏎, Space in a draft types a space ('\(controller.composer.draft)')")
        check(!controller.composer.spaceActs, "and never sends it")
        _ = escape(controller, client)
        settings.actionKey = .optionTap
        controller.applySettings()
        improve(controller, client)
        type("wojintianyoudianbushufu", controller, client)
        tapOption(controller, client)
        _ = pump(timeout: 2) { controller.composer.phase == .choosing }
        check(controller.composer.phase == .choosing && controller.composer.sentText == sentence,
              "单按 ⌥: a tap converts the pinyin and sends it")
        _ = escape(controller, client)
        check(enter(controller, client) && pump(timeout: 2) { controller.composer.phase == .choosing },
              "单按 ⌥: ⏎ runs the command too")
        check(press(controller, client, "0", code: 0x1D) && client.inserted.last == sentence, "0 inserts the original")
        settings.actionKey = .optionSpace
        controller.applySettings()
        improve(controller, client)
        type("wojintianyoudianbushufu", controller, client)
        _ = optionSpace(controller, client)
        _ = pump(timeout: 2) { controller.composer.phase == .choosing }
        check(controller.composer.phase == .choosing && controller.composer.sentText == sentence,
              "⌥空格: converts the pinyin and sends it")
        check(optionSpace(controller, client) && choices.count > 1 && client.inserted.last == choices[1].text,
              "⌥空格 again inserts the highlighted line")
        settings.actionKey = .space
        controller.applySettings()
        improve(controller, client)
        type("wojintianyoudianbushufu", controller, client)
        _ = space(controller, client)
        check(controller.composer.spaceActs && controller.panelModel().status == draftHint(controller, input: .chinese),
              "空格: the hint says Space (\(controller.panelModel().status))")
        _ = space(controller, client)
        _ = pump(timeout: 2) { controller.composer.phase == .choosing }
        check(controller.composer.phase == .choosing, "空格: the second Space sends it")
        check(press(controller, client, "0", code: 0x1D) && client.inserted.last == sentence, "0 inserts the original")
        settings.actionKey = .enter
        controller.applySettings()
        check(controller.composer.actionKey == .enter, "back to ⏎")

        // The cached sentence once more, with the interface in English (an English system, or the
        // Interface language setting, 界面语言, set to English).
        section("interface language: English", needs: [.composing, .bedrock])
        settings.uiLanguage = "en"
        controller.applySettings()
        improve(controller, client)
        type("wojintianyoudianbushufu", controller, client)
        check(controller.panelModel().footer == "Space picks · ⏎ to " + UIText.action(input: .chinese, config: settings),
              "English footer while typing: \(controller.panelModel().footer)")
        _ = space(controller, client)
        check(controller.panelModel().status == draftHint(controller, input: .chinese)
              && controller.panelModel().footer == "⌃V paste · ⌫ delete · Esc clear",
              "English hint under the draft: \(controller.panelModel().status)")
        act(controller, client)
        _ = pump(timeout: 2) { controller.composer.phase == .choosing }
        let english = controller.panelModel()
        let styleNames = english.rows.dropFirst().map { $0.comment.components(separatedBy: " · ")[0] }
        check(english.footer == "Type, ⇧⏎ refine · Space / ⏎ insert · digits pick · 0 original · ⌘C copy · Esc back"
              && english.rows.first?.comment == "original" && !styleNames.joined().containsHan,
              "English results panel: \(english.footer) | \(english.rows.map(\.comment))")
        snapshot("9-english-ui", in: snapshotDirectory)
        _ = escape(controller, client)
        _ = escape(controller, client)
        tapShift(controller, client)
        check(controller.panelModel().detail == "English", "English mode notice: \(controller.panelModel().detail ?? "none")")
        tapShift(controller, client)
        let englishMenu = controller.menu()?.items.map(\.title) ?? []
        check(englishMenu.first == "Settings…" && englishMenu.contains { $0.hasPrefix("Model: ") },
              "English input menu (\(englishMenu.prefix(3)))")
        settings.uiLanguage = "zh"
        controller.applySettings()
        check(controller.composer.messages == .chinese && UIText.chinese, "back to Chinese")
        _ = pump(timeout: 3) { controller.panelModel().detail == nil }  // let the 中 (Chinese mode) notice expire

        testEnglishAndOutput(controller, client, snapshotDirectory: snapshotDirectory)
        testVoice(controller, client, snapshotDirectory: snapshotDirectory)
        controller.services.loadSettings = { SelfTest.settings }
        controller.services.converter = liveConverter
        controller.applySettings()
        testCommands(controller, client, snapshotDirectory: snapshotDirectory)
        testNotesAndReminders(controller, client, snapshotDirectory: snapshotDirectory)
        testNoteDestinations(controller, client, snapshotDirectory: snapshotDirectory)
        testToolCommands(controller, client, snapshotDirectory: snapshotDirectory)
        testIMessage(controller, client)
        testReportIssue(controller, client, snapshotDirectory: snapshotDirectory)
        testSelectionKept(controller, client)
        testCommandsOnSelection(controller, client)
        testAtAfterAWord(controller, client)
        testSnippets(controller, client)
        testAppProfiles(controller, client, snapshotDirectory: snapshotDirectory)
        testTranslateMode(controller, client, snapshotDirectory: snapshotDirectory)
        testAutocomplete(controller, client, snapshotDirectory: snapshotDirectory)
        testShiftHoldInElectron(controller, client)
        testRecentQuestions(controller, client, snapshotDirectory: snapshotDirectory)
        testQuestionChat(controller, client, snapshotDirectory: snapshotDirectory)
        testContinueListKeepsAgentsNotInstalled(snapshotDirectory: snapshotDirectory)
        testAppleModel(controller, client, snapshotDirectory: snapshotDirectory)
        testRedaction(controller, client, snapshotDirectory: snapshotDirectory)
        testReply(controller, client)
        testReleaseImages(controller, client, snapshotDirectory: snapshotDirectory)
        testAIConfig(snapshotDirectory: snapshotDirectory)
        testAssistantOnDevice(snapshotDirectory: snapshotDirectory)
        testAssistantAutocompleteOnDevice(snapshotDirectory: snapshotDirectory)
        testDoctor(snapshotDirectory: snapshotDirectory)
        testAssistantPage(snapshotDirectory: snapshotDirectory)
        testAWSCredentials(snapshotDirectory: snapshotDirectory)
        testSnippetEditorAndReview(snapshotDirectory: snapshotDirectory)

        section("error display (an invalid Bedrock model)", needs: [.composing, .bedrock])
        controller.services.converter = Converter(loadConfig: {
            var config = try Config.load()
            config.modelId = "allinoneime.invalid-model-for-selftest"
            return config
        })
        func failed() -> Bool { if case .failed = controller.composer.phase { return true } else { return false } }
        improve(controller, client)
        type("ceshi", controller, client)
        _ = space(controller, client)
        act(controller, client)
        _ = pump(timeout: 15) { failed() }
        if case let .failed(message) = controller.composer.phase {
            check(true, "error shown: \(message)")
            snapshot("5-error", in: snapshotDirectory)
        } else {
            check(false, "expected an error, got \(controller.composer.phase)")
        }
        // Space asks again (the model is still invalid, so it fails again).
        check(space(controller, client) && !failed() && pump(timeout: 15) { failed() }, "Space retries")
        _ = escape(controller, client)
        check(controller.composer.phase == .drafting && client.marked == "improve › 测试", "Esc returns to the draft")
        controller.commitComposition(client)
        check(client.inserted.last == "@improve 测试" && controller.composer.phase == .idle, "commitComposition inserts the draft")

        section("commitComposition, the input menu", needs: .composing)
        type("nihao", controller, client)
        controller.commitComposition(client)
        check(client.inserted.last == "你好", "commitComposition converts pending pinyin")

        needing([])
        let menu = controller.menu()
        let menuTitles = menu?.items.map(\.title) ?? []
        check(menuTitles.count > 2 && menuTitles[2].hasPrefix("模型："), "menu shows the model right after 设置… (\(menuTitles.prefix(3)))")
        check(menuTitles.suffix(2) == ["报告问题…", "检查更新…"], "the menu ends with 报告问题… and 检查更新… (\(menuTitles.suffix(2)))")
        // The styles sit in a submenu, whose title names the ones that are on.
        let stylesItem = menu?.items.first { $0.title.hasPrefix("改写风格：") }
        let styleItems = stylesItem?.submenu?.items.filter { $0.action == #selector(AllInOneIMEInputController.toggleStyle(_:)) } ?? []
        check(menu?.items.contains { $0.action == #selector(AllInOneIMEInputController.toggleStyle(_:)) } == false
              && stylesItem.map { item in RewriteStyle.resolve((try? Config.load())?.rewriteStyles ?? []).allSatisfy { item.title.contains($0.name) } } == true,
              "rewrite styles in a submenu titled with the ones on (\(stylesItem?.title ?? "none"))")
        let configured = Set(RewriteStyle.resolve((try? Config.load())?.rewriteStyles ?? []).map(\.name))
        check(styleItems.compactMap { $0.representedObject as? String } == RewriteStyle.catalog.map(\.name)
              && styleItems.allSatisfy { ($0.state == .on) == configured.contains($0.representedObject as? String ?? "") },
              "menu lists the presets, checked per config (\(styleItems.map { "\($0.state == .on ? "✓" : "·")\($0.representedObject ?? "")" }.joined(separator: " ")))")
        // The toggle logic and IMK's info-dictionary form of the sender (no config is written here).
        check(AllInOneIMEInputController.toggled("口语", in: ["正式", "润色"]) == ["正式", "润色", "口语"]
              && AllInOneIMEInputController.toggled("润色", in: ["正式", "润色"]) == ["正式"],
              "style toggle adds at the end and removes in place")
        if let item = styleItems.first {
            let info: NSDictionary = [kIMKCommandMenuItemName as Any: item]
            check(AllInOneIMEInputController.menuItem(from: info) === item, "menu action finds its item in IMK's info dictionary")
        }
        check(menu?.items.first?.action == #selector(AllInOneIMEInputController.showPreferences(_:)),
              "menu starts with 设置… (IMK showPreferences:)")
        // Output and input languages in submenus, listing the languages added in the config.
        let languages = (try? Config.load()) ?? .default
        let outputItems = menu?.items.first { $0.title.hasPrefix("翻译成：") }?.submenu?.items
            .filter { $0.action == #selector(AllInOneIMEInputController.setOutputLanguage(_:)) } ?? []
        check(outputItems.compactMap { $0.representedObject as? String } == languages.outputLanguages.map(\.code)
              && outputItems.allSatisfy { $0.state == .on },
              "menu offers the added output languages, checked per config (\(outputItems.map(\.title)))")
        let inputItems = menu?.items.first { $0.title.hasPrefix("输入：") }?.submenu?.items
            .filter { $0.action == #selector(AllInOneIMEInputController.setDefaultInput(_:)) } ?? []
        check(inputItems.compactMap { $0.representedObject as? String } == languages.inputLanguages.map(\.rawValue)
              && inputItems.filter { $0.state == .on }.compactMap { $0.representedObject as? String } == [languages.defaultInput.rawValue],
              "menu lists the added input languages, the default checked")
        // Dragging a chip: it lands before the chips whose middle is right of the pointer.
        let mids: [String: CGFloat] = ["zh": 50, "en": 150, "ja": 250]
        check(ChipOrder.moved("en", in: ["zh", "en", "ja"], to: 20, midX: { mids[$0] }) == ["en", "zh", "ja"]
              && ChipOrder.moved("zh", in: ["zh", "en", "ja"], to: 200, midX: { mids[$0] }) == ["en", "zh", "ja"]
              && ChipOrder.moved("zh", in: ["zh", "en", "ja"], to: 400, midX: { mids[$0] }) == ["en", "ja", "zh"]
              && ChipOrder.moved("en", in: ["zh", "en", "ja"], to: 140, midX: { mids[$0] }) == ["zh", "en", "ja"],
              "a dragged language chip lands where it's let go")
        check(AllInOneIMEInputController.toggled(Language.english, in: [.chinese]) == [.chinese, .english]
              && AllInOneIMEInputController.toggled(Language.chinese, in: [.chinese]) == [.chinese]
              && AllInOneIMEInputController.toggled(Language.chinese, in: [.chinese, .english]) == [.english],
              "input languages toggle; the last one stays on")
        testFloatingPanel(controller, snapshotDirectory: snapshotDirectory)
        testSettingsWindow(snapshotDirectory: snapshotDirectory)
        testUpdates(controller, snapshotDirectory: snapshotDirectory)
        testExtensionSources(snapshotDirectory: snapshotDirectory)
        testICloudSync(snapshotDirectory: snapshotDirectory)
        testSettingsListsAfterSync(snapshotDirectory: snapshotDirectory)
        testKeychainSync()
        controller.deactivateServer(client)

        section("the user's config")
        check((try? Data(contentsOf: Config.userURL)) == userConfig, "the user's config file was not touched by the whole run")
        return summary()
    }
}
