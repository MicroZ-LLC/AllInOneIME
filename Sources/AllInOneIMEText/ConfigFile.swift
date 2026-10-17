import Foundation

/// The config file as far as AllInOneIME Settings reads it: just `uiLanguage`, without `Config` (AllInOneIMECore), which
/// is the whole of it.
public enum ConfigFile {
    /// The user's config file, `~/.config/allinoneime/config.json`.
    public static var userURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/allinoneime/config.json")
    }

    /// Just `uiLanguage` from the config file at `url`: nil when the file or the value isn't there, or can't be read
    /// (read even where the whole config can't be decoded).
    public static func uiLanguage(from url: URL = userURL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json["uiLanguage"] as? String, !value.isEmpty else { return nil }
        return value
    }
}
