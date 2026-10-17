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
#if canImport(FoundationModels)
import FoundationModels
#endif

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

/// The input method's own log of its AI requests as it is written (`log stream`): "conversion 12 started (…)", then
/// "conversion 12 done in 1.20s cache=false" once all its results are in, which the panel doesn't show from outside
/// (its frames can stay the same while a rewrite is still being written, or be complete at once from the cache).
final class RequestLog: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var lines: [String] = []
    private var partial = ""

    /// Streaming (it stops by itself after a few minutes, should the test end without stopping it); nil if it can't.
    static func start(prefix: String = "conversion ") -> RequestLog? {
        let log = RequestLog()
        log.process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        log.process.arguments = ["stream", "--style", "compact", "--timeout", "3m", "--predicate",
                                 "subsystem == \"\(imeID)\" AND eventMessage BEGINSWITH \"\(prefix)\""]
        let pipe = Pipe()
        log.process.standardOutput = pipe
        log.process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak log] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }  // it stopped
            guard let log, let text = String(data: data, encoding: .utf8) else { return }
            log.lock.withLock {
                let parts = (log.partial + text).components(separatedBy: "\n")
                log.partial = parts.last ?? ""
                log.lines += parts.dropLast()
            }
        }
        do { try log.process.run() } catch { return nil }
        return log
    }

    /// Lines so far (the first is `log stream`'s own header, once it streams).
    var count: Int { lock.withLock { lines.count } }

    /// The first request started after line `mark`, once it is done: whether it came from the cache (nil until then).
    func done(after mark: Int) -> (id: Int, cached: Bool)? {
        let new = lock.withLock { Array(lines.dropFirst(mark)) }
        guard let id = new.lazy.compactMap({ Self.request($0, "started") }).first,
              let line = new.first(where: { Self.request($0, "done") == id }) else { return nil }
        return (id, line.contains("cache=true"))
    }

    /// Whether a request started after line `mark` says `text` ("@question round 2").
    func started(after mark: Int, saying text: String) -> Bool {
        lock.withLock { lines.dropFirst(mark).contains { $0.contains("] conversion ") && $0.contains(" started (") && $0.contains(text) } }
    }

    /// The request id in "conversion 12 <word> …".
    private static func request(_ line: String, _ word: String) -> Int? {
        guard let range = line.range(of: "] conversion ") else { return nil }
        let rest = line[range.upperBound...], digits = rest.prefix(while: \.isNumber)
        return rest.dropFirst(digits.count).hasPrefix(" \(word)") ? Int(digits) : nil
    }

    /// The lines after `mark` holding `text`.
    func lines(after mark: Int, containing text: String) -> [String] {
        lock.withLock { lines.dropFirst(mark).filter { $0.contains(text) } }
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }
}

let keyCodes: [Character: UInt16] = [
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
    "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
    "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
    "7": 0x1A, "8": 0x1C, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25,
    "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E, ",": 0x2B, ".": 0x2F, " ": 0x31,
]
let spaceCode: UInt16 = 0x31, returnCode: UInt16 = 0x24, escapeCode: UInt16 = 0x35, tabCode: UInt16 = 0x30
let deleteCode: UInt16 = 0x33, leftShiftCode: UInt16 = 0x38, leftOptionCode: UInt16 = 0x3A

final class Harness: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var textView: NSTextView!
    var failures = 0
    /// Checks that counted, and the ones skipped, by reason (`section`).
    var passed = 0
    var skipped: [String: Int] = [:]
    /// Why the checks from here on are skipped (nil: they count), and how many counted in a section (none while some
    /// were skipped: nothing that types through the input method ran).
    var skipping: String?
    var inSection = false
    var checkedInSections = 0
    var originalSource: String?
    /// Window is key (normal desktop): dispatch through NSApp like real typing. Otherwise (e.g. the
    /// screen is locked) hand events to the text view, which forwards them to its input context.
    var dispatchThroughApp = true

    func check(_ ok: Bool, _ message: String) {
        if let skipping {
            print("– \(message) — skipped: \(skipping)")
            skipped[skipping, default: 0] += 1
        } else {
            print("\(ok ? "✓" : "✗") \(message)")
            if ok { passed += 1 } else { failures += 1 }
            if inSection { checkedInSections += 1 }
        }
        fflush(stdout)
    }

    // MARK: - Secure input

    static let secureInputSkip = "secure input (screen locked?)"
    /// How long a section waits for secure input held elsewhere to go, and how long the run waits for it in all (the
    /// watchdog's six minutes hold a test of about two, and this).
    let secureInputWait: TimeInterval = 30
    var secureInputWaitLeft: TimeInterval = 90
    /// It was still on when a section stopped waiting: the next ones don't wait again while it stays.
    var secureInputStayed = false

    /// Secure input held by another process (a password field, a terminal's Secure Keyboard Entry) refuses every
    /// request; on the lock screen no keys reach an input method at all.
    func secureInputHeld() -> Bool { IsSecureEventInputEnabled() || screenIsLocked() }

    /// Whether secure input is off, or goes within `secureInputWait` seconds (not waited for again while it stays on).
    func secureInputGoes() -> Bool {
        guard secureInputHeld() else {
            secureInputStayed = false
            return true
        }
        guard !secureInputStayed, secureInputWaitLeft > 0 else { return false }
        let wait = min(secureInputWait, secureInputWaitLeft)
        let pid = (CGSessionCopyCurrentDictionary() as? [String: Any])?["kCGSSessionSecureInputPID"]
        note("secure input is on (pid \(pid ?? "?"))\(screenIsLocked() ? ", the screen is locked" : ""): waiting up to \(Int(wait)) s for it to go")
        let started = Date()
        while secureInputHeld(), Date().timeIntervalSince(started) < wait { pump(0.2) }
        secureInputWaitLeft -= Date().timeIntervalSince(started)
        secureInputStayed = secureInputHeld()
        return !secureInputStayed
    }

    /// Starts a section (they all type through the input method): while secure input stays on, its checks are skipped,
    /// not failed. One that counts after a skipped one starts from an empty text view.
    func section(_ title: String) {
        print("— \(title)")
        fflush(stdout)
        inSection = true
        let wasSkipping = skipping != nil
        skipping = nil
        if !secureInputGoes() { skipping = Self.secureInputSkip }
        if let skipping { note("skipped: \(skipping)") }
        if wasSkipping, skipping == nil {
            reset()
            textView.string = ""
        }
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
        // A skipped section counts nothing: it runs on without waiting for what won't come.
        let deadline = Date().addingTimeInterval(skipping == nil ? timeout : min(timeout, 0.3))
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

    /// Types `text` key by key (a space with the Space key). A character with no key in `keyCodes` is a bug in the test:
    /// it fails the run (key code 0 would have typed an "a" in its place, as it did for the spaces of "candidates in a row").
    func type(_ text: String) {
        for ch in text {
            guard let code = keyCodes[ch] else {
                print("✗ type(\"\(text)\"): no key for '\(ch)' in keyCodes")
                fflush(stdout)
                failures += 1
                continue
            }
            key(String(ch), code)
        }
    }

    func space(_ flags: NSEvent.ModifierFlags = []) { key(" ", spaceCode, flags) }
    func enter() { key("\r", returnCode) }
    /// ⇧⏎: sends a follow-up typed on AI results (a refine, an @question conversation's next question).
    func shiftEnter() { key("\r", returnCode, .shift) }
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

    /// Whether letters go straight into the text view (English) or into pinyin, asked by typing "a" into an empty text
    /// view and taking it back; nil if neither happened. Leaves the text view empty.
    func typesEnglish() -> Bool? {
        textView.string = ""
        type("a")
        _ = waitUntil(2) { !self.marked.isEmpty || !self.committed.isEmpty }
        let english: Bool? = !marked.isEmpty ? false : committed == "a" ? true : nil
        reset()
        textView.string = ""
        return english
    }

    /// English or Chinese (pinyin) as asked: Shift only when the field isn't in it already (a tap toggles, so it isn't
    /// taken on trust). Whether the field is in it now.
    func switchTo(english: Bool) -> Bool {
        for _ in 0..<3 {
            guard let now = typesEnglish() else { return false }
            if now == english { return true }
            tapShift()
            pump(0.3)
        }
        return typesEnglish() == english
    }

    /// The candidate panel is up (one of the input method's windows, not the menu bar icon).
    func imePanelShown() -> Bool {
        let top = NSScreen.screens.first.map { $0.frame.maxY - 40 } ?? .greatestFiniteMagnitude
        return imePanelFrames().contains { $0.maxY < top }
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
    /// Hiragana or katakana (half-width too): Japanese, which shares its Han characters with Chinese.
    static func hasKana(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x31F0...0x31FF).contains($0.value) || (0xFF66...0xFF9D).contains($0.value) }
    }
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
        DispatchQueue.global().asyncAfter(deadline: .now() + 360) {
            print("✗ watchdog: test took too long")
            print("REALTEST FAILED (timeout)")
            fflush(stdout)
            exit(3)
        }
        DispatchQueue.main.async { self.run() }
    }

    func finish() -> Never {
        (skipping, inSection) = (nil, false)
        reset()
        finishing = true
        restoreConfig()
        restoreQuestions()
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
        // Only failures fail the run; skipped checks never make it pass.
        let skippedCount = skipped.values.reduce(0, +)
        let counts = "\(passed) passed, \(failures) failed, \(skippedCount) skipped"
        let reasons = skipped.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        if failures > 0 {
            print("REALTEST FAILED (\(failures)): \(counts)\(reasons.isEmpty ? "" : " (\(reasons))")")
        } else if skippedCount == 0 {
            print("REALTEST PASSED: \(counts)")
        } else if checkedInSections == 0 {
            print("Everything that types through the input method was skipped (\(reasons)): this run doesn't show it works.")
            print("REALTEST SKIPPED: \(counts) (\(reasons))")
        } else {
            print("REALTEST INCOMPLETE: \(counts) (\(reasons))")
        }
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Test

    func run() {
        // While the lock screen is up, macOS routes no app's keys to input methods (verified: keys go
        // straight into the text view and the input method never sees them), so the test can't run: a while for it
        // to be unlocked, else nothing runs (not a failure; the unlock watcher waits for the next unlock).
        if !secureInputGoes(), screenIsLocked() {
            print("The screen is locked: nothing ran. Unlock the Mac, then run `make realtest` again.")
            print("REALTEST BLOCKED (screen locked): 0 passed, 0 failed, everything skipped")
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

        // The test's own settings, whatever the user's (theirs come back after: `restoreConfig`): Amazon Bedrock (the
        // live checks expect its answers, not an on-device model's or another provider's), with the user's profile,
        // region and model; Chinese first, so it starts in pinyin; results inserted at once, not typed out; @improve
        // polishes without translating, and Chinese translates into English. None of the user's script extensions is
        // offered: they run programs of their own.
        check(setConfig {
            $0["provider"] = "bedrock"
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
        // Secure input held by a process macOS can't name stops composing everywhere: then nothing can be checked.
        if !reachable, secureInputHeld() { skipping = Self.secureInputSkip }
        check(reachable, String(format: "input method answers (%.1fs, process running: %@)",
                                Date().timeIntervalSince(warmStart), imeIsRunning() ? "yes" : "no"))
        guard reachable else { finish() }
        textView.string = ""

        // 1. Level one: local pinyin; without a command Space inserts the Chinese, like any input method.
        section("level one: pinyin")
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
        section("pass-through")
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
        section("level two: @improve polishes (live Bedrock, key: \(actionKey))")
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
        section("level two: @translate, digit 2")
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
        section("level two: 0 / Esc")
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
        section("⇧Space")
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
        section("Shift: English / Chinese")
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
        section("English @improve (live Bedrock)")
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

        appleModel()
        selectionCommands()
        refineResults()
        horizontalAndReport()
        atAfterAWord()
        recentQuestions()
        questionConversation()
        extensions()
        perAppSettings()
        redaction()
        aiConfig()
        doctor()
        frenchAndKorean()
        finish()
    }

    /// 6a. Commands on the selected text: part of the text in the text view selected, "@improve" is written in the
    ///     candidate panel while the text view stays as it was, the part still selected (pinyin too); Esc (in the draft,
    ///     and after level two) and ⇧Return leave it so; the action key works on it, and the first version picked
    ///     replaces exactly the selection (live Bedrock). A selection moved meanwhile gives the command up.
    func selectionCommands() {
        section("commands on the selected text (live Bedrock)")
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

    /// 6a'. Refining the results: @improve a long English sentence and, once all its results are in (the input
    ///     method's log says so, `RequestLog`), pick row 1 (V1); the same sentence again (the cache answers at once,
    ///     all in), "shorter" typed while the results are up and ⇧⏎ asks again with them as context; the draft stays as
    ///     it was (the letters went to the refine line, not the sentence), and 1 inserts the refined version, which is
    ///     shorter than V1 (live Bedrock).
    func refineResults() {
        section("refine the results: shorter (live Bedrock)")
        reset()
        textView.string = ""
        tapShift()  // English: the sentence and the instruction are typed as letters
        let words = ["i", "wanted", "to", "let", "you", "know", "that", "the", "meeting", "we", "planned", "for", "tomorrow",
                     "morning", "has", "been", "moved", "to", "the", "afternoon", "because", "the", "big", "room", "was", "not",
                     "free", "and", "several", "people", "could", "not", "join", "that", "early"]
        let sentence = words.joined(separator: " ")
        /// "@improve" and the sentence, marked as typed.
        func draft() -> Bool {
            command("i")
            for word in words {
                type(word)
                space()
            }
            return waitUntil(2) { self.marked == "improve › " + sentence + " " }
        }
        /// The panel's frames stay the same for `quiet` seconds, within `timeout`.
        func settled(_ timeout: TimeInterval, quiet: TimeInterval = 1) -> Bool {
            var last = imePanelFrames(), since = Date()
            return waitUntil(timeout) {
                let now = imePanelFrames()
                if now != last { last = now; since = Date() }
                return !now.isEmpty && Date().timeIntervalSince(since) >= quiet
            }
        }
        /// The request the action key starts, once all its results are in (from the cache or not; nil: not within
        /// `timeout`). Without the input method's log: the panel unchanged for a few seconds (a rewrite only shows once
        /// it is complete, so it can stay the same for a second while one is still being written).
        let requests = RequestLog.start()
        _ = waitUntil(5) { (requests?.count ?? 1) > 0 }  // its header: streaming
        func actUntilAllIn(_ timeout: TimeInterval) -> Bool? {
            let mark = requests?.count ?? 0
            act()
            guard let requests else { return settled(timeout, quiet: 3) ? false : nil }
            var done: (id: Int, cached: Bool)?
            _ = waitUntil(timeout) { done = requests.done(after: mark); return done != nil }
            pump(0.3)  // its last rows shown
            return done?.cached
        }
        /// The end of the section, also when it gives up: no log, nothing marked (the text view can't have its text
        /// taken away under the marked text), Chinese again.
        func endSection() {
            requests?.stop()
            reset()
            textView.string = ""
            tapShift()  // back to Chinese
        }
        check(draft(), "sentence drafted in English (\(marked))")
        // All the results first: V1 inserted while the rest still streams stops the request, and nothing is kept for
        // the same sentence again (from an earlier run of the test, it may be kept already).
        let firstIn = actUntilAllIn(40)
        let improved = firstIn != nil && waitUntil(5) {
            if self.committed.isEmpty { self.space() }
            return !self.committed.isEmpty
        }
        let first = committed, kept = firstIn == true ? " (from the cache)" : ""
        check(improved && Self.looksEnglish(first) && marked.isEmpty,
              "@improve inserts its first version, once all its results are in\(kept): '\(first)'")
        guard improved, marked.isEmpty else { return endSection() }
        textView.string = ""
        check(draft(), "the same sentence again")
        // From the cache: all in at once. A live request (nothing kept) would still be streaming, and the letters
        // typed next would go to the sentence.
        let started = Date()
        let againIn = actUntilAllIn(10)
        check(requests == nil ? againIn != nil : againIn == true,
              String(format: "its results are all in at once, from the cache (%.1fs%@)", Date().timeIntervalSince(started),
                     requests == nil ? "; no log of the input method's: only the panel settled" : ""))
        requests?.stop()
        type("shorter")
        pump(0.3)
        check(marked == "improve › " + sentence + " ", "'shorter' goes to the refine line: the sentence is as it was (\(marked))")
        shiftEnter()  // ⇧⏎ sends a refine; ⏎ would insert the version selected
        let refining = Date()
        let picked = waitUntil(25) {
            if self.committed.isEmpty { self.key("1", keyCodes["1"]!); self.pump(0.3) }  // ignored until row 1 is complete
            return !self.committed.isEmpty
        }
        let refined = committed
        check(picked && Self.looksEnglish(refined) && marked.isEmpty && refined != first && refined.count < first.count,
              String(format: "⇧⏎ refines and 1 inserts the refined version after %.1fs: '%@' (%d characters, was %d)",
                     Date().timeIntervalSince(refining), refined, refined.count, first.count))
        endSection()
    }

    /// 5b. Apple Intelligence on this Mac (`provider: "apple"`), where its model is available: @improve on English and on
    ///     pinyin with the on-device model, through the installed input method; then the test's provider (Bedrock) again.
    func appleModel() {
        var available = false
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { available = SystemLanguageModel.default.isAvailable }
        #endif
        section("Apple Intelligence on this Mac (on-device model)")
        guard available else {
            note("skipped: Apple Intelligence isn't available on this Mac")
            return
        }
        let provider = configValue("provider")
        guard setConfig({ $0["provider"] = "apple" }) else {
            check(false, "config file readable, to choose Apple Intelligence")
            return
        }
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(0.8)

        textView.string = ""
        tapShift()
        command("i")
        let words = ["i", "think", "we", "should", "moved", "the", "meeting", "to", "next", "week"]
        for word in words {
            type(word)
            space()
        }
        check(waitUntil(2) { self.marked == "improve › " + words.joined(separator: " ") + " " }, "sentence drafted (\(marked))")
        var started = Date()
        act()
        let polished = waitUntil(20) {
            if self.committed.isEmpty { self.space() }  // ignored until the first version is complete
            return !self.committed.isEmpty
        }
        check(polished && Self.looksEnglish(committed) && committed != words.joined(separator: " ") && marked.isEmpty,
              String(format: "on-device @improve: Space inserts a polished English version after %.1fs: '%@'",
                     Date().timeIntervalSince(started), committed))
        reset()
        textView.string = ""
        tapShift()

        command("i")
        type("mingtiankaihuiwokenengyaochidao")
        _ = waitUntil(3) { self.marked != "improve › " }
        confirmAll()
        check(waitUntil(3) { Self.hasHan(self.afterCommand) && !Self.hasLatinLetter(self.afterCommand) },
              "sentence confirmed (marked: \(marked))")
        started = Date()
        act()
        let chinese = waitUntil(20) {
            if self.committed.isEmpty { self.space() }
            return !self.committed.isEmpty
        }
        check(chinese && Self.hasHan(committed) && marked.isEmpty,
              String(format: "on-device @improve on pinyin: a Chinese version after %.1fs: '%@'",
                     Date().timeIntervalSince(started), committed))
        reset()
        textView.string = ""
        _ = setConfig { $0["provider"] = provider }  // none: removed again
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(0.8)
    }

    /// 6b. Candidates in a row (`candidateLayout`): the panel is one line (shorter than the same candidates in a column,
    ///     under 120 pt, wider than tall), and → moves the highlight, so Space inserts the second candidate. On today's date ("rq", rime-ice's Lua), so no word is learned in the user's
    ///     dictionary. Then `@reportissue`: the action key shows what the page would hold, and Esc goes back; the page
    ///     is never opened (⏎ isn't pressed on it).
    func horizontalAndReport() {
        section("candidates in a row, @reportissue's preview")
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

    /// 6d. "@" right after a word is text (an email address, `ssh user@host`): in English "bob@example.com" goes in as
    ///     typed, no command list. After a space or at the start "@" opens the list, and → on it leaves the "@" as typed
    ///     and the key moves the caret on, as before. (A terminal's → only ends the list, the "@" going in after it: the
    ///     self-test checks that on a fake Ghostty line; this is a text view.) The address is typed once no panel of the
    ///     input method is up, and the list is watched for from the "@" on, key by key.
    func atAfterAWord() {
        section("@ after a word, → on a lone @")
        textView.string = ""
        guard switchTo(english: true) else {
            check(false, "the field types English letters, for the address")
            return
        }
        let at = { self.key("@", keyCodes["2"]!, .shift) }
        // Every panel of the input method down first: the Shift's mode notice (英 / English, about 1.3 s) was still up
        // when the address had been typed, and read as the list.
        check(waitUntil(5) { !self.imePanelShown() }, "no input method panel up before the address")
        // The list must never show: watched between "@" and the next key, and after each key after it.
        var listShown = false, markedSeen = ""
        func watch(_ seconds: TimeInterval) {
            let until = Date().addingTimeInterval(seconds)
            repeat {
                listShown = listShown || imePanelShown()
                if markedSeen.isEmpty { markedSeen = marked }
                pump(0.02)
            } while Date() < until
        }
        type("bob")
        at()
        watch(0.4)
        let afterAt = committed
        for ch in "example.com" {
            type(String(ch))
            watch(0.05)
        }
        check(waitUntil(2) { self.committed == "bob@example.com" } && marked.isEmpty && !listShown && markedSeen.isEmpty,
              "an email address goes in as typed, the list never shown ('\(committed)', '\(afterAt)' after the @; "
                + "marked '\(marked)'\(markedSeen.isEmpty ? "" : ", '\(markedSeen)' on the way")\(listShown ? ", a panel shown" : ""))")
        space()
        at()
        check(waitUntil(2) { self.marked == "@" }, "after a space, @ opens the list (marked '\(marked)')")
        reset()
        // At the start of "ab" (← ← take the caret there): "@", then → puts the "@" in and moves the caret past "a".
        textView.string = ""
        type("ab")
        key("", 0x7B)  // ←
        key("", 0x7B)
        at()
        check(waitUntil(2) { self.marked == "@" }, "at the start of the text @ opens the list (marked '\(marked)')")
        key("", 0x7C)  // →
        check(waitUntil(2) { self.committed == "@ab" && self.marked.isEmpty } && waitUntil(2) { !self.imePanelShown() },
              "→ leaves the @ as typed and the list closes ('\(committed)')")
        type("x")
        check(waitUntil(2) { self.committed == "@axb" }, "…and the caret moved on: x lands after the a ('\(committed)')")
        reset()
        textView.string = ""
        _ = switchTo(english: false)
    }

    /// 7a. Hiding sensitive information (`redaction` on in the test's config): `@improve` on a selected sentence with
    ///     an email and a phone number (live). The version picked replaces it with the real values in it, no
    ///     placeholder left ("[EMAIL_1]" is what the model saw).
    func redaction() {
        section("hiding sensitive information from the AI (live)")
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
        section("script extensions (a temporary folder)")
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
        // Until a fix is seen taken in a field, only a wrong letter is tried there (`TypeOut.Typing.probe`): a letter
        // or space typed twice, or a word typed again, goes in plainly. In about 1 run in 45 of this sentence no slip
        // is a wrong letter, and none shows: up to three runs (each starts unproven), all typed exactly.
        var typed = true
        var runs = 0
        while runs < 3, !typoSeen {
            runs += 1
            textView.string = ""
            command("rttypo")
            pump(0.5)
            act()
            typed = waitUntil(40) {
                if self.committed.isEmpty, !self.marked.isEmpty { self.space() }  // ignored until its output is in
                return self.committed == Self.typoSentence
            } && marked.isEmpty && typed
            pump(0.3)
            reset()
        }
        NotificationCenter.default.removeObserver(observer)
        check(typed && committed == Self.typoSentence && marked.isEmpty,
              "typed out with typos on, the text is exactly what it printed ('\(committed)')")
        check(typoSeen, "…with typos in the text view on the way, each taken back (\(runs) run\(runs == 1 ? "" : "s"))")
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

    /// 7c. Settings for this app (`appProfiles`, by this harness's bundle id): its text field starts in English though
    ///     Chinese is the default, and @improve sends nothing (no AI), its draft kept; without them, pinyin again.
    func perAppSettings() {
        section("per-app settings (this app: English, no AI)")
        let me = Bundle.main.bundleIdentifier ?? "com.aipinyin.realtest"
        guard setConfig({ $0["appProfiles"] = [me: ["inputLanguage": "en", "noAI": true]] }) else {
            check(false, "config file readable, to give this app its own settings")
            return
        }
        // The text field again: the input method applies the app's starting language when a field becomes active.
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(0.8)
        textView.string = ""
        type("hi")
        check(waitUntil(2) { self.committed == "hi" && self.marked.isEmpty }, "this app's field starts in English ('\(committed)')")
        textView.string = ""
        command("i")
        type("hello")
        check(waitUntil(2) { self.afterCommand == "hello" }, "@improve with its text (\(marked))")
        act()
        pump(2)
        check(marked == "improve › hello" && committed.isEmpty,
              "the action key sends nothing to the AI here: the draft stays, nothing inserted (\(marked))")
        reset()
        textView.string = ""
        guard setConfig({ $0["appProfiles"] = [String: Any]() }) else { return }
        window.makeFirstResponder(nil)
        pump(0.5)
        window.makeFirstResponder(textView)
        pump(0.8)
        type("a")
        check(waitUntil(2) { self.marked == "a" }, "without them, the field starts in pinyin again (marked: \(marked))")
        reset()
        textView.string = ""
    }

    /// 7d. `@config` (live: the on-device model if this Mac has it, else the configured provider): "candidates in a row"
    ///     shows its preview, ⏎ applies it to the config file (the test's config has them in a column) and nothing is
    ///     inserted; ⌘Z on the confirmation puts the column back (else `@config undo`). The config is the test's own.
    ///     English is asked of the field before the sentence is typed, and a draft that isn't exactly the sentence is
    ///     given up unsent; ⏎ only once the preview is up (the input method's log), then once. When the on-device model
    ///     makes nothing of the sentence ("notUnderstood"), it is asked once more, plainly ("candidate layout horizontal"),
    ///     and the check says so; a second notUnderstood fails.
    func aiConfig() {
        section("@config: candidates in a row, and undo (live)")
        guard setConfig({ $0["candidateLayout"] = "vertical" }) else {
            check(false, "config file readable, to lay the candidates out in a column first")
            return
        }
        reset()
        textView.string = ""
        func layout() -> String? { configValue("candidateLayout") as? String }
        // English (the sentence is typed as letters), asked of the field, not taken on trust from a Shift tap.
        let wasEnglish = typesEnglish()
        guard switchTo(english: true) else {
            check(false, "@config: letters can't be typed as English here (nothing sent)")
            return
        }
        defer { _ = switchTo(english: wasEnglish ?? false) }
        let requests = RequestLog.start(prefix: "@config")
        _ = waitUntil(5) { (requests?.count ?? 1) > 0 }  // its header: streaming
        defer { requests?.stop() }
        guard let requests else {
            check(false, "@config: the input method's log can't be read, so the preview can't be waited for")
            reset()
            textView.string = ""
            return
        }
        // Where the lines of the request sent last start (`ask`).
        var mark = requests.count
        func logged(_ text: String) -> String? { requests.lines(after: mark, containing: text).first }
        // Or it failed ("@config N failed: …", "@config N: the answer wasn't readable"): no use waiting the 60 s out.
        func noPreview() -> String? { logged(": no preview") ?? logged(" failed: ") ?? logged("wasn't readable") }
        func shown(_ line: String?) -> String { (line ?? "no answer within 60 s").components(separatedBy: "] ").last ?? "-" }
        /// "@config <sentence>" drafted and sent; then the preview's rows (the input method logs "@config N: … rows"), or
        /// why there are none ("@config N: no preview (…)"), waited for up to 60 s: the on-device model may take a while to
        /// load the first time. ⏎ while it's pending does nothing. False: the draft wasn't exactly the sentence (✗, and
        /// nothing sent: anything else, a letter lost or pinyin, would be sent as it is).
        func ask(_ sentence: String) -> Bool {
            command("conf")
            type(sentence)
            let drafted = waitUntil(2) { self.marked == "config › " + sentence }
            check(drafted, "@config drafted (\(marked))")
            guard drafted else { return false }
            mark = requests.count
            act()
            _ = waitUntil(60) { logged(" rows, ") != nil || noPreview() != nil }
            return true
        }
        let started = Date()
        guard ask("candidates in a row") else {
            reset()
            textView.string = ""
            return
        }
        // The small on-device model now and then makes nothing of the sentence ("notUnderstood"): once, the same request
        // said plainly. A second notUnderstood fails like any other answer without a preview.
        var retried: String?
        if logged(" rows, ") == nil, let first = noPreview(), first.contains("notUnderstood") {
            retried = shown(first)
            note("@config made nothing of \"candidates in a row\" (\(retried ?? "-")): once more, as \"candidate layout horizontal\"")
            reset()
            textView.string = ""
            guard ask("candidate layout horizontal") else {
                reset()
                textView.string = ""
                return
            }
        }
        let previewed = logged(" rows, ")
        check(previewed != nil,
              String(format: "@config shows its preview after %.1fs (%@)%@", Date().timeIntervalSince(started),
                     shown(previewed ?? noPreview()),
                     retried.map { ", on the second try, \"candidate layout horizontal\" (the first: \($0))" } ?? ""))
        guard previewed != nil else {
            reset()
            textView.string = ""
            return
        }
        pump(0.3)  // the rows drawn
        enter()
        let applied = waitUntil(10) { logged("changes applied") != nil && layout() == "horizontal" }
        check(applied && committed.isEmpty,
              String(format: "⏎ once applies it: candidateLayout = horizontal after %.1fs; nothing inserted ('%@')",
                     Date().timeIntervalSince(started), committed))
        guard applied else {
            reset()
            textView.string = ""
            return
        }
        key("z", keyCodes["z"]!, .command)
        var undone = waitUntil(5) { layout() == "vertical" }
        if !undone {
            note("⌘Z found the confirmation closed: @config undo instead")
            reset()
            command("conf")
            type("undo")
            act()
            undone = waitUntil(5) { layout() == "vertical" }
        }
        check(undone && committed.isEmpty && marked.isEmpty, "undo puts the column back (\(layout() ?? "-")), nothing inserted")
        reset()
        textView.string = ""
    }

    /// 7e. `@doctor`: its checks run on this Mac (nothing sent) and find the input method installed and enabled (✓, read
    ///     from its log: the panel can't be read from outside); nothing is inserted, Esc closes it.
    func doctor() {
        section("@doctor: the input method is fine")
        reset()
        textView.string = ""
        let requests = RequestLog.start(prefix: "doctor ")
        _ = waitUntil(5) { (requests?.count ?? 1) > 0 }  // its header: streaming
        tapShift()  // English
        command("doc")
        check(waitUntil(2) { self.marked == "doctor › " }, "@doctor drafted (\(marked))")
        let mark = requests?.count ?? 0
        act()
        let done = waitUntil(30) { !(requests?.lines(after: mark, containing: " done: ").isEmpty ?? true) }
        let line = requests?.lines(after: mark, containing: " done: ").first ?? ""
        check(done && line.contains("inputMethod=ok") && committed.isEmpty,
              "@doctor shows ✓ for the input method, nothing inserted (\(line.components(separatedBy: "] ").last ?? "no log"))")
        requests?.stop()
        escape()
        pump(0.3)
        check(marked.isEmpty && committed.isEmpty, "Esc closes it")
        reset()
        textView.string = ""
        tapShift()  // back to Chinese
    }

    /// 8. French types with its own keyboard layout (AZERTY), dead keys too; Korean composes Hangul; Shift goes
    ///    through the input languages in order. The config gets them for the section, and the test's languages back after.
    func frenchAndKorean() {
        section("French (AZERTY), Korean, Hindi")
        let before = configValues(["inputLanguages", "defaultInput", "keyboardLayouts"])
        guard addTestLanguages() else {
            check(false, "config file readable, to add French and Korean for the test")
            return
        }
        defer { putBack(before) }
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
            // The Chinese line: Han characters, and no kana (a Japanese line has Han characters too).
            check(inserted && marked.isEmpty
                  && (english ? Self.looksEnglish(line) : Self.hasHan(line) && !Self.hasKana(line) && !Self.hasLatinLetter(line) && !line.contains("요")),
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
    }

    /// 6c. `@question`'s recent questions (live Bedrock): a question asked is kept in the file; "@question " lists it,
    ///     1 shows its saved answer at once (nothing is asked) and Space inserts the same text; ⌘R asks it again for a fresh
    ///     answer, which takes its place. The user's own recent questions are put back afterwards (the input method reads
    ///     the file again once it changed).
    func recentQuestions() {
        section("@question: recent questions (live Bedrock)")
        _ = setConfig { $0["rememberQuestions"] = true }
        savedQuestions = (try? Data(contentsOf: Self.questionsURL)) ?? Data()  // empty: there was no file
        try? FileManager.default.removeItem(at: Self.questionsURL)
        defer { restoreQuestions() }
        func kept() -> String { (try? Data(contentsOf: Self.questionsURL)).map { String(decoding: $0, as: UTF8.self) } ?? "" }
        /// Space until the answer is in (ignored until it is complete).
        func insertAnswer(_ timeout: TimeInterval) -> Bool {
            waitUntil(timeout) {
                if self.committed.isEmpty { self.space() }
                return !self.committed.isEmpty
            }
        }
        reset()
        textView.string = ""
        command("q")
        type("yijiayidengyuji")  // 一加一等于几: what is one plus one
        act()
        let asked = insertAnswer(25)
        let answer = committed
        check(asked && Self.hasHan(answer) && marked.isEmpty, "@question answers, Space inserts it: '\(answer.prefix(40))'")
        check(waitUntil(2) { kept().contains("一加一等于几") }, "the question and its answer are kept in recent-questions.json")

        textView.string = ""
        command("q")
        pump(0.3)
        key("1", keyCodes["1"]!)
        let started = Date()
        let shown = insertAnswer(3)
        check(shown && committed == answer && marked.isEmpty,
              String(format: "1 shows the saved answer at once (%.1fs), Space inserts the same text ('%@')",
                     Date().timeIntervalSince(started), String(committed.prefix(40))))

        textView.string = ""
        command("q")
        pump(0.3)
        key("1", keyCodes["1"]!)
        pump(0.3)
        let before = kept()
        key("r", keyCodes["r"]!, .command)
        let again = insertAnswer(25)
        check(again && Self.hasHan(committed) && marked.isEmpty, "⌘R asks again, Space inserts the fresh answer: '\(committed.prefix(40))'")
        check(waitUntil(2) { kept() != before } && kept().components(separatedBy: "\"question\"").count == 2,
              "the fresh answer takes the old one's place (one question kept)")
        reset()
        textView.string = ""
    }

    /// 6d. An @question conversation (live Bedrock): a question asked, a follow-up typed and sent with ⇧⏎ as round 2 (the
    ///     input method's log says so) while the panel grows; with `questionRounds` 2 in the test's config the row of where
    ///     to go on is then up, and its copy choice (⌘1 here: `questionContinueIn` ["copy", "chatgpt"]) puts the
    ///     conversation on the clipboard in Markdown, nothing inserted. Nothing is handed to Claude or a browser; the
    ///     user's clipboard and the three keys it set are put back, and nothing is kept in the recent questions.
    func questionConversation() {
        section("@question: a conversation (live Bedrock)")
        let before = configValues(["questionRounds", "questionContinueIn", "rememberQuestions"])
        _ = setConfig {
            $0["questionRounds"] = 2
            $0["questionContinueIn"] = ["copy", "chatgpt"]
            $0["rememberQuestions"] = false
        }
        let pasteboard = NSPasteboard.general
        let clipboard = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let clipboard { pasteboard.setString(clipboard, forType: .string) }
            reset()
            textView.string = ""
            tapShift()  // back to Chinese
            putBack(before)  // only these: the rest stays the test's (the user's comes back in `finish`)
        }
        reset()
        textView.string = ""
        pump(1)  // the config read again by the input method
        tapShift()  // English: the questions are typed as letters
        let requests = RequestLog.start()
        _ = waitUntil(5) { (requests?.count ?? 1) > 0 }
        defer { requests?.stop() }
        /// Until the request started after `mark` is done (from the input method's log; without it, the panel settled).
        func answered(after mark: Int, _ timeout: TimeInterval) -> Bool {
            guard let requests else {
                var last = imePanelFrames(), since = Date()
                return waitUntil(timeout) {
                    let now = imePanelFrames()
                    if now != last { last = now; since = Date() }
                    return !now.isEmpty && Date().timeIntervalSince(since) >= 3
                }
            }
            let done = waitUntil(timeout) { requests.done(after: mark) != nil }
            pump(0.5)
            return done
        }
        func height() -> CGFloat { imePanelFrames().map(\.height).max() ?? 0 }
        command("q")
        for (index, word) in ["what", "is", "the", "capital", "of", "france"].enumerated() {
            if index > 0 { space() }
            type(word)
        }
        let first = requests?.count ?? 0
        act()
        check(answered(after: first, 25) && marked.hasPrefix("question › what is the capital of france") && committed.isEmpty,
              "round 1 answered, the panel up (\(marked))")
        let one = height()
        for (index, word) in ["and", "its", "population"].enumerated() {
            if index > 0 { space() }
            type(word)
        }
        pump(0.3)
        check(committed.isEmpty && marked.hasPrefix("question › what is the capital of france"),
              "the follow-up goes to the next question's line, not the text (\(marked))")
        let second = requests?.count ?? 0
        shiftEnter()
        let roundTwo = answered(after: second, 25)
        check(roundTwo && (requests?.started(after: second, saying: "@question round 2") ?? true) && committed.isEmpty,
              "⇧⏎ asks it as round 2 of the conversation")
        let two = height()
        check(two > one, "the panel grows with the conversation (\(Int(one)) → \(Int(two)) points)")
        // Round 2 of 2: where to go on is up; ⌘1, its copy choice, copies the conversation.
        pasteboard.clearContents()
        key("1", keyCodes["1"]!, .command)
        let copied = waitUntil(3) { pasteboard.string(forType: .string)?.contains("**A:**") == true }
        let text = pasteboard.string(forType: .string) ?? ""
        check(copied && text.hasPrefix("**Q:** what is the capital of france") && text.contains("**Q:** and its population")
              && text.components(separatedBy: "**A:** ").count == 3 && committed.isEmpty && marked.isEmpty,
              "after round 2 the hand-off row is up and ⌘1 (copy) puts both rounds on the clipboard, nothing inserted")
    }

    /// The user's recent questions while the test asks its own (`recentQuestions`): empty when there was no file.
    var savedQuestions: Data?
    static let questionsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AllInOneIME/recent-questions.json")

    func restoreQuestions() {
        guard let saved = savedQuestions else { return }
        if saved.isEmpty {
            try? FileManager.default.removeItem(at: Self.questionsURL)
        } else if (try? saved.write(to: Self.questionsURL, options: .atomic)) != nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.questionsURL.path)
        }
        savedQuestions = nil
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

    /// The values `keys` have now (nil: not set), for `putBack` after a section that changes them.
    func configValues(_ keys: [String]) -> [(key: String, value: Any?)] { keys.map { ($0, configValue($0)) } }

    /// Puts back what `configValues` read (a key that wasn't set is removed again); the rest stays the test's.
    func putBack(_ values: [(key: String, value: Any?)]) {
        _ = setConfig { json in for (key, value) in values { json[key] = value } }
    }

    /// Set by `finish`, the only place the user's own config comes back: back any earlier, every section after it would
    /// run on the user's settings (their provider, languages, default input), not the test's.
    var finishing = false

    func restoreConfig() {
        guard finishing else {
            // A bug in the test, not in the input method: fail loudly, whatever the section's state, and keep the test's config.
            print("✗ restoreConfig() before finish(): a section must put back only the keys it changed (`putBack`)")
            fflush(stdout)
            failures += 1
            return
        }
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
