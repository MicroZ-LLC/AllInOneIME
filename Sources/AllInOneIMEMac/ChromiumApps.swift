import Foundation

/// Apps built on Chromium or Electron (Slack, VS Code, Claude, Chrome, Edge, Brave, Arc …): their text fields are a web
/// page's, and Chromium gives the page a key the input method took as a key down of its own (its keyCode, not 229)
/// unless the field has marked text before or after the key, or more than one character goes in during it with no
/// range. Slack's composer sent its message on a Return that put a suggestion row in, and moved its caret (or the focus)
/// on the ↓ and ↑ that chose one (0.6.7.2's and 0.6.7.3's Electron harness measured it). Only there does the input method
/// keep such a key from the app (`AllInOneIMEInputController.markRow`); other fields (AppKit's, WebKit's) never act on a
/// key the input method took. Told by the app: a Chromium browser known by its bundle id (its web apps too), or a
/// bundle with Electron's or a Chromium framework in Contents/Frameworks.
public enum ChromiumApps {
    /// Frameworks in an app's Contents/Frameworks that make it one: Electron's and the Chromium Embedded Framework's.
    static let frameworks: Set<String> = ["Electron Framework.framework", "Chromium Embedded Framework.framework"]
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

    /// Whether the app at `bundle` (its .app) has Electron's or a Chromium framework in Contents/Frameworks.
    public static func hasChromium(bundle: URL) -> Bool {
        let folder = bundle.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        return names.contains { name in
            guard !frameworks.contains(name) else { return true }
            guard name.hasSuffix(" Framework.framework") else { return false }
            let stem = name.dropLast(" Framework.framework".count)
            return browserFrameworks.contains { stem == $0 || stem.hasPrefix($0 + " ") }
        }
    }

    /// Whether apps are Chromium's or Electron's, each told once and kept (by bundle id): a known browser
    /// (`isBrowser`), else its bundle (`hasChromium`), found by `locate` (the app running with that id, else where Launch
    /// Services has it). An app not found, or a field that tells none: no. Any thread.
    public final class Known: @unchecked Sendable {
        private let lock = NSLock()
        private var apps: [String: Bool] = [:]
        private let locate: (String) -> URL?

        public init(locate: @escaping (String) -> URL?) {
            self.locate = locate
        }

        public func isChromium(_ bundleID: String?) -> Bool {
            guard let bundleID, !bundleID.isEmpty else { return false }
            if let known = lock.withLock({ apps[bundleID] }) { return known }
            let found = ChromiumApps.isBrowser(bundleID) || locate(bundleID).map(ChromiumApps.hasChromium(bundle:)) ?? false
            lock.withLock { apps[bundleID] = found }
            return found
        }
    }
}
