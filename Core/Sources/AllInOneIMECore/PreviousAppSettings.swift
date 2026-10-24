import Foundation

/// The per-app settings no setting sets any more (0.6.7: an app has two of its own, Insert and No AI): the input it
/// starts in, Translate as You Type always on, autocomplete always or never, no suggestions, results typed out or not, its
/// rewrite styles. Each is still honored while it is set. Settings lists the apps with any under "Previous per-app
/// settings", and Remove clears them there (`Config.removePreviousSettings`); nothing else changes them: the config file
/// keeps them as they are, synced as before.
public enum PreviousAppSettings {
    /// Whether `profile` sets any of them (a value that changes nothing, such as `translateAlways: false`, isn't one).
    public static func any(_ profile: AppProfile) -> Bool {
        profile.startingInput != nil || profile.translateAlways == true || profile.autocomplete != nil || profile.suggestions == false
            || profile.typeOut != nil || profile.rewriteStyles != nil
    }

    /// The apps whose profile sets any, by their id as the file has it, in order.
    public static func apps(in config: Config) -> [String] {
        config.appProfiles.filter { any($0.value) }.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// What `profile` sets of them, each as a few words ("Starts in English", "Always Translate as You Type"), in the
    /// interface language; Code is named with `config`'s coding language.
    public static func parts(_ profile: AppProfile, config: Config) -> [String] {
        var parts: [String] = []
        if let input = profile.startingInput {
            let name = SessionText.inputName(input, language: UIText.language,
                                             coding: config.codingLanguage.map { CodingLanguagePack.title(of: $0) })
            parts.append(tr("用\(name)开始", "Starts in \(name)"))
        }
        if profile.translateAlways == true { parts.append(tr("总是边打边译", "Always Translate as You Type")) }
        if let autocomplete = profile.autocomplete {
            parts.append(autocomplete ? tr("总是续写", "Always autocomplete") : tr("不续写", "No autocomplete"))
        }
        if profile.suggestions == false { parts.append(tr("不显示建议", "No suggestions")) }
        if let typeOut = profile.typeOut { parts.append(typeOut ? tr("逐字上屏", "Typed out") : tr("不逐字上屏", "Not typed out")) }
        if let names = profile.rewriteStyles {
            let styles = RewriteStyle.resolve(names).map(UIText.name)
            parts.append(tr("改写：", "Rewrites: ") + (styles.isEmpty ? tr("无", "none") : styles.joined(separator: tr("、", ", "))))
        }
        return parts
    }

    /// `profile` without them: its Insert and No AI as they are.
    public static func cleared(_ profile: AppProfile) -> AppProfile {
        var profile = profile
        profile.startingInput = nil
        profile.translateAlways = nil
        profile.autocomplete = nil
        profile.suggestions = nil
        profile.typeOut = nil
        profile.rewriteStyles = nil
        return profile
    }
}

extension Config {
    /// Settings' "Previous per-app settings" → Remove: those of `app` cleared (every spelling of its id), its Insert and
    /// No AI kept; a profile left setting nothing goes. The other apps' are as they were.
    public mutating func removePreviousSettings(for app: String) {
        guard profileKey(for: app) != nil else { return }
        changeProfile(for: app, dropsEmpty: true) { $0 = PreviousAppSettings.cleared($0) }
    }
}
