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
