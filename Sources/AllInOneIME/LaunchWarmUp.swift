import AllInOneIMECore
import AppKit

/// What the first key and the first panel after launch would wait for, made ready once librime is (or a moment after
/// launch without it): the English words put among pinyin's candidates, the jargon list's terms with them, made off the
/// main thread (`EnglishWordsEngine.Words.prepare`; the first text field made them on the main thread, 36 ms), and the
/// candidate panel's window and glass, shown once, unseen (`CandidatePanel.prewarm`); a config that chose Gemini CLI's session moved
/// to Antigravity's (`ClaudeSessionMac.migrateGeminiCLIChoice`); with a CLI chosen, the fast fallback autocomplete would ask, looked
/// up off the main thread (`AutocompleteSwitch.lookUp`). Nothing is sent or shown. Once a launch; main thread only.
@MainActor
enum LaunchWarmUp {
    private static var done = false

    static func run() {
        guard !done else { return }
        done = true
        CandidatePanel.shared.prewarm()
        ClaudeSessionMac.migrateGeminiCLIChoice()
        let config = LiveConfig.current
        AutocompleteSwitch.lookUp(config)  // with a CLI chosen, what autocomplete asks, for the input menu's switch
        DispatchQueue.global(qos: .utility).async {
            let url = config.jargonURL
            let date = FileDate.own(url.path)
            let jargon = date == nil ? [] : JargonLibrary.load(from: url)
            EnglishWordsEngine.Words.prepare(config, jargon: jargon)
            DispatchQueue.main.async { LiveJargon.take(url: url, date: date, entries: jargon) }
        }
    }
}
