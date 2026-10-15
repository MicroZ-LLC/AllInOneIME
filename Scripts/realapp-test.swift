// End-to-end check through the real macOS text input system.
//
// A separate app with a real NSTextView types through the *installed* AllInOneIME input method
// (launched by macOS from ~/Library/Input Methods, real Rime engine, live Bedrock call).
// Keys are CGEvent-backed events dispatched to this app's own window, so they take the same
// NSTextInputContext → IMK path as real typing, need no Accessibility permission, and never reach
// other apps. The input source is switched to AllInOneIME for the test and restored afterwards.
//
// Run with: make realtest
import AppKit
import Carbon

let imeID = "com.aipinyin.inputmethod.AIPinyin"

func currentInputSourceID() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
    else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

@discardableResult
func selectInputSource(_ id: String) -> Bool {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
          let source = list.first
    else { return false }
    return TISSelectInputSource(source) == noErr
}

func screenIsLocked() -> Bool {
    let value = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"]
    return (value as? Bool) == true || (value as? Int) == 1
}

/// Where results go (first non-option argument), default /tmp/allinoneime-realtest.
let outputDirectory = URL(fileURLWithPath:
    CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") } ?? "/tmp/allinoneime-realtest")
let originalSourceFile = outputDirectory.appendingPathComponent("original-source.txt")
let configBackupFile = outputDirectory.appendingPathComponent("config.backup.json")

func imeIsRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: imeID).isEmpty
}

/// On-screen windows of the input method process (the candidate panel), in Cocoa screen coordinates.
func imePanelFrames() -> [NSRect] {
    let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: imeID).map(\.processIdentifier))
    guard !pids.isEmpty,
          let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
    else { return [] }
    let screenHeight = NSScreen.screens.first?.frame.height ?? 0
    return windows.compactMap { window in
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
              let bounds = window[kCGWindowBounds as String],
              let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary)
        else { return nil }
        // CGWindow bounds are top-left based; flip to Cocoa's bottom-left origin.
        return NSRect(x: rect.minX, y: screenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

let keyCodes: [Character: UInt16] = [
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
    "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
    "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
    "7": 0x1A, "8": 0x1C, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25,
    "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E, ",": 0x2B, ".": 0x2F,
]
let spaceCode: UInt16 = 0x31, returnCode: UInt16 = 0x24, escapeCode: UInt16 = 0x35, tabCode: UInt16 = 0x30
let deleteCode: UInt16 = 0x33, leftShiftCode: UInt16 = 0x38, leftOptionCode: UInt16 = 0x3A

final class Harness: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var textView: NSTextView!
    var failures = 0
    var originalSource: String?
    /// Window is key (normal desktop): dispatch through NSApp like real typing. Otherwise (e.g. the
    /// screen is locked) hand events to the text view, which forwards them to its input context.
    var dispatchThroughApp = true

    func check(_ ok: Bool, _ message: String) {
        print("\(ok ? "✓" : "✗") \(message)")
        fflush(stdout)
        if !ok { failures += 1 }
    }

    func note(_ message: String) {
        print("  \(message)")
        fflush(stdout)
    }

    // MARK: - Text view state

    var marked: String {
        guard textView.hasMarkedText() else { return "" }
        return (textView.string as NSString).substring(with: textView.markedRange())
    }

    /// Document text without the marked (still composing) part.
    var committed: String {
        let text = textView.string as NSString
        guard textView.hasMarkedText() else { return text as String }
        return text.replacingCharacters(in: textView.markedRange(), with: "")
    }

    // MARK: - Events

    func pump(_ seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        repeat {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01),
                                           inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
        } while Date() < until
    }

    @discardableResult
    func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { return false }
            pump(0.05)
        }
        return true
    }

    func dispatch(_ event: NSEvent) {
        if dispatchThroughApp {
            NSApp.sendEvent(event)
        } else {
            switch event.type {
            case .keyDown: textView.keyDown(with: event)
            case .keyUp: textView.keyUp(with: event)
            case .flagsChanged: textView.flagsChanged(with: event)
            default: break
            }
        }
    }

    /// Key events are built from CGEvents, like the system's own: NSEvent.keyEvent(…) events are
    /// handed straight to the text view and never reach the input method (verified on macOS 27).
    let eventSource = CGEventSource(stateID: .hidSystemState)

    func cgFlags(_ flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var out: CGEventFlags = []
        if flags.contains(.shift) { out.insert(.maskShift) }
        if flags.contains(.control) { out.insert(.maskControl) }
        if flags.contains(.option) { out.insert(.maskAlternate) }
        if flags.contains(.command) { out.insert(.maskCommand) }
        return out
    }

    func key(_ characters: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
        for down in [true, false] {
            guard let cg = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down) else { continue }
            // Keep the event's own flags (e.g. non-coalesced); only the modifier bits are replaced.
            var eventFlags = cg.flags
            eventFlags.subtract([.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskAlphaShift])
            cg.flags = eventFlags.union(cgFlags(flags))
            if let event = NSEvent(cgEvent: cg) { dispatch(event) }
        }
        pump(0.04)
    }

    func type(_ text: String) {
        for ch in text { key(String(ch), keyCodes[ch] ?? 0) }
    }

    func space(_ flags: NSEvent.ModifierFlags = []) { key(" ", spaceCode, flags) }
    func enter() { key("\r", returnCode) }
    func escape() { key("\u{1B}", escapeCode) }
    func backspace() { key("\u{7F}", deleteCode) }

    static func hasLatinLetter(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.isASCII && $0.properties.isAlphabetic }
    }

    /// The marked text after the command ("improve › 我今天" → "我今天": the input method shows a picked command
    /// without its "@", and a "›" after it).
    var afterCommand: String {
        let text = marked
        guard let arrow = text.range(of: " › ") else { return text }
        return String(text[arrow.upperBound...])
    }

    /// The text without punctuation and spaces: a version that only re-punctuates the sentence says the same.
    static func wording(_ s: String) -> String { s.filter { !$0.isPunctuation && !$0.isWhitespace } }

    /// Space until no pinyin is left after the command (long input may need more than one pick).
    func confirmAll() {
        for _ in 0..<5 {
            space()
            _ = waitUntil(2) { !Self.hasLatinLetter(self.afterCommand) }
            if !Self.hasLatinLetter(afterCommand) { return }
        }
    }

    /// "@", the first letters of a command and Tab: the palette picks it ("@i" → "@improve ", shown "improve › ").
    func command(_ prefix: String) {
        key("@", keyCodes["2"]!, .shift)
        type(prefix)
        key("\t", tabCode)
    }

    /// Shift pressed and released on its own (built from CGEvents, like the system's own events).
    func tapShift() {
        for down in [true, false] {
            guard let cg = CGEvent(keyboardEventSource: eventSource, virtualKey: leftShiftCode, keyDown: down) else { return }
            cg.type = .flagsChanged
            cg.flags = down ? .maskShift : []
            if let event = NSEvent(cgEvent: cg) { dispatch(event) }
            pump(0.05)
        }
    }

    /// Left Option pressed and released on its own, with the left-Option device bit as the system sets it.
    func tapOption() {
        for down in [true, false] {
            guard let cg = CGEvent(keyboardEventSource: eventSource, virtualKey: leftOptionCode, keyDown: down) else { return }
            cg.type = .flagsChanged
            cg.flags = down ? [.maskAlternate, CGEventFlags(rawValue: 0x20)] : []  // NX_DEVICELALTKEYMASK
            if let event = NSEvent(cgEvent: cg) { dispatch(event) }
            pump(0.05)
        }
    }

    /// The input method's action key (config `actionKey`): Return unless set otherwise.
    lazy var actionKey = configValue("actionKey") as? String ?? "enter"

    /// Presses the action key: runs the action on the sentence (converting pinyin still being typed).
    func act() {
        switch actionKey {
        case "optionTap": tapOption()
        case "optionSpace": space(.option)
        case "space": space()
        default: enter()
        }
    }

    /// The command as typed, without AI: ⇧Return (Return alone runs it, whatever the action key).
    func asTyped() { key("\r", returnCode, .shift) }

    /// Clears everything (used between steps so one failure doesn't cascade). Two Escapes take the
    /// input method from any state back to idle (level two → draft → nothing).
    func reset() {
        if textView.hasMarkedText() {
            escape()
            escape()
            if textView.hasMarkedText() { textView.unmarkText() }
        }
        pump(0.1)
    }

    static func hasHan(_ s: String) -> Bool { s.unicodeScalars.contains { $0.properties.isIdeographic } }
    static func looksEnglish(_ s: String) -> Bool {
        !s.isEmpty && !hasHan(s) && s.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.isASCII }.count >= 3
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 240, y: 420, width: 760, height: 240),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AllInOneIME real-app test"
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        textView = NSTextView(frame: scroll.bounds)
        textView.autoresizingMask = [.width]
        textView.font = .systemFont(ofSize: 18)
        textView.isRichText = false
        // Keep AppKit from rewriting what the input method inserts.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        scroll.documentView = textView
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window.makeFirstResponder(textView)

        // Safety net if something hangs. TIS may only be used on the main thread, so the input
        // source is restored afterwards by `RealTest --restore-input-source` (run by make).
        DispatchQueue.global().asyncAfter(deadline: .now() + 300) {
            print("✗ watchdog: test took too long")
            print("REALTEST FAILED (timeout)")
            fflush(stdout)
            exit(3)
        }
        DispatchQueue.main.async { self.run() }
    }

    func finish() -> Never {
        reset()
        restoreConfig()
        if let extensionFolder { try? FileManager.default.removeItem(at: extensionFolder) }
        if let originalSource {
            selectInputSource(originalSource)
            pump(0.3)
            check(currentInputSourceID() == originalSource, "input source restored to \(originalSource)")
        }
        let png = window.contentView.flatMap { view -> Data? in
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep.representation(using: .png, properties: [:])
        }
        let out = outputDirectory
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        if let png, (try? png.write(to: out.appendingPathComponent("textview.png"))) != nil {
            note("text view snapshot: \(out.path)/textview.png")
        }
        print("--- document ---\n\(textView.string)\n----------------")
        print(failures == 0 ? "REALTEST PASSED" : "REALTEST FAILED (\(failures))")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Test

    func run() {
        // While the lock screen is up, macOS routes no app's keys to input methods (verified: keys go
        // straight into the text view and the input method never sees them), so the test can't run.
        if screenIsLocked() {
            print("✗ the screen is locked: unlock the Mac, then run `make realtest` again")
            print("REALTEST BLOCKED (screen locked)")
            fflush(stdout)
            exit(4)
        }
        if !window.isKeyWindow {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            _ = waitUntil(3) { self.window.isKeyWindow }
        }
        note("app active: \(NSApp.isActive), window key: \(window.isKeyWindow), "
             + "text view first responder: \(window.firstResponder === textView)")
        if !window.isKeyWindow {
            dispatchThroughApp = false
            note("window is not key; delivering keys to the text view directly")
        }
        originalSource = currentInputSourceID()
        if let originalSource {
            try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try? originalSource.write(to: originalSourceFile, atomically: true, encoding: .utf8)
        }
        note("input source before: \(originalSource ?? "?")")
        let secure = (CGSessionCopyCurrentDictionary() as? [String: Any])?["kCGSSessionSecureInputPID"]
        note("secure input: \(IsSecureEventInputEnabled() ? "ON (pid \(secure ?? "?")) — translations will be refused" : "off")")

        // The test's own settings, whatever the user's (theirs come back after: `restoreConfig`): Chinese first, so it
        // starts in pinyin; results inserted at once, not typed out; @improve polishes without translating, and
        // Chinese translates into English. None of the user's script extensions is offered: they run programs of
        // their own.
        check(setConfig {
            $0["inputLanguages"] = ["zh", "en"]
            $0["defaultInput"] = "zh"
            $0["typeOut"] = false
            $0["improveTranslates"] = false
            $0["outputLanguages"] = ["en", "zh"]
            $0["outputLanguage"] = "en"
            $0["extensionFolders"] = [String]()
            $0["findRaycastScripts"] = false
            // In a column (horizontal is the default): the panel checks below expect it; `horizontalAndReport` tries the row.
            $0["candidateLayout"] = "vertical"
        }, "config file readable, to set the test's languages")

        guard let context = textView.inputContext else {
            check(false, "text view has an input context")
            finish()
        }
        context.activate()
        context.selectedKeyboardInputSource = imeID
        pump(0.5)
        if context.selectedKeyboardInputSource != imeID { selectInputSource(imeID); pump(0.5) }
        check(context.selectedKeyboardInputSource == imeID,
              "AllInOneIME selected (context: \(context.selectedKeyboardInputSource ?? "nil"), system: \(currentInputSourceID() ?? "nil"))")
        // The input method takes the settings when a text field becomes active: this one again, now that they're the
        // test's (an input method already running would keep the user's, typing results out letter by letter).
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(0.8)

        // Warm-up: the first keys start the input method process (and wait for its dictionaries), until "a" is
        // pinyin. The test's config starts it in Chinese; should a field still be in another input language, Shift
        // goes on through them (a key going straight in while the dictionaries load: Shift does nothing yet).
        var reachable = false
        var shifts = 0
        let warmStart = Date()
        while Date().timeIntervalSince(warmStart) < 25 {
            let before = committed
            type("a")
            let answered = waitUntil(3) { !self.marked.isEmpty || self.committed != before }
            if answered, marked == "a" {
                reachable = true
                escape()
                break
            }
            if !marked.isEmpty { escape() } else if committed != before { backspace() }
            if answered, imeIsRunning(), shifts < 4 {
                tapShift()
                shifts += 1
            }
            pump(1)
        }
        check(reachable, String(format: "input method answers (%.1fs, process running: %@)",
                                Date().timeIntervalSince(warmStart), imeIsRunning() ? "yes" : "no"))
        guard reachable else { finish() }
        textView.string = ""

        // 1. Level one: local pinyin; without a command Space inserts the Chinese, like any input method.
        print("— level one: pinyin")
        type("nihao")
        check(waitUntil(3) { self.marked.replacingOccurrences(of: " ", with: "") == "nihao" },
              "pinyin is marked inline (\(marked))")
        _ = waitUntil(2) { !imePanelFrames().isEmpty }
        let panels = imePanelFrames()
        if let caret = Optional(textView.firstRect(forCharacterRange: textView.markedRange(), actualRange: nil)),
           let panel = panels.first {
            let below = panel.maxY <= caret.minY + 1 && caret.minY - panel.maxY < 40
            let aligned = abs(panel.minX - caret.minX) < 120
            check(below && aligned, "candidate panel sits under the caret (panel \(panel.integral), caret \(caret.integral))")
        } else {
            note("candidate panel not on screen (\(panels.count) windows; expected while the screen is locked)")
        }
        space()
        check(waitUntil(3) { self.committed == "你好" && self.marked.isEmpty }, "Space inserts 你好 (document: '\(committed)')")

        // 2. Keys the input method doesn't need still reach the app.
        print("— pass-through")
        key(",", keyCodes[","]!)
        check(waitUntil(2) { self.committed == "你好，" }, "',' types a Chinese comma")
        enter()
        check(waitUntil(2) { self.committed == "你好，\n" }, "Enter with nothing pending makes a new line")
        type("ceshi")
        _ = waitUntil(2) { !self.marked.isEmpty }
        escape()
        check(waitUntil(2) { self.marked.isEmpty && self.committed == "你好，\n" }, "Esc cancels pinyin")
        reset()

        // 3. Level two: the action key on a finished @improve sentence polishes it, in Chinese (the language it
        //    was written in); Space inserts the first version.
        print("— level two: @improve polishes (live Bedrock, key: \(actionKey))")
        textView.string = ""
        command("i")
        check(waitUntil(2) { self.marked == "improve › " }, "@i Tab picks @improve (marked: '\(marked)')")
        type("wojintianyoudianbushufu")
        _ = waitUntil(3) { self.marked != "improve › " }
        confirmAll()
        check(waitUntil(3) { Self.hasHan(self.afterCommand) && !Self.hasLatinLetter(self.afterCommand) },
              "sentence confirmed (marked: \(marked))")
        let sentence = afterCommand.trimmingCharacters(in: .whitespaces)
        let started = Date()
        act()
        let polishedChinese = waitUntil(20) {
            if self.committed.isEmpty { self.space() }  // ignored until the first version is complete
            return !self.committed.isEmpty
        }
        let version = committed
        check(polishedChinese && Self.hasHan(version) && !Self.hasLatinLetter(version) && marked.isEmpty
              && Self.wording(version) != Self.wording(sentence),
              String(format: "Space inserts a Chinese version, worded anew, after %.1fs: '%@' (from '%@')",
                     Date().timeIntervalSince(started), version, sentence))
        reset()

        // 4. @translate translates into English (the test's output languages: English, Chinese), and a digit picks
        //    another version. With ⌥Space or a tap of ⌥ the key goes right on the pinyin (it is converted first);
        //    with Space the sentence is confirmed first.
        print("— level two: @translate, digit 2")
        textView.string = ""
        command("tr")
        check(waitUntil(2) { self.marked == "translate › " }, "@tr Tab picks @translate (marked: '\(marked)')")
        type("zhegexiangmudejindutaimanle")
        _ = waitUntil(3) { self.marked != "translate › " }
        if actionKey == "space" { confirmAll() }
        act()
        check(waitUntil(3) { Self.hasHan(self.afterCommand) && !Self.hasLatinLetter(self.afterCommand) },
              "sentence converted and sent (\(marked))")
        let picked = waitUntil(20) {
            if self.committed.isEmpty { self.key("2", keyCodes["2"]!); self.pump(0.3) }
            return !self.committed.isEmpty
        }
        check(picked && Self.looksEnglish(committed) && marked.isEmpty, "digit 2 inserts an English version: '\(committed)'")
        reset()

        // 5. In level two, 0 keeps the Chinese and Esc goes back to the draft.
        print("— level two: 0 / Esc")
        textView.string = ""
        command("i")
        type("nihao")
        space()
        act()
        key("0", keyCodes["0"]!)
        check(waitUntil(3) { self.committed == "你好" && self.marked.isEmpty }, "0 inserts the Chinese original")
        command("i")
        type("nihao")
        space()
        act()
        escape()
        check(waitUntil(3) { self.marked == "improve › 你好" && self.committed == "你好" }, "Esc returns to the draft")
        type("ma")
        space()
        check(waitUntil(3) { self.afterCommand.hasPrefix("你好") && self.afterCommand.count == 3
                             && Self.hasHan(String(self.afterCommand.suffix(1))) },
              "typing continues the sentence (\(marked))")
        let continued = "@improve " + afterCommand  // as typed: the command with its "@"
        asTyped()
        check(waitUntil(3) { self.committed == "你好" + continued && self.marked.isEmpty },
              "⇧Return inserts it as typed (document: '\(committed)')")
        reset()

        // 6. ⇧Space is Space: it picks the candidate, and with nothing pending the app types a space.
        print("— ⇧Space")
        textView.string = ""
        type("nihao")
        space(.shift)
        check(waitUntil(3) { self.committed == "你好" && self.marked.isEmpty }, "⇧Space picks 你好, like Space")
        space(.shift)
        check(waitUntil(2) { self.committed == "你好 " && self.marked.isEmpty },
              "with nothing pending, ⇧Space types a space ('\(committed)')")
        reset()

        // 7. Shift alone switches to English and back. English letters go straight in; after
        //    @improve they collect into the command and the action key polishes them.
        print("— Shift: English / Chinese")
        textView.string = ""
        tapShift()
        type("abc")
        check(waitUntil(2) { self.committed == "abc" && self.marked.isEmpty }, "after Shift, letters are typed as English ('\(committed)')")
        // Dead keys: macOS doesn't compose them for an input method; it does (US layout: ⌥E then E).
        key("", keyCodes["e"]!, .option)
        type("e")
        check(waitUntil(2) { self.committed == "abcé" && self.marked.isEmpty }, "⌥E E types é ('\(committed)')")
        command("i")
        type("caf")
        key("", keyCodes["e"]!, .option)
        type("e")
        check(waitUntil(2) { self.marked.hasSuffix(" café") }, "⌥E E types é in a command's text (\(marked))")
        reset()
        print("— English @improve (live Bedrock)")
        textView.string = ""
        command("i")
        let words = ["this", "is", "a", "blocker", "bug", "your", "team", "need", "fix", "it", "asap"]
        for word in words {
            type(word)
            space()
        }
        check(waitUntil(2) { self.marked == "improve › " + words.joined(separator: " ") + " " }, "sentence drafted (\(marked))")
        let polishStarted = Date()
        act()
        let polished = waitUntil(20) {
            if self.committed.isEmpty { self.space() }  // ignored until the first version is complete
            return !self.committed.isEmpty
        }
        check(polished && Self.looksEnglish(committed) && committed != words.joined(separator: " ") && marked.isEmpty,
              String(format: "the action key polishes, Space inserts after %.1fs: '%@'", Date().timeIntervalSince(polishStarted), committed))
        textView.string = ""
        tapShift()
        type("ni")
        check(waitUntil(2) { !self.marked.isEmpty }, "after Shift again, pinyin input is back (marked: \(marked))")
        reset()

        selectionCommands()
        horizontalAndReport()
        extensions()
        redaction()
        frenchAndKorean()
        finish()
    }

    /// 6a. Commands on the selected text: part of the text in the text view selected, "@improve" is written in the
    ///     candidate panel while the text view stays as it was, the part still selected (pinyin too); Esc (in the draft,
    ///     and after level two) and ⇧Return leave it so; the action key works on it, and the first version picked
    ///     replaces exactly the selection (live Bedrock). A selection moved meanwhile gives the command up.
    func selectionCommands() {
        print("— commands on the selected text (live Bedrock)")
        let text = "Dear team, this sentance have a error. Thanks!"
        let part = "this sentance have a error."
        let range = (text as NSString).range(of: part)
        /// The candidate panel is up (one of the input method's windows, not the menu bar icon).
        func panelShown() -> Bool {
            let top = NSScreen.screens.first.map { $0.frame.maxY - 40 } ?? .greatestFiniteMagnitude
            return imePanelFrames().contains { $0.maxY < top }
        }
        func select() {
            reset()
            // A command still written in the panel (a check failed): nothing marked for `reset` to see.
            if panelShown() { escape(); escape() }
            textView.string = text
            textView.setSelectedRange(range)
            pump(0.2)
        }
        /// The text view as it was, the part still selected, nothing marked.
        func untouched() -> Bool { textView.string == text && textView.selectedRange() == range && !textView.hasMarkedText() }
        select()
        command("i")
        pump(0.4)
        check(untouched() && panelShown(),
              "@improve on part of the text: the text view unchanged, the part still selected, the command in the panel")
        escape()
        check(waitUntil(2) { untouched() }, "Esc: the text and its selection as they were ('\(textView.string)', \(textView.selectedRange()))")

        select()
        command("i")
        type("nihao")
        pump(0.3)
        check(untouched() && panelShown(), "pinyin in the command's text: in the panel, the text view still untouched")
        space()
        escape()
        check(waitUntil(2) { untouched() }, "Space picks 你好 into the command, Esc gives it up: as it was")

        select()
        command("i")
        asTyped()
        check(waitUntil(2) { untouched() }, "⇧Return inserts nothing: no @improve over the selection ('\(textView.string)')")

        select()
        command("i")
        act()
        pump(0.5)
        escape()
        check(waitUntil(2) { untouched() && panelShown() }, "Esc in level two goes back to the command, the text untouched")
        escape()
        check(waitUntil(2) { untouched() }, "Esc again: the text and its selection as they were")

        select()
        command("i")
        let started = Date()
        act()
        let picked = waitUntil(25) {
            if self.textView.string == text { self.space() }  // ignored until the first version is complete
            return self.textView.string != text
        }
        let result = textView.string
        let middle = result.hasPrefix("Dear team, ") && result.hasSuffix(" Thanks!") ? String(result.dropFirst(11).dropLast(8)) : ""
        check(picked && !middle.isEmpty && middle != part && Self.looksEnglish(middle) && !result.contains("improve")
              && !textView.hasMarkedText(),
              String(format: "the first version replaces exactly the selection, after %.1fs: '%@'", Date().timeIntervalSince(started), result))

        // The selection moved while the command is written (a click): it's given up, and the key types as usual.
        select()
        command("i")
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        pump(0.2)
        type("a")
        check(waitUntil(2) { self.marked == "a" && self.committed == String(text.dropFirst(4)) },
              "a selection moved meanwhile gives the command up; the next key types as usual ('\(committed)' + '\(marked)')")
        reset()
        textView.string = ""
    }

    /// 6b. Candidates in a row (`candidateLayout`): the panel is one line (shorter than the same candidates in a column,
    ///     under 120 pt, wider than tall), and → moves the highlight, so Space inserts the second candidate. On today's date ("rq", rime-ice's Lua), so no word is learned in the user's
    ///     dictionary. Then `@reportissue`: the action key shows what the page would hold, and Esc goes back; the page
    ///     is never opened (⏎ isn't pressed on it).
    func horizontalAndReport() {
        print("— candidates in a row, @reportissue's preview")
        // The same candidates in a column first (the test's config leaves the layout as the user has it: set it).
        _ = setConfig { $0["candidateLayout"] = "vertical" }
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(0.8)
        textView.string = ""
        type("rq")
        _ = waitUntil(2) { !imePanelFrames().isEmpty }
        let column = imePanelFrames().first
        reset()
        textView.string = ""
        guard setConfig({ $0["candidateLayout"] = "horizontal" }) else {
            check(false, "config file readable, to lay the candidates out in a row")
            return
        }
        // The text field again: the input method reads the layout when a field becomes active.
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(0.8)
        textView.string = ""
        type("rq")
        _ = waitUntil(2) { !imePanelFrames().isEmpty }
        if let panel = imePanelFrames().first {
            // A line of cells and the footer: shorter than two rows of a column (under 120 pt), wider than tall, and
            // shorter than the same candidates in a column.
            check(panel.width > panel.height && panel.height < 120 && column.map { panel.height < $0.height } != false,
                  "the candidates are in a row (panel \(panel.integral); in a column \(column.map { "\($0.integral)" } ?? "-"))")
        } else {
            note("candidate panel not on screen (expected while the screen is locked)")
        }
        key("", 0x7C)  // →
        space()
        check(waitUntil(2) { self.committed.contains("/") && self.marked.isEmpty },
              "→ then Space inserts the second candidate, today's date with slashes ('\(committed)')")
        reset()
        textView.string = ""

        // @reportissue: the action key shows the issue first; Esc goes back to it, a second Esc clears it.
        command("reporti")
        check(waitUntil(2) { self.marked == "reportissue › " }, "@reporti Tab picks @reportissue (\(marked))")
        let before = imePanelFrames().first?.height ?? 0
        act()
        pump(0.6)
        let after = imePanelFrames().first?.height ?? 0
        check(marked == "reportissue › " && committed.isEmpty && (before == 0 || after > before),
              "the action key shows what the issue holds, nothing opened or typed (panel \(Int(before)) → \(Int(after)) high)")
        escape()
        check(waitUntil(2) { self.marked == "reportissue › " }, "Esc goes back to the title (\(marked))")
        escape()
        check(waitUntil(2) { self.marked.isEmpty && self.committed.isEmpty }, "Esc again clears it ('\(committed)')")
        reset()
        textView.string = ""
        _ = setConfig { $0["candidateLayout"] = "vertical" }
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(0.8)
    }

    /// 7a. Hiding sensitive information (`redaction` on in the test's config): `@improve` on a selected sentence with
    ///     an email and a phone number (live). The version picked replaces it with the real values in it, no
    ///     placeholder left ("[EMAIL_1]" is what the model saw).
    func redaction() {
        print("— hiding sensitive information from the AI (live)")
        let before = configValue("redaction")
        guard setConfig({ $0["redaction"] = ["enabled": true] }) else {
            check(false, "config file readable, to turn on hiding sensitive information")
            return
        }
        defer { _ = setConfig { $0["redaction"] = before } }
        // The text field again: the input method reads the settings when a field becomes active.
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(0.8)
        let email = "rt.tester@example.com", phone = "555-123-4567"
        let text = "pls tell \(email) the meeting moved, or call \(phone) tomorow"
        reset()
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        pump(0.2)
        command("i")
        let started = Date()
        act()
        let picked = waitUntil(25) {
            if self.textView.string == text { self.space() }  // ignored until the first version is complete
            return self.textView.string != text
        }
        let result = textView.string
        check(picked && result.contains(email) && result.contains(phone) && !result.contains("[EMAIL") && !result.contains("[PHONE")
              && !result.contains("improve") && !textView.hasMarkedText(),
              String(format: "the version picked has the real email and number back, after %.1fs: '%@'", Date().timeIntervalSince(started), result))
        reset()
        textView.string = ""
    }

    /// The script extensions made for the test (in a temporary folder), removed when it ends.
    var extensionFolder: URL?

    /// What `@rttypo` prints, typed out with typos (`typeOutMistakes`): long enough for a few.
    static let typoSentence = "Thanks for the quick reply, I will look into the report tomorrow morning and write back "
        + "before lunch. The team has been busy with the release this week, but this one matters, so we will make "
        + "time for it and keep you posted on what we find."

    /// Whether the text view held other than the start of `typoSentence` while it was typed out (a typo).
    var typoSeen = false

    /// 7. Script extensions from a temporary folder the test's config points at (no network, no model): a list shows
    ///    its rows as the command is picked and the action key inserts the one highlighted; a command that takes no
    ///    input is only completed by Tab and runs on the action key; what it prints is inserted, or typed out with
    ///    typos fixed on the way.
    func extensions() {
        print("— script extensions (a temporary folder)")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-realtest-\(UUID().uuidString)")
        extensionFolder = folder
        let scripts = [
            "rtlist.sh": "# @allinoneime.output list\n# @allinoneime.input optional\n"
                + #"printf '{"items": [{"title": "Row one", "arg": "rt-row-one"}, {"title": "Row two", "arg": "rt-row-two"}]}\n'"#,
            "rtecho.sh": "# @allinoneime.input none\necho rt-insert-ok",
            "rttypo.sh": "# @allinoneime.input none\necho '\(Self.typoSentence)'",
        ]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, body) in scripts {
                let file = folder.appendingPathComponent(name)
                try Data(("#!/bin/bash\n# @allinoneime.schemaVersion 1\n" + body + "\n").utf8).write(to: file)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            }
        } catch {
            check(false, "the test's extensions written (\(error))")
            return
        }
        guard setConfig({ $0["extensionFolders"] = [folder.path] }) else {
            check(false, "config file readable, to add the test's extension folder")
            return
        }
        // The text field again: the input method reads its extensions in the background when a field becomes active.
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(1.5)
        textView.string = ""

        // A list: rows as soon as it's picked (its text is optional); ↓ and the action key insert the second row.
        command("rtlist")
        check(waitUntil(2) { self.marked == "rtlist › " }, "@rtlist is picked from the list (\(marked))")
        pump(1)  // its run, after its query delay
        key("", 0x7D)  // ↓
        act()
        check(waitUntil(3) { self.committed == "rt-row-two" && self.marked.isEmpty },
              "the list's rows are shown, and the action key inserts the one picked ('\(committed)')")
        reset()
        textView.string = ""

        // No input: Tab only completes it; the action key runs it; its output is inserted.
        command("rtecho")
        pump(0.5)
        check(marked == "rtecho › " && committed.isEmpty, "Tab completes a command that takes no input, without running it (\(marked))")
        act()
        let inserted = waitUntil(5) {
            if self.committed.isEmpty, !self.marked.isEmpty { self.space() }  // ignored until its output is in
            return self.committed == "rt-insert-ok"
        }
        check(inserted && marked.isEmpty, "the action key runs it, and what it printed is inserted ('\(committed)')")
        reset()
        textView.string = ""
        typedOutWithTypos()
    }

    /// 7b. Typed out with typos fixed on the way (`typeOutMistakes`), at the fastest pace: the input method takes each
    ///     typo back by its range in this NSTextView, and the text ends up exactly what the script printed.
    func typedOutWithTypos() {
        guard setConfig({ $0["typeOut"] = true; $0["typeOutRate"] = 40; $0["typeOutMistakes"] = true }) else {
            check(false, "config file readable, to type results out with typos")
            return
        }
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(0.8)
        textView.string = ""
        typoSeen = false
        // This app forgotten among those that couldn't take a typo back (a failed run before would keep typos off).
        let ime = UserDefaults(suiteName: imeID)
        let noTypos = "typeOutNoTyposApps"
        let me = Bundle.main.bundleIdentifier ?? "com.aipinyin.realtest"
        ime?.set((ime?.stringArray(forKey: noTypos) ?? []).filter { $0 != me }, forKey: noTypos)
        let observer = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView,
                                                              queue: nil) { [weak self] _ in
            guard let self, !Self.typoSentence.hasPrefix(self.committed) else { return }
            self.typoSeen = true
        }
        command("rttypo")
        pump(0.5)
        act()
        let typed = waitUntil(40) {
            if self.committed.isEmpty, !self.marked.isEmpty { self.space() }  // ignored until its output is in
            return self.committed == Self.typoSentence
        }
        pump(0.3)
        NotificationCenter.default.removeObserver(observer)
        check(typed && committed == Self.typoSentence && marked.isEmpty,
              "typed out with typos on, the text is exactly what it printed ('\(committed)')")
        check(typoSeen, "…with typos in the text view on the way, each taken back")
        ime?.synchronize()
        check(!(UserDefaults(suiteName: imeID)?.stringArray(forKey: noTypos) ?? []).contains(me),
              "…and the NSTextView isn't remembered as a field that can't take typos back")
        reset()
        textView.string = ""
        _ = setConfig { $0["typeOut"] = false; $0["typeOutMistakes"] = false }
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(0.8)
    }

    /// 8. French types with its own keyboard layout (AZERTY), dead keys too; Korean composes Hangul; Shift goes
    ///    through the input languages in order. The config gets them for the test and is restored after.
    func frenchAndKorean() {
        print("— French (AZERTY), Korean, Hindi")
        guard addTestLanguages() else {
            check(false, "config file readable, to add French and Korean for the test")
            return
        }
        // The text field again, so the input method reads the languages and starts in French (the default).
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(0.8)
        textView.string = ""
        type("q")
        check(waitUntil(2) { self.committed == "a" }, "in French the A key of AZERTY types 'a' ('\(committed)')")
        key("", 0x21)  // AZERTY's ^ dead key, where [ is on a US keyboard
        type("e")
        check(waitUntil(2) { self.committed == "aê" && self.marked.isEmpty }, "^ then e types ê ('\(committed)')")
        tapShift()
        textView.string = ""
        type("gksrmf")
        check(waitUntil(2) { self.committed == "한" && self.marked == "글" }, "after Shift, Korean: g k s r m f → 한 and 글 being typed ('\(committed)' + '\(marked)')")
        space()
        check(waitUntil(2) { self.committed == "한글 " && self.marked.isEmpty }, "Space finishes 글 and types a space ('\(committed)')")
        command("tr")
        type("dkssud")
        check(waitUntil(2) { self.marked.hasSuffix(" 안녕") }, "Hangul in a command's text (\(marked))")
        reset()
        // @translate from Korean into the test's output languages, English and Chinese: a line in each, 1 the English
        // and 2 the Chinese (live model output: only which script each is in is checked).
        for (digit, english) in [("1", true), ("2", false)] {
            textView.string = ""
            command("tr")
            for (index, word) in ["dhsmf", "ahadl", "wha", "dks", "whgdkdy"].enumerated() {  // 오늘 몸이 좀 안 좋아요
                if index > 0 { space() }
                type(word)
            }
            check(waitUntil(2) { self.afterCommand == "오늘 몸이 좀 안 좋아요" }, "Korean sentence after @translate (\(marked))")
            if actionKey == "space" { space() }  // Space after a word is a space; the second runs it
            act()
            let inserted = waitUntil(20) {
                if self.committed.isEmpty { self.key(digit, keyCodes[Character(digit)]!); self.pump(0.3) }
                return !self.committed.isEmpty
            }
            let line = committed
            check(inserted && marked.isEmpty
                  && (english ? Self.looksEnglish(line) : Self.hasHan(line) && !Self.hasLatinLetter(line) && !line.contains("요")),
                  "@translate from Korean: \(digit) inserts the \(english ? "English" : "Chinese") line: '\(line)'")
            reset()
        }
        tapShift()
        textView.string = ""
        type("namaste")
        check(waitUntil(2) { self.marked == "नमस्ते" }, "Shift again: Hindi, namaste shows नमस्ते (marked: \(marked))")
        space()
        check(waitUntil(2) { self.committed == "नमस्ते " && self.marked.isEmpty }, "Space inserts नमस्ते and a space ('\(committed)')")
        type("hai")
        key(".", keyCodes["."]!)
        check(waitUntil(2) { self.committed == "नमस्ते है।" }, "hai then . types है। ('\(committed)')")
        reset()
        tapShift()
        textView.string = ""
        type("ni")
        check(waitUntil(2) { !self.marked.isEmpty }, "Shift again: pinyin (marked: \(marked))")
        reset()
        tapShift()
        textView.string = ""
        type("q")
        check(waitUntil(2) { self.committed == "q" }, "Shift again: English, the system's layout ('\(committed)')")
        restoreConfig()
    }

    /// The user's config, kept while the test changes it (`restoreConfig`; a backup file too).
    var savedConfig: Data?
    static let configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/allinoneime/config.json")

    /// Changes the config for the test. The user's own is kept the first time (`restoreConfig` puts it back).
    func setConfig(_ change: (inout [String: Any]) -> Void) -> Bool {
        guard let data = try? Data(contentsOf: Self.configURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if savedConfig == nil {
            savedConfig = data
            try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try? data.write(to: configBackupFile)
        }
        change(&json)
        guard let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return false }
        return (try? out.write(to: Self.configURL, options: .atomic)) != nil
    }

    func addTestLanguages() -> Bool {
        setConfig {
            $0["inputLanguages"] = ["fr", "ko", "hi", "zh", "en"]
            $0["defaultInput"] = "fr"
            $0["keyboardLayouts"] = [String: String]()
        }
    }

    func restoreConfig() {
        guard let savedConfig else { return }
        try? savedConfig.write(to: Self.configURL, options: .atomic)
        try? FileManager.default.removeItem(at: configBackupFile)
        self.savedConfig = nil
    }

    /// A value from the input method's config file (nil if unset or the file is missing).
    func configValue(_ key: String) -> Any? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/allinoneime/config.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json[key]
    }
}

// Helper modes, run as a plain command (used by the Makefile and the unlock watcher).
switch CommandLine.arguments.dropFirst().first {
case "--is-locked":
    print(screenIsLocked() ? "true" : "false")
    exit(0)
case "--restore-input-source":
    // And the config, if the test was stopped while it had changed it.
    if let backup = try? Data(contentsOf: configBackupFile) {
        try? backup.write(to: Harness.configURL, options: .atomic)
        try? FileManager.default.removeItem(at: configBackupFile)
        print("config restored")
    }
    // Backup for when the test couldn't restore it itself (watchdog timeout or crash).
    if let original = try? String(contentsOf: originalSourceFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines), !original.isEmpty, currentInputSourceID() != original {
        print(selectInputSource(original) ? "input source restored to \(original)" : "could not restore \(original)")
    }
    exit(0)
default:
    break
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let harness = Harness()
app.delegate = harness
app.run()
