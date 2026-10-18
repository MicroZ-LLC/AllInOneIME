import Foundation

/// Where the core keeps its files, and the user's home. On macOS, as always: settings in ~/.config/allinoneime,
/// data in ~/Library/Application Support/AllInOneIME, logs in ~/Library/Logs/AllInOneIME, caches in
/// ~/Library/Caches/AllInOneIME. Elsewhere the platform's places: the XDG folders on Linux (~/.config,
/// ~/.local/share, ~/.local/state, ~/.cache), %APPDATA% and %LOCALAPPDATA% on Windows.
public enum CorePaths {
    /// The user's home folder.
    public static var home: URL {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #else
        FileManager.default.homeDirectoryForCurrentUser
        #endif
    }

    /// Whether `path` names a place on its own, not from some folder: one starting at "/"; on Windows one starting at a
    /// drive's root ("C:\…", "C:/…") or a share ("\\server\share\…"), as Foundation writes them too ("C:/Users/…").
    public static func isAbsolute(_ path: String) -> Bool {
        #if os(Windows)
        let start = Array(path.prefix(3))
        func separator(_ character: Character) -> Bool { character == "/" || character == "\\" }
        if start.count == 3, start[0].isASCII, start[0].isLetter, start[1] == ":", separator(start[2]) { return true }
        return start.count >= 2 && separator(start[0]) && separator(start[1])
        #else
        return path.hasPrefix("/")
        #endif
    }

    /// Whether `character` separates a path's parts: "/"; on Windows "\" too.
    public static func isSeparator(_ character: Character) -> Bool {
        #if os(Windows)
        character == "/" || character == "\\"
        #else
        character == "/"
        #endif
    }

    /// `path`'s parts, split on every separator (`isSeparator`), empty ones dropped.
    public static func components(_ path: String) -> [Substring] { path.split(whereSeparator: isSeparator) }

    /// Whether `part` of a path could lead out of its folder: "..", and on Windows what Windows reads as it or as
    /// something else than a name: a part of dots and spaces only (it drops a name's trailing ones), one with a ":"
    /// (a drive, "C:", or a file's stream, "a:b"), or a device's name (`isDeviceName`: "NUL", "con.txt").
    public static func climbs(_ part: Substring) -> Bool {
        #if os(Windows)
        if part != ".", part.allSatisfy({ $0 == "." || $0 == " " }) || part.contains(":") || isDeviceName(part) { return true }
        #endif
        return part == ".."
    }

    /// Whether Windows takes `part` for a device, not a file, in any folder: CON, PRN, AUX, NUL, COM1-9, LPT1-9,
    /// CONIN$, CONOUT$, in any case, with an extension or not ("nul.txt", "Com1.log"), trailing spaces dropped.
    static func isDeviceName(_ part: Substring) -> Bool {
        var base = part.prefix { $0 != "." }
        while base.last == " " { base = base.dropLast() }
        let name = base.uppercased()
        if ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"].contains(name) { return true }
        guard name.count == 4, name.hasPrefix("COM") || name.hasPrefix("LPT"), let digit = name.last else { return false }
        return ("1"..."9").contains(digit)
    }

    /// Whether `path`, written relative to a folder (a manifest's script, a bundle in a repository), stays in it as
    /// written, on every system alike: not absolute (`isAbsolute`), from no root ("/", "\"), drive ("C:", "C:x") or
    /// share ("\\server"), and no part that climbs out (`climbs`). Links aren't followed: that is `file(_:in:)`'s
    /// caller's to judge.
    public static func isPlainRelative(_ path: String) -> Bool {
        let start = Array(path.prefix(2))
        guard let first = start.first, !path.contains("\0"), !isAbsolute(path), first != "/", first != "\\" else { return false }
        if start.count == 2, first.isASCII, first.isLetter, start[1] == ":" { return false }
        return !components(path).contains(where: climbs)
    }

    /// The file `path` names in `folder` when it is plainly relative (`isPlainRelative`) and not `folder` itself ("."):
    /// with no part that climbs, root or drive, it is inside `folder` as written, by its parts alone (`standardizedFileURL`
    /// can't tell: it drops "/private" only from paths that exist). nil otherwise. On Windows its "\" are written "/", as
    /// Foundation's paths are.
    public static func file(_ path: String, in folder: URL) -> URL? {
        guard isPlainRelative(path), components(path).contains(where: { $0 != "." }) else { return nil }
        return folder.appendingPathComponent(isSeparator("\\") ? path.replacingOccurrences(of: "\\", with: "/") : path)
    }

    /// What the user edits: config.json, jargon.txt, plugins/, extensions/.
    public static var configDir: URL {
        #if os(macOS)
        home.appendingPathComponent(".config/allinoneime", isDirectory: true)
        #elseif os(Windows)
        windows("APPDATA")
        #else
        xdg("XDG_CONFIG_HOME", ".config")
        #endif
    }

    /// What the app keeps: language packs, extension sources, recent questions.
    public static var dataDir: URL {
        #if os(macOS)
        home.appendingPathComponent("Library/Application Support/AllInOneIME", isDirectory: true)
        #elseif os(Windows)
        windows("LOCALAPPDATA")
        #else
        xdg("XDG_DATA_HOME", ".local/share")
        #endif
    }

    public static var logsDir: URL {
        #if os(macOS)
        home.appendingPathComponent("Library/Logs/AllInOneIME", isDirectory: true)
        #elseif os(Windows)
        windows("LOCALAPPDATA").appendingPathComponent("Logs", isDirectory: true)
        #else
        xdg("XDG_STATE_HOME", ".local/state").appendingPathComponent("logs", isDirectory: true)
        #endif
    }

    public static var cacheDir: URL {
        #if os(macOS)
        home.appendingPathComponent("Library/Caches/AllInOneIME", isDirectory: true)
        #elseif os(Windows)
        windows("LOCALAPPDATA").appendingPathComponent("Cache", isDirectory: true)
        #else
        xdg("XDG_CACHE_HOME", ".cache")
        #endif
    }

    #if os(Windows)
    /// %APPDATA%\AllInOneIME or %LOCALAPPDATA%\AllInOneIME.
    private static func windows(_ variable: String) -> URL {
        let base = ProcessInfo.processInfo.environment[variable].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent("AppData/" + (variable == "APPDATA" ? "Roaming" : "Local"), isDirectory: true)
        return base.appendingPathComponent("AllInOneIME", isDirectory: true)
    }
    #elseif !os(macOS)
    /// `$variable/allinoneime`, or `~/fallback/allinoneime` when it isn't set to an absolute path (the XDG rule).
    private static func xdg(_ variable: String, _ fallback: String) -> URL {
        let base = ProcessInfo.processInfo.environment[variable].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
            ?? home.appendingPathComponent(fallback, isDirectory: true)
        return base.appendingPathComponent("allinoneime", isDirectory: true)
    }
    #endif
}
