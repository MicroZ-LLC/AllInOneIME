import Foundation
import Testing
@testable import AllInOneIMECore

/// The per-app settings no setting sets any more (`Config.previousAppSettings`, Settings v2 §2): which apps have any, what
/// their row says word for word, their order, and Remove, which changes nothing of an app without them. Suggestions off
/// in an app is no longer one of them (Off in "In these apps", the owner's decision of 2026-10-24): never listed, never
/// removed.
struct PreviousAppSettingsTests {
    let slack = "com.tinyspeck.slackmacgap"
    let mail = "com.apple.mail"
    let notes = "com.apple.Notes"

    @Test func onlyWhatChangesSomethingCounts() {
        #expect(AppProfile().previousFields.isEmpty)
        #expect(AppProfile(noAI: true, suggestionsInsert: .title).previousFields.isEmpty, "the two settings kept aren't listed")
        #expect(AppProfile(suggestions: false).previousFields.isEmpty, "nor an app's Off")
        #expect(!AppProfile.PreviousField.allCases.map(\.rawValue).contains("suggestions"))
        #expect(AppProfile(translateAlways: false).previousFields.isEmpty, "Translate as You Type off is no setting")
        var code = AppProfile()
        code.startingInput = .code
        #expect(code.previousFields == [.startingInput], "an app that starts in Code")
    }

    @Test func saysWhatIsSet() async {
        await withInterfaceLanguage("en") {
            var config = Config.default
            config.codingLanguage = "python"
            config.appProfiles = [slack: AppProfile(inputLanguage: .english, rewriteStyles: ["正式"], typeOut: false, translateAlways: true,
                                                    autocomplete: true, suggestions: false)]
            #expect(config.previousAppSettings(appName: { _ in "Slack" }).map(\.text)
                    == ["Slack: starts in English, Always Translate as You Type, Autocomplete always on, "
                        + "results not typed out, rewrites: Formal"], "its suggestions off aren't said")
            var code = AppProfile()
            code.startingInput = .code
            config.appProfiles = [slack: code]
            #expect(config.previousAppSettings(appName: { _ in nil }).map(\.text) == ["\(slack): starts in Code (Python)"],
                    "an app without a name goes by its id")
        }
    }

    @Test func rowsAreInTheOrderOfTheAppsNames() {
        var config = Config.default
        config.appProfiles = [slack: AppProfile(inputLanguage: .english), mail: AppProfile(typeOut: true), notes: AppProfile(noAI: true)]
        let names = [slack: "Slack", mail: "Mail", notes: "Notes"]
        #expect(config.previousAppSettings(appName: { names[$0] }).map(\.app) == [mail, slack])
        #expect(Config.default.previousAppSettings(appName: { names[$0] }).isEmpty)
    }

    @Test func removeChangesNothingOfAnAppWithoutThem() {
        var config = Config.default
        config.appProfiles = [notes: AppProfile(noAI: true), mail: AppProfile(typeOut: true), slack: AppProfile(suggestions: false)]
        let before = config
        config.removePreviousAppSettings(for: notes)
        config.removePreviousAppSettings(for: slack)
        config.removePreviousAppSettings(for: "com.example.none")
        #expect(config == before)
    }

    /// Remove keeps an app's Off ("In these apps": its suggestions off, what its rows insert) with its No AI.
    @Test func removeKeepsAnAppsOff() {
        var config = Config.default
        config.appProfiles = [slack: AppProfile(inputLanguage: .english, noAI: true, autocomplete: true, suggestions: false,
                                                suggestionsInsert: .titleAndLink)]
        #expect(config.previousAppSettings(appName: { _ in "Slack" }).first?.fields == [.startingInput, .autocomplete])
        config.removePreviousAppSettings(for: slack)
        #expect(config.profile(for: slack) == AppProfile(noAI: true, suggestions: false, suggestionsInsert: .titleAndLink))
        #expect(config.profile(for: slack)?.insertChoice == .off && config.previousAppSettings(appName: { _ in "Slack" }).isEmpty)
    }
}
