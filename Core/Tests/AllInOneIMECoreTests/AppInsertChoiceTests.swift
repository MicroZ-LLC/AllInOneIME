import Foundation
import Testing
@testable import AllInOneIMECore

/// An app's own choice in Settings → General → Suggestions → "In these apps" and the input menu's This App ▸ Insert
/// (`AppInsertChoice`, the owner's decision of 2026-10-24): With title, With title and link, Off. It is the app's
/// `suggestions` and `suggestionsInsert` (`AppProfile.insertChoice`), no key of its own: what each profile reads as, what
/// each choice writes, and that an app with only Off is in the list and has settings of its own.
struct AppInsertChoiceTests {
    @Test func offeredInOrderWithTheirNames() {
        #expect(AppInsertChoice.offered == [.insert(.title), .insert(.titleAndLink), .off])
        UIText.$scopedLanguage.withValue("en") {
            #expect(AppInsertChoice.offered.map(\.label) == ["With title", "With title and link", "Off"])
            #expect(AppInsertChoice.insert(.id).label == "ID only" && AppInsertChoice.insert(.source).label == "Source's default")
        }
        UIText.$scopedLanguage.withValue("zh-Hans") {
            #expect(AppInsertChoice.offered.map(\.label) == ["带标题", "带标题和链接", "关闭"])
        }
    }

    /// The settings document's values: an insert's own, "off"; nothing else reads as one.
    @Test func rawValuesRoundTrip() {
        let every = SuggestionsInsert.allCases.map(AppInsertChoice.insert) + [.off]
        for choice in every { #expect(AppInsertChoice(rawValue: choice.rawValue) == choice, "\(choice)") }
        #expect(AppInsertChoice.off.rawValue == "off" && AppInsertChoice.insert(.titleAndLink).rawValue == "titleAndLink")
        #expect(AppInsertChoice(rawValue: "Off") == nil && AppInsertChoice(rawValue: "") == nil && AppInsertChoice(rawValue: "none") == nil)
    }

    /// What a profile reads as: Off while its suggestions are off (whatever it inserts, an old choice too), else what it
    /// inserts; suggestions on (true) is as everywhere.
    @Test func whatAProfileReadsAs() {
        let cases: [(AppProfile, AppInsertChoice?)] = [
            (AppProfile(), nil),
            (AppProfile(noAI: true), nil),
            (AppProfile(suggestions: true), nil),
            (AppProfile(suggestionsInsert: .title), .insert(.title)),
            (AppProfile(suggestions: true, suggestionsInsert: .titleAndLink), .insert(.titleAndLink)),
            (AppProfile(suggestionsInsert: .id), .insert(.id)),
            (AppProfile(suggestionsInsert: .source), .insert(.source)),
            (AppProfile(suggestions: false), .off),
            (AppProfile(suggestions: false, suggestionsInsert: .title), .off),
            (AppProfile(suggestions: false, suggestionsInsert: .id), .off),
        ]
        for (profile, choice) in cases { #expect(profile.insertChoice == choice, "\(profile)") }
    }

    /// What each choice writes: Off turns the app's suggestions off and keeps what it inserts; an insert turns them back
    /// on (as everywhere) with it; none (Remove, Restore Default, Same as everywhere) clears both. Its other fields stay.
    @Test func whatEachChoiceWrites() {
        let start = AppProfile(inputLanguage: .english, noAI: true, suggestionsInsert: .titleAndLink)
        var profile = start
        profile.insertChoice = .off
        #expect(profile == AppProfile(inputLanguage: .english, noAI: true, suggestions: false, suggestionsInsert: .titleAndLink))
        profile.insertChoice = .insert(.title)
        #expect(profile == AppProfile(inputLanguage: .english, noAI: true, suggestionsInsert: .title))
        profile.insertChoice = .off
        profile.insertChoice = nil
        #expect(profile == AppProfile(inputLanguage: .english, noAI: true))
        var on = AppProfile(suggestions: true, suggestionsInsert: .id)
        on.insertChoice = nil
        #expect(on.isEmpty, "Restore Default of an old one: nothing left")
        var off = AppProfile()
        off.insertChoice = .off
        #expect(off == AppProfile(suggestions: false) && !off.isEmpty, "Off alone is a setting of its own")
    }

    /// An app with only Off has settings of its own: kept in the file, its suggestions off in the session's switches, and
    /// none of what it inserts said there.
    @Test func anAppWithOnlyOffIsKept() throws {
        var config = Config.default
        config.changeProfile(for: "com.apple.Terminal", dropsEmpty: true) { $0.insertChoice = .off }
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(decoded.profile(for: "com.apple.terminal")?.insertChoice == .off)
        #expect(decoded.suggestionsSettings().apps == ["com.apple.Terminal": false] && decoded.suggestionsSettings().appInserts.isEmpty)
        config.changeProfile(for: "com.apple.Terminal", dropsEmpty: true) { $0.insertChoice = nil }
        #expect(config.appProfiles.isEmpty)
    }
}
