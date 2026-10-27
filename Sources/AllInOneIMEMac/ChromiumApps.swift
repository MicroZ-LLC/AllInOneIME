import Foundation

/// Apps built on Chromium or Electron (Slack, VS Code, Claude, Chrome, Edge, Brave, Arc …): their text fields are a web
/// page's, and Chromium gives the page a key the input method took as a key down of its own (its keyCode, not 229)
/// unless the field has marked text before or after the key, or more than one character goes in during it with no
/// range. Slack's composer sent its message on a Return that put a suggestion row in, and moved its caret (or the focus)
/// on the ↓ and ↑ that chose one (0.6.7.2's and 0.6.7.3's Electron harness measured it). Only there does the input method
/// keep such a key from the app (`AllInOneIMEInputController.markRow`); other fields (AppKit's, WebKit's) never act on a
/// key the input method took. Told by the app: a Chromium browser known by its bundle id (its web apps too), or a
/// bundle with Electron's, a Chromium browser's or any Chromium or CEF framework in Contents/Frameworks.
public enum ChromiumApps {
    /// Frameworks in an app's Contents/Frameworks that make it one: Electron's and the Chromium Embedded Framework's.
    static let frameworks: Set<String> = ["Electron Framework.framework", "Chromium Embedded Framework.framework"]
    /// What in the name of anything else in Contents/Frameworks (a framework, a library) makes it one too: Chromium's
    /// or the Chromium Embedded Framework's under another name ("CEF.framework", "libcef.dylib"). As written, case and
    /// all: "PlaceFramework" has no CEF in it.
    static let frameworkNameParts = ["Chromium", "CEF", "libcef"]
    /// A Chromium browser's framework, "<name> Framework.framework" or "<name> <channel> Framework.framework" (Google
    /// Chrome's, Microsoft Edge Beta's …), by its name.
    static let browserFrameworks = ["Google Chrome", "Chromium", "Microsoft Edge", "Brave Browser", "Arc", "Vivaldi", "Opera",
                                    "Yandex", "Whale"]

    /// The Chromium browsers by bundle id, their beta, dev and nightly builds too. A web app one of them installed
    /// ("Install page as app") is "<its id>.app.<the app's>".
    public static let browsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.operasoftware.OperaGX",
        "ru.yandex.desktop.yandex-browser", "com.naver.Whale",
    ]

    /// Whether `bundleID` is one of `browsers`, or a web app of one.
    public static func isBrowser(_ bundleID: String) -> Bool {
        browsers.contains(bundleID) || browsers.contains { bundleID.hasPrefix($0 + ".app.") }
    }

    /// Whether the app at `bundle` (its .app) has Electron's or a Chromium framework in Contents/Frameworks: one of
    /// `frameworks`, a Chromium browser's, or one with Chromium or CEF in its name (`frameworkNameParts`).
    public static func hasChromium(bundle: URL) -> Bool {
        let folder = bundle.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        return names.contains { name in
            guard !frameworks.contains(name), !frameworkNameParts.contains(where: { name.contains($0) }) else { return true }
            guard name.hasSuffix(" Framework.framework") else { return false }
            let stem = name.dropLast(" Framework.framework".count)
            return browserFrameworks.contains { stem == $0 || stem.hasPrefix($0 + " ") }
        }
    }

    /// Whether apps are Chromium's or Electron's, by bundle id: a known browser (`isBrowser`), else its bundle
    /// (`hasChromium`), found by `locate` (the app running with that id, else where Launch Services has it); each answer
    /// kept for good. An app not found is no for now, and nothing kept: it is looked for again once `retry` seconds
    /// have gone (`now`, the system's uptime), so an app installed or moved since is told, a key costing no look-up
    /// meanwhile. A field that tells none: no. Any thread.
    public final class Known: @unchecked Sendable {
        /// How long an app not found stays no before it is looked for again.
        public static let retry: TimeInterval = 30
        private let lock = NSLock()
        private var apps: [String: Bool] = [:]
        /// The apps not found, and when each was looked for.
        private var missing: [String: TimeInterval] = [:]
        private let locate: (String) -> URL?
        private let retry: TimeInterval
        private let now: () -> TimeInterval

        public init(retry: TimeInterval = Known.retry, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                    locate: @escaping (String) -> URL?) {
            (self.retry, self.now, self.locate) = (retry, now, locate)
        }

        public func isChromium(_ bundleID: String?) -> Bool {
            guard let bundleID, !bundleID.isEmpty else { return false }
            let time = now()
            let known: Bool? = lock.withLock {
                if let known = apps[bundleID] { return known }
                if let looked = missing[bundleID], time - looked < retry { return false }
                return nil
            }
            if let known { return known }
            let found: Bool
            if ChromiumApps.isBrowser(bundleID) {
                found = true
            } else if let bundle = locate(bundleID) {
                found = ChromiumApps.hasChromium(bundle: bundle)
            } else {
                lock.withLock { missing[bundleID] = time }
                return false
            }
            lock.withLock { (apps[bundleID], missing[bundleID]) = (found, nil) }
            return found
        }
    }
}

extension ChromiumApps {
    /// What a key the input method takes and puts nothing in (↓ ↑ → Esc on the rows, ⌃V opening clipboard history) is
    /// marked with during it in such an app's field, so its page gets the key as the input method's (229) and acts on none
    /// of it (`AllInOneIMEInputController.markBeforeCaret`): text that is there marked in its own place and committed as it
    /// was once the key is done, or a space taken out again.
    public enum KeyMark: Equatable, Sendable {
        /// The selection, its text as read back: committed, it is the same text with the caret after it.
        case selection(NSRange, String)
        /// The character before the caret, whole: a surrogate pair (an emoji), a letter with its accents, an emoji with
        /// its modifiers (the composed character sequence that ends at the caret).
        case character(NSRange, String)
        /// Nothing before the caret (the field's start): a space marked at the caret.
        case space
    }

    /// The most UTF-16 units read back before the caret for the character there: an emoji family takes 11, a region's
    /// flag 14; Chromium's view reads back 100 characters around the selection.
    static let characterWindow = 32

    /// What a key is marked with in a field whose selection (or caret) is `caret`, `read` giving its text in a range back
    /// (nil: it doesn't). Nil where nothing can be marked safely: the field tells no caret, or doesn't read back the
    /// selection or the whole character before the caret (half of one outside the Basic Multilingual Plane reads back as
    /// U+FFFD).
    public static func keyMark(caret: NSRange, read: (NSRange) -> String?) -> KeyMark? {
        guard caret.location != NSNotFound, caret.length != NSNotFound else { return nil }
        if caret.length > 0 {
            guard let text = read(caret), (text as NSString).length == caret.length else { return nil }
            return .selection(caret, text)
        }
        guard caret.location > 0 else { return .space }
        let window = NSRange(location: max(caret.location - characterWindow, 0), length: min(caret.location, characterWindow))
        guard let text = read(window).map({ $0 as NSString }), text.length == window.length else { return nil }
        let last = text.rangeOfComposedCharacterSequence(at: text.length - 1)
        // One that starts where the window does may start further back.
        guard last.location > 0 || window.location == 0 else { return nil }
        let character = text.substring(with: last)
        guard character != "\u{FFFD}" else { return nil }
        return .character(NSRange(location: window.location + last.location, length: last.length), character)
    }
}
