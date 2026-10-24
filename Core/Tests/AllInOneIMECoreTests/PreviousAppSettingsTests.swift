import Foundation
import Testing
@testable import AllInOneIMECore

/// The per-app settings no setting sets any more (`PreviousAppSettings`, Settings v2): which apps have any, what their row
/// says, and Remove, which clears those of one app and nothing else.
struct PreviousAppSettingsTests {
    let slack = "com.tinyspeck.slackmacgap"
    let mail = "com.apple.mail"
    let notes = "com.apple.Notes"

    @Test func onlyWhatChangesSomethingCounts() {
        #expect(!PreviousAppSettings.any(AppProfile()))
        #expect(!PreviousAppSettings.any(AppProfile(noAI: true, suggestionsInsert: .title)), "the two settings kept aren't listed")
        #expect(!PreviousAppSettings.any(AppProfile(translateAlways: false, suggestions: true)), "values that change nothing")
        for profile in [AppProfile(inputLanguage: .english), AppProfile(rewriteStyles: []), AppProfile(typeOut: false),
                        AppProfile(translateAlways: true), AppProfile(autocomplete: false), AppProfile(suggestions: false)] {
            #expect(PreviousAppSettings.any(profile), "\(profile)")
        }
        var code = AppProfile()
        code.startingInput = .code
        #expect(PreviousAppSettings.any(code), "an app that starts in Code")
    }

    @Test func listsTheAppsWithAny() {
        var config = Config.default
        config.appProfiles = [slack: AppProfile(inputLanguage: .english), mail: AppProfile(typeOut: true), notes: AppProfile(noAI: true)]
        #expect(PreviousAppSettings.apps(in: config) == [mail, slack])
        #expect(PreviousAppSettings.apps(in: .default).isEmpty)
    }

    @Test func saysWhatIsSet() async {
        await withInterfaceLanguage("en") {
            var config = Config.default
            config.codingLanguage = "python"
            let profile = AppProfile(inputLanguage: .english, rewriteStyles: ["正式"], typeOut: false, translateAlways: true,
                                     autocomplete: true, suggestions: false)
            #expect(PreviousAppSettings.parts(profile, config: config)
                    == ["Starts in English", "Always Translate as You Type", "Always autocomplete", "No suggestions", "Not typed out",
                        "Rewrites: Formal"])
            var code = AppProfile()
            code.startingInput = .code
            #expect(PreviousAppSettings.parts(code, config: config).first?.hasPrefix("Starts in Code") == true)
        }
    }

    @Test func removeClearsThemOfThatAppOnly() {
        var config = Config.default
        config.appProfiles = [slack: AppProfile(inputLanguage: .english, translateAlways: true, autocomplete: true, suggestionsInsert: .titleAndLink),
                              mail: AppProfile(rewriteStyles: ["正式"], typeOut: true), notes: AppProfile(noAI: true)]
        // Under another spelling of the id: the app's one entry.
        config.removePreviousSettings(for: "com.tinyspeck.SlackMacGap")
        #expect(config.appProfiles[slack] == AppProfile(suggestionsInsert: .titleAndLink), "Insert kept")
        #expect(config.appProfiles[mail] == AppProfile(rewriteStyles: ["正式"], typeOut: true), "another app's as they were")
        #expect(config.appProfiles[notes] == AppProfile(noAI: true))
        // An app left with nothing goes; one without a profile changes nothing.
        config.removePreviousSettings(for: mail)
        #expect(config.appProfiles[mail] == nil && config.appProfiles.count == 2)
        let before = config
        config.removePreviousSettings(for: "com.example.none")
        #expect(config == before)
    }

    @Test func nothingElseRewritesThem() throws {
        // Read and written again as they are: the settings no setting sets stay in the file until Remove.
        let json = #"{"appProfiles": {"com.tinyspeck.slackmacgap": {"inputLanguage": "en", "translateAlways": true, "autocomplete": true}}}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(again.appProfiles[slack] == AppProfile(inputLanguage: .english, translateAlways: true, autocomplete: true))
    }
}
