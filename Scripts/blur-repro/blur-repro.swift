// What happens to an open "@" list or unfinished pinyin when a real app's text field loses the focus without a click
// (Core/Tests/AllInOneIMEHostTests/HostKnownIssues.swift `atListLostOnBlur` is the fake hosts' answer; this asks the
// real apps). For each app × way of losing the focus × state it types through the *installed* AllInOneIME, makes the
// field lose the focus, gives it back, and records the field's text before, while typing, after the loss and after the
// focus came back, the input method's windows on screen, and whether what was typed is in its clipboard history;
// a screenshot at each step. Results: OUT/results.md (a table) and OUT/*.png.
//
// Run with Scripts/blur-repro/run.sh (which says what it needs: the screen unlocked, Accessibility and Screen Recording
// for this app). Keys are posted to the session (CGEvent), each only while the app under test is frontmost.
// No AI: every app under test gets `noAI` in the test's config and Autocomplete is off; the user's config and input
// source come back at the end (`--restore OUT` puts them back after a run that was stopped).
import AppKit
import ApplicationServices
import Carbon

let imeID = "com.allinoneime.inputmethod.AllInOneIME"
let arguments = Array(CommandLine.arguments.dropFirst())
let out = URL(fileURLWithPath: arguments.first { !$0.hasPrefix("-") } ?? "/tmp/allinoneime-blur-repro")
let page = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/page.html")
let home = FileManager.default.homeDirectoryForCurrentUser
let configURL = home.appendingPathComponent(".config/allinoneime/config.json")
let historyURL = home.appendingPathComponent("Library/Application Support/AllInOneIME/clipboard-history.json")
let configBackup = out.appendingPathComponent("config.backup.json")
let sourceBackup = out.appendingPathComponent("original-source.txt")

func option(_ name: String) -> String? {
    arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
}

func wait(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

// MARK: - Input source and config (the user's come back at the end)

func currentInputSourceID() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

@discardableResult
func selectInputSource(_ id: String) -> Bool {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
          let source = list.first else { return false }
    return TISSelectInputSource(source) == noErr
}

func setConfig(_ change: (inout [String: Any]) -> Void) -> Bool {
    guard let data = try? Data(contentsOf: configURL),
          var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
    if !FileManager.default.fileExists(atPath: configBackup.path) { try? data.write(to: configBackup) }
    change(&json)
    guard let new = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return false }
    return (try? new.write(to: configURL, options: .atomic)) != nil
}

func restore() {
    if let backup = try? Data(contentsOf: configBackup) {
        try? backup.write(to: configURL, options: .atomic)
        try? FileManager.default.removeItem(at: configBackup)
        print("config restored")
    }
    if let original = try? String(contentsOf: sourceBackup, encoding: .utf8), !original.isEmpty {
        if currentInputSourceID() != original { print(selectInputSource(original) ? "input source restored to \(original)" : "could not restore \(original)") }
        try? FileManager.default.removeItem(at: sourceBackup)
    }
}

// MARK: - Keys, windows, screenshots

let keyCodes: [Character: CGKeyCode] = [
    "a": 0x00, "h": 0x04, "q": 0x0C, "w": 0x0D, "2": 0x13, "o": 0x1F, "i": 0x22, "n": 0x2D, "`": 0x32,
]
let tabCode: CGKeyCode = 0x30, downCode: CGKeyCode = 0x7D

func frontmostID() -> String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

func post(_ code: CGKeyCode, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
        wait(0.03)
    }
    wait(0.09)
}

/// Types into `app` only: false, with nothing more typed, as soon as another app is frontmost.
func type(_ text: String, into app: String) -> Bool {
    for character in text {
        guard frontmostID() == app else { return false }
        if character == "@" { post(0x13, flags: .maskShift) } else if let code = keyCodes[character] { post(code) }
    }
    return true
}

func running(_ id: String) -> NSRunningApplication? { NSRunningApplication.runningApplications(withBundleIdentifier: id).first }

/// The input method's windows on screen (the candidate panel, the "@" list).
func panels() -> Int {
    let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: imeID).map(\.processIdentifier))
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.filter { ($0[kCGWindowOwnerPID as String] as? pid_t).map(pids.contains) == true }.count
}

func screenshot(_ name: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", out.appendingPathComponent(name + ".png").path]
    try? process.run()
    process.waitUntilExit()
}

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

/// The field with the focus in `app` now (kept, and read again after it lost the focus).
func focusedElement(of app: NSRunningApplication) -> AXUIElement? {
    // swiftlint:disable:next force_cast
    attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute).map { $0 as! AXUIElement }
}

/// The page's own account (page.html writes it in its title), whichever of the app's windows has it.
func pageTitle(of app: NSRunningApplication) -> String {
    let windows = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] ?? []
    let titles = windows.compactMap { attribute($0, kAXTitleAttribute) as? String }
    return titles.first { $0.contains("BLUR|") } ?? "(no page title: \(titles))"
}

func inHistory(_ text: String) -> Bool {
    (try? String(contentsOf: historyURL, encoding: .utf8))?.contains("\"\(text)\"") == true
}

// MARK: - The cases

struct Target {
    let name: String, id: String, web: Bool
    var kinds: [String] { ["cmdtab", "otherapp", "window"] + (web ? ["jsfocus", "remove"] : []) }
}

let targets = [
    Target(name: "textedit", id: "com.apple.TextEdit", web: false),
    Target(name: "terminal", id: "com.apple.Terminal", web: false),
    Target(name: "safari", id: "com.apple.Safari", web: true),
    Target(name: "chrome", id: "com.google.Chrome", web: true),
]
/// The state typed: its name, the keys, the input language the app's field starts in.
let states = [(name: "at", keys: "@q", language: "en"), (name: "pinyin", keys: "nihao", language: "zh")]
let other = "com.apple.calculator"

func open(_ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = arguments
    try? process.run()
    process.waitUntilExit()
}

func waitFront(_ id: String, _ seconds: Double = 8) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { if frontmostID() == id { return true }; wait(0.2) }
    return false
}

var rows: [String] = []
var number = 0

/// One case. `field`: "ta"/"ce" for a page's field, "" otherwise.
func run(_ target: Target, kind: String, field: String, state: (name: String, keys: String, language: String)) {
    number += 1
    let label = String(format: "%02d-%@%@-%@-%@", number, target.name, field.isEmpty ? "" : "-" + field, kind, state.name)
    func row(_ cells: [String]) {
        rows.append("| " + ([label] + cells).map { $0.replacingOccurrences(of: "|", with: "¦").replacingOccurrences(of: "\n", with: "⏎") }.joined(separator: " | ") + " |")
        print(rows.last ?? "")
    }
    guard setConfig({
        var profiles = $0["appProfiles"] as? [String: Any] ?? [:]
        profiles[target.id] = ["noAI": true, "inputLanguage": state.language]
        ($0["appProfiles"], $0["autocomplete"], $0["commandTrigger"]) = (profiles, false, "@")
        ($0["inputLanguages"], $0["defaultInput"], $0["typeOut"]) = (["en", "zh"], "en", false)
    }) else { return row(["config not writable"]) }

    // The field, focused by the app itself (a document opened, the page's own focus()): no click.
    if target.web {
        let pageKind = ["jsfocus", "remove"].contains(kind) ? kind : "none"
        open(["-a", target.id == "com.apple.Safari" ? "Safari" : "Google Chrome", page.absoluteString + "?field=\(field)&kind=\(pageKind)&after=4&back=5"])
    } else if target.name == "textedit" {
        let file = out.appendingPathComponent("\(label).txt")
        try? "你好".write(to: file, atomically: true, encoding: .utf8)
        open(["-a", "TextEdit", file.path])
    } else {
        open(["-a", "Terminal", home.path])
    }
    guard waitFront(target.id), let app = running(target.id) else { return row(["the app didn't come to the front"]) }
    wait(2.5)
    var windows = 1
    if kind == "window" {  // a second window of the app, then back to the first: ⌘` is what leaves the field
        post(keyCodes["n"] ?? 0, flags: .maskCommand); wait(1.5)
        post(keyCodes["`"] ?? 0, flags: .maskCommand); wait(1)
        windows = 2
    }
    if target.name == "textedit" { post(downCode, flags: .maskCommand) }  // the caret after 你好
    selectInputSource(imeID)
    wait(1)
    let element = target.web ? nil : focusedElement(of: app)
    func read() -> String {
        if target.web { return pageTitle(of: app) }
        guard let element, let value = attribute(element, kAXValueAttribute) as? String else { return "(unreadable)" }
        // A terminal's is the whole screen: its last line.
        return target.name == "terminal" ? (value.split(separator: "\n").last.map(String.init) ?? "") : value
    }
    let before = read()
    guard frontmostID() == target.id, type(state.keys, into: target.id) else { return row(["another app came to the front: nothing typed"]) }
    wait(1.2)
    let typed = read(), panelsTyped = panels()
    screenshot(label + "-1-typed")

    switch kind {
    case "cmdtab": post(tabCode, flags: .maskCommand)
    case "otherapp": open(["-a", "Calculator"])
    case "window": post(keyCodes["`"] ?? 0, flags: .maskCommand)
    default: wait(4)  // the page's timer, 4 s after the first key
    }
    wait(1.5)
    let after = read(), panelsAfter = panels(), front = frontmostID() ?? "?"
    screenshot(label + "-2-blurred")

    switch kind {
    case "cmdtab", "otherapp": app.activate(); _ = waitFront(target.id)
    case "window": post(keyCodes["`"] ?? 0, flags: .maskCommand)
    default: wait(5)  // the page focuses the field again, 5 s later
    }
    wait(1.5)
    let again = read(), panelsAgain = panels()
    screenshot(label + "-3-refocused")
    row([before, typed, "\(panelsTyped)", after, "\(panelsAfter)", front, again, "\(panelsAgain)", inHistory(state.keys) ? "yes" : "no"])

    // The windows the case opened, closed while the app is still frontmost (TextEdit saves its file in OUT by itself).
    for _ in 0..<windows where frontmostID() == target.id { post(keyCodes["w"] ?? 0, flags: .maskCommand); wait(0.8) }
    if kind == "otherapp" || kind == "cmdtab" { running(other)?.terminate() }
}

// MARK: - Main

if arguments.first == "--restore" { restore(); exit(0) }
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let session = CGSessionCopyCurrentDictionary() as? [String: Any]
if session == nil || (session?["CGSSessionScreenIsLocked"] as? Bool) == true {
    print("BLUR-REPRO BLOCKED: the screen is locked (or this isn't the console's login session)"); exit(2)
}
let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
if !trusted {
    print("BLUR-REPRO BLOCKED: needs Accessibility (System Settings → Privacy & Security → Accessibility → AllInOneIME BlurRepro), then run again"); exit(2)
}
if !CGPreflightScreenCaptureAccess(), !arguments.contains("--no-screenshots") {
    CGRequestScreenCaptureAccess()
    print("BLUR-REPRO BLOCKED: needs Screen Recording for the screenshots (System Settings → Privacy & Security), or pass --no-screenshots"); exit(2)
}
if IsSecureEventInputEnabled() { print("BLUR-REPRO BLOCKED: secure input is on (a password field has the keys)"); exit(2) }
guard let original = currentInputSourceID(), selectInputSource(imeID) else {
    print("BLUR-REPRO BLOCKED: AllInOneIME isn't an enabled input source (make install)"); exit(2)
}
try? original.write(to: sourceBackup, atomically: true, encoding: .utf8)
defer { restore() }

let only = option("--only")?.split(separator: ",").map(String.init)
// ⌘Tab goes to the app used last: Calculator, brought forward once before the cases.
open(["-a", "Calculator"]); wait(1.5)
for target in targets where only?.contains(target.name) ?? true {
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.id) != nil else { print("\(target.name): not installed, skipped"); continue }
    for field in target.web ? ["ta", "ce"] : [""] {
        for kind in target.kinds {
            for state in states { run(target, kind: kind, field: field, state: state) }
        }
    }
}
running(other)?.terminate()

let header = """
    | case | before | typed (while the panel is up) | panels | after the focus loss | panels | frontmost then | after the focus came back | panels | typed text in clipboard history |
    |---|---|---|---|---|---|---|---|---|---|
    """
try? (header + "\n" + rows.joined(separator: "\n") + "\n").write(to: out.appendingPathComponent("results.md"), atomically: true, encoding: .utf8)
print("BLUR-REPRO DONE: \(rows.count) cases, \(out.path)/results.md")
