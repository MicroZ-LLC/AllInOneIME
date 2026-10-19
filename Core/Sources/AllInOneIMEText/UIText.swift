import Foundation

/// Interface language (settings window, candidate panel, notices, input menu): the one picked in the
/// settings (config `uiLanguage`), else the first of the system's preferred languages that the app ships
/// (`InterfaceLanguage.pick`; on the Mac, System Settings → General → Language & Region). Simplified Chinese and English
/// come from the code (`tr`), the others from the String Catalogs (`InterfaceText.lookup`).
///
/// The process's own: what every text the shell and the core make reads (`tr`). The core's texts that name its types
/// (commands, providers, errors …) are in AllInOneIMECore's extensions of it (UIText+Names.swift, UIText+Errors.swift).
/// Safe from any thread; a shell changes it from one (the Mac: the main thread), and a change is told on the main thread
/// (`.allInOneIMEInterfaceLanguageChanged`).
public enum UIText {
    private struct State {
        var choice: String?
        var app: Bundle
        var shipped: [String]
        var language: String
        var chinese: Bool
    }

    /// Worked out once, on the first read: `language` is read on the candidate panel's hot path (`tr`), so it is worked
    /// out when `choice` or `app` changes, not per text. The first read hands the core the app's translations
    /// (`InterfaceText.bundleLookup`), unless the shell installed its own (`InterfaceText.lookup`, a shell without
    /// `.lproj` bundles).
    private static let state: Locked<State> = {
        let app = Bundle.main
        let shipped = InterfaceLanguage.shipped(in: app)
        if !InterfaceText.lookupInstalled { InterfaceText.lookup = InterfaceText.bundleLookup(app: app) }
        let language = picked(choice: nil, shipped: shipped)
        return Locked(initialState: State(choice: nil, app: app, shipped: shipped, language: language,
                                          chinese: InterfaceLanguage.isChinese(language)))
    }()

    /// Picked in the settings (config `uiLanguage`: "zh", "en" or a shipped code; applied from the config when a
    /// text field or the window opens); nil follows the system. A change posts `.allInOneIMEInterfaceLanguageChanged` on
    /// the main thread: at once when it is changed there, else soon after, on the main queue.
    public static var choice: String? {
        get { state.withLock { $0.choice } }
        set {
            let changed = state.withLock { state -> Bool in
                guard state.choice != newValue else { return false }
                state.choice = newValue
                state.language = picked(choice: newValue, shipped: state.shipped)
                state.chinese = InterfaceLanguage.isChinese(state.language)
                return true
            }
            if changed { languageChanged() }
        }
    }

    /// Tells a panel on screen all along (the Mac's menu bar panel) to redraw in the new language, on the main thread,
    /// where it draws: at once from there, else on the main queue (a session on a thread of its own changed it).
    static func languageChanged() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .allInOneIMEInterfaceLanguageChanged, object: nil)
        } else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .allInOneIMEInterfaceLanguageChanged, object: nil) }
        }
    }

    /// Where the translations are (`<code>.lproj`): the app; a stand-in while the self-test checks them.
    public static var app: Bundle {
        get { state.withLock { $0.app } }
        set {
            state.withLock { state in
                state.app = newValue
                state.shipped = InterfaceLanguage.shipped(in: newValue)
                state.language = picked(choice: state.choice, shipped: state.shipped)
                state.chinese = InterfaceLanguage.isChinese(state.language)
            }
            InterfaceText.lookup = InterfaceText.bundleLookup(app: newValue)
        }
    }

    /// The languages `app` ships: "en", "zh-Hans" and its other `.lproj` folders.
    public static var shipped: [String] { state.withLock { $0.shipped } }

    /// The system's pick among what the app ships, read once per process (macOS relaunches apps after a language change).
    public static let systemLanguage = InterfaceLanguage.pick(preferred: Locale.preferredLanguages,
                                                               shipped: InterfaceLanguage.shipped(in: .main))

    /// The interface language's code: "zh-Hans", "en", …
    public static var language: String { state.withLock { $0.language } }

    /// Whether the interface is Chinese: what only comes in Chinese and English (key names, …) is Chinese then.
    public static var chinese: Bool { state.withLock { $0.chinese } }

    /// The interface text in the interface language as it is now (`language`): what a shell hands the core's text that
    /// takes its language (`PanelPresenter`, `SessionText`), and what `UIText`'s own texts are made with.
    public static var words: InterfaceWords { InterfaceWords(language: language) }

    private static func picked(choice: String?, shipped: [String]) -> String {
        InterfaceLanguage.code(forSetting: choice, shipped: shipped) ?? systemLanguage
    }

    /// Text written only in Simplified Chinese and English, without a catalog entry (an error's Chinese, a short
    /// language name), for the Chinese interface: as it is in Simplified Chinese, in Traditional characters in
    /// Traditional Chinese (ICU's Hans-Hant transform), never Simplified Chinese there.
    public static func chineseOnly(_ text: String) -> String { words.chineseOnly(text) }
}

extension Notification.Name {
    /// The interface language changed (`UIText.choice`): a panel on screen all along redraws in it. Posted on the main
    /// thread.
    public static let allInOneIMEInterfaceLanguageChanged = Notification.Name("AllInOneIMEInterfaceLanguageChanged")
}

/// Interface text in the interface language (see `UIText`): `chinese` for Simplified Chinese, `english` for English,
/// else the translation of `english` in the String Catalogs (through `InterfaceText.lookup`: on the Mac the app's
/// `<language>.lproj`, compiled from them), or `english` without one. The English text, as `UIString.format`
/// ("%@ items"), is the catalog's key.
///
/// `key`: where the same English text means something else elsewhere (`make strings` reports those), a key of its
/// own: a short dotted name for where or how it is used ("remove.delete"), whose English in the catalog is `english`.
public func tr(_ chinese: UIString, _ english: UIString, key: String? = nil) -> String {
    InterfaceText.text(chinese, english, key: key, language: UIText.language)
}
