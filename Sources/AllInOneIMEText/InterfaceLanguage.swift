import Foundation

/// The language of the interface (the input method, AllInOneIME Settings and the installer): a language code
/// ("en", "zh-Hans", "fr", "pt-BR"), one of the `.lproj` folders the app ships. The config's `uiLanguage` if it names
/// one, else the one the system prefers, as macOS picks an app's language (System Settings → General → Language &
/// Region, including the language chosen there for the app alone).
public enum InterfaceLanguage {
    /// The language codes that always ship: "en" and "zh-Hans".
    public static let builtIn = ["en", "zh-Hans"]

    /// The interface language for `preferred` (like `Locale.preferredLanguages`) among `shipped` codes
    /// (the bundle's localizations).
    ///
    /// The first preferred language that matches wins; none, English. Chinese is Simplified Chinese, or Traditional
    /// Chinese ("zh-Hant", "zh-TW", "zh-HK", "zh-MO") when that ships, else Simplified Chinese too. Other languages
    /// match the code with its region ("pt-BR"), else the language ("pt"); never another region of it.
    public static func pick(preferred: [String], shipped: [String]) -> String {
        let shipped = shipped.filter { $0 != "Base" }
        for identifier in preferred {
            let tag = Tag(identifier)
            switch tag.language {
            case "zh":
                if tag.traditional, let hant = spelled("zh-Hant", in: shipped) { return hant }
                return spelled("zh-Hans", in: shipped) ?? "zh-Hans"
            case "en": return spelled("en", in: shipped) ?? "en"
            default:
                // Apple's matching, kept to the code itself, without a region, or without a script (not pt-PT for
                // pt-BR, nor es-MX for es-419, nor its fallback when nothing matches).
                let candidates = tag.candidates
                let matches = Bundle.preferredLocalizations(from: shipped, forPreferences: [tag.code])
                if let match = matches.first(where: { candidates.contains(Tag($0).code.lowercased()) }) { return match }
                for candidate in candidates {
                    if let match = shipped.first(where: { Tag($0).code.lowercased() == candidate }) { return match }
                }
            }
        }
        return spelled("en", in: shipped) ?? "en"
    }

    /// A config value ("zh", "en", or a shipped code) → the code it means, or nil (follow the system).
    public static func code(forSetting value: String?, shipped: [String]) -> String? {
        switch value {
        case nil, ""?: return nil
        case "zh"?: return spelled("zh-Hans", in: shipped) ?? "zh-Hans"
        case "en"?: return spelled("en", in: shipped) ?? "en"
        case let value?: return spelled(value, in: shipped.filter { $0 != "Base" })
        }
    }

    /// The config value for `code`: "zh" and "en" for Simplified Chinese and English, as older versions write and
    /// read them; the code for the others.
    public static func setting(for code: String) -> String {
        switch code.lowercased() {
        case "zh-hans": return "zh"
        case "en": return "en"
        default: return code
        }
    }

    /// The interface language: the config's `uiLanguage` (`setting`) if it names one `app` ships, else the one
    /// `preferred` picks.
    public static func current(setting: String?, preferred: [String] = Locale.preferredLanguages,
                               app: Bundle = .main) -> String {
        let shipped = shipped(in: app)
        return code(forSetting: setting, shipped: shipped) ?? pick(preferred: preferred, shipped: shipped)
    }

    /// The languages `app` ships: the built-in ones and its other `.lproj` folders, in that order.
    public static func shipped(in app: Bundle = .main) -> [String] {
        let others = app.localizations.filter { code in
            code != "Base" && !builtIn.contains { $0.caseInsensitiveCompare(code) == .orderedSame }
        }
        return builtIn + others.sorted()
    }

    /// Whether `code` is Chinese ("zh-Hans", "zh-Hant"): the interface texts that only come in Chinese and English
    /// (`UIText.chinese`) are Chinese then.
    public static func isChinese(_ code: String) -> Bool { Tag(code).language == "zh" }

    /// The code of Simplified Chinese or English: for what only knows whether the interface is Chinese.
    public static func code(chinese: Bool) -> String { chinese ? "zh-Hans" : "en" }

    /// A language's name in that language, as the settings list it: "English", "简体中文", "Français".
    public static func name(_ code: String) -> String {
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// `code` as `shipped` spells it, matched without regard to case or "_" / "-"; nil when it doesn't ship.
    static func spelled(_ code: String, in shipped: [String]) -> String? {
        let wanted = Tag(code).code.lowercased()
        return shipped.first { Tag($0).code.lowercased() == wanted }
    }

    /// A language identifier taken apart: "zh_Hant_TW" → zh, hant, TW.
    struct Tag {
        /// The identifier with "-" between its parts.
        let code: String
        /// Lowercased: "zh", "pt".
        let language: String
        let script: String?
        let region: String?

        init(_ identifier: String) {
            code = identifier.replacingOccurrences(of: "_", with: "-")
            let parts = code.split(separator: "-").map(String.init)
            language = parts.first?.lowercased() ?? ""
            script = parts.dropFirst().first { $0.count == 4 && $0.allSatisfy(\.isLetter) }?.lowercased()
            region = parts.dropFirst().first {
                ($0.count == 2 && $0.allSatisfy(\.isLetter)) || ($0.count == 3 && $0.allSatisfy(\.isNumber))
            }?.uppercased()
        }

        /// Traditional Chinese: written in Hant, or for Taiwan, Hong Kong or Macau without a script.
        var traditional: Bool { script.map { $0 == "hant" } ?? ["TW", "HK", "MO"].contains(region ?? "") }

        /// What may match it, lowercased, best first: the code, the language with its script and region, with its
        /// region, with its script, and alone.
        var candidates: [String] {
            var candidates = [code.lowercased()]
            for parts in [[script, region], [region], [script], []] {
                let candidate = ([language] + parts.compactMap { $0 }).joined(separator: "-").lowercased()
                if !candidates.contains(candidate) { candidates.append(candidate) }
            }
            return candidates
        }
    }
}
