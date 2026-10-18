import Foundation
import Testing
@testable import AllInOneIMECore

// Acceptance tests for interface localization, step 1 (0.6.5/localization), written from the spec only, independently
// of the implementation's own tests; the implementer may not edit them. They cover the public AllInOneIMECore API the
// spec gives: `UIString` (an interface literal as a printf format plus its arguments), `InterfaceText.translate` (a
// lookup in a `<code>.lproj` bundle, built per test in a fresh temporary folder) and `InterfaceLanguage` (`builtIn`,
// `pick` and `code(forSetting:)`). What the apps do with them (`tr`, the settings picker, the catalog, `make strings`)
// lives outside this module and isn't checked here.

// MARK: - Fixtures

enum L10nAcc {
    /// What step 1 ships.
    static let step1 = ["en", "zh-Hans"]
    /// Step 1 plus Traditional Chinese.
    static let hant = ["en", "zh-Hans", "zh-Hant"]
    /// Step 1 plus French.
    static let french = ["en", "zh-Hans", "fr"]
    /// Step 1 plus Traditional Chinese, French, Japanese, Portuguese and Brazilian Portuguese.
    static let wide = ["en", "zh-Hans", "zh-Hant", "fr", "ja", "pt", "pt-BR"]

    /// Writes `entries` as `<fresh temporary folder>/fr.lproj/Localizable.strings` ("key" = "value";), hands
    /// `Bundle(path: <folder>/fr.lproj)` to `body`, then deletes the folder. Bundle caches bundles by path, so every
    /// call gets a folder of its own.
    static func withFrenchBundle(_ entries: KeyValuePairs<String, String>,
                                 sourceLocation: SourceLocation = #_sourceLocation,
                                 _ body: (Bundle) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aio-l10n-acc-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lproj = root.appendingPathComponent("fr.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let strings = entries.map { "\(quoted($0.key)) = \(quoted($0.value));\n" }.joined()
        try strings.write(to: lproj.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        try body(try #require(Bundle(path: lproj.path), sourceLocation: sourceLocation))
    }
}

/// A value whose text is its description.
struct L10nAccVersion: CustomStringConvertible {
    var description: String { "0.6.5" }
}

// MARK: - The tests

struct InterfaceLocalizationAcceptanceTests {
    // MARK: UIString

    @Test("UIString: a literal without interpolations is its own format, with no arguments")
    func uiStringPlainLiteral() {
        let s: UIString = "Check for updates automatically"
        #expect(s.format == "Check for updates automatically")
        #expect(s.arguments == [])
        #expect(s.text == "Check for updates automatically")
    }

    @Test("UIString: each interpolation is a %@ in the format, in order, and its text an argument")
    func uiStringInterpolations() {
        let file = "notes.txt", folder = "Documents"
        let move: UIString = "Move \(file) to \(folder)"
        #expect(move.format == "Move %@ to %@")
        #expect(move.arguments == ["notes.txt", "Documents"])
        #expect(move.text == "Move notes.txt to Documents")
        let joined: UIString = "\(folder)\(file)"
        #expect(joined.format == "%@%@")
        #expect(joined.arguments == ["Documents", "notes.txt"])
        #expect(joined.text == "Documentsnotes.txt")
    }

    @Test("UIString: an argument is the interpolated value's text, \"\\(value)\", whatever its type")
    func uiStringArgumentText() {
        let count = 42, seconds = 0.8, version = L10nAccVersion()
        let s: UIString = "\(count) items in \(seconds) s (\(version))"
        #expect(s.format == "%@ items in %@ s (%@)")
        #expect(s.arguments == ["\(count)", "\(seconds)", "\(version)"])
        #expect(s.arguments == ["42", "0.8", "0.6.5"])
        #expect(s.text == "42 items in 0.8 s (0.6.5)")
    }

    @Test("UIString: a % in the literal is %% in the format, and a single % in the text")
    func uiStringPercentInLiteral() {
        let done: UIString = "100% done"
        #expect(done.format == "100%% done")
        #expect(done.arguments == [])
        #expect(done.text == "100% done")

        let n = 40
        let saved: UIString = "\(n)% saved"
        #expect(saved.format == "%@%% saved")
        #expect(saved.arguments == ["40"])
        #expect(saved.text == "40% saved")

        // Placeholders written in the literal are text, not placeholders.
        let literal: UIString = "Type %@, %1$@ or %d"
        #expect(literal.format == "Type %%@, %%1$@ or %%d")
        #expect(literal.arguments == [])
        #expect(literal.text == "Type %@, %1$@ or %d")
    }

    @Test("UIString: a % in an argument is kept as it is, and fills in as text, not as a placeholder")
    func uiStringPercentInArgument() {
        let share = "50%", raw = "%@ %d %%"
        let s: UIString = "\(share) of \(raw)"
        #expect(s.format == "%@ of %@")
        #expect(s.arguments == ["50%", "%@ %d %%"])
        #expect(s.text == "50% of %@ %d %%")
    }

    @Test("UIString: the Chinese side works the same way")
    func uiStringChinese() {
        let n = 3
        let s: UIString = "共 \(n) 个，已完成 100%"
        #expect(s.format == "共 %@ 个，已完成 100%%")
        #expect(s.arguments == ["3"])
        #expect(s.text == "共 3 个，已完成 100%")
    }

    @Test("UIString(_:): a runtime string has its % doubled in the format and no arguments")
    func uiStringRuntime() {
        let name = ["Report", "100%", "%@.txt"].joined(separator: " ")
        let s = UIString(name)
        #expect(s.format == "Report 100%% %%@.txt")
        #expect(s.arguments == [])
        #expect(s.text == "Report 100% %@.txt")
    }

    @Test("UIString: equal when the format and the arguments are")
    func uiStringEquatable() {
        let one = 1, two = 2
        #expect(("\(one) items" as UIString) == ("\(one) items" as UIString))
        #expect(("\(one) items" as UIString) != ("\(two) items" as UIString))
        #expect(("\(one) items" as UIString) != ("\(one) files" as UIString))
        #expect(UIString("100% done") == ("100% done" as UIString))
    }

    @Test("UIString is an Equatable, Sendable string-interpolation literal")
    func uiStringConformances() {
        func conforms<T: ExpressibleByStringInterpolation & Equatable & Sendable>(_: T.Type) -> Bool { true }
        #expect(conforms(UIString.self))
    }

    // MARK: InterfaceText.translate

    @Test("translate: a plain entry gives its translation")
    func translatePlain() throws {
        try L10nAcc.withFrenchBundle(["Settings": "Réglages"]) { bundle in
            #expect(InterfaceText.translate("Settings", in: bundle) == "Réglages")
        }
    }

    @Test("translate: an interpolated entry is found by its format and filled in with the English arguments")
    func translateInterpolated() throws {
        try L10nAcc.withFrenchBundle(["%@ items": "%@ éléments"]) { bundle in
            let n = 3
            #expect(InterfaceText.translate("\(n) items", in: bundle) == "3 éléments")
        }
    }

    @Test("translate: %1$@ and %2$@ place the arguments in the translation's order")
    func translateReordered() throws {
        try L10nAcc.withFrenchBundle(["Move %@ to %@": "Déplacer vers %2$@ : %1$@",
                                      "Page %@ of %@": "Page %1$@ sur %2$@"]) { bundle in
            let file = "notes.txt", folder = "Documents", page = 2, pages = 5
            #expect(InterfaceText.translate("Move \(file) to \(folder)", in: bundle)
                    == "Déplacer vers Documents : notes.txt")
            #expect(InterfaceText.translate("Page \(page) of \(pages)", in: bundle) == "Page 2 sur 5")
        }
    }

    @Test("translate: %% in the key and in the translation is a single %")
    func translatePercent() throws {
        try L10nAcc.withFrenchBundle(["100%% done": "100 %% terminé", "%@%% saved": "%@ %% enregistrés",
                                      "Type %%@ for a value": "Tapez %%@ pour une valeur"]) { bundle in
            let n = 40
            #expect(InterfaceText.translate("100% done", in: bundle) == "100 % terminé")
            #expect(InterfaceText.translate("\(n)% saved", in: bundle) == "40 % enregistrés")
            #expect(InterfaceText.translate("Type %@ for a value", in: bundle) == "Tapez %@ pour une valeur")
        }
    }

    @Test("translate: an argument with % in it fills in as text")
    func translateArgumentWithPercent() throws {
        try L10nAcc.withFrenchBundle(["%@ left": "Il reste %@"]) { bundle in
            let share = "50%", raw = "%@ %d"
            #expect(InterfaceText.translate("\(share) left", in: bundle) == "Il reste 50%")
            #expect(InterfaceText.translate("\(raw) left", in: bundle) == "Il reste %@ %d")
        }
    }

    @Test("translate: nil when the bundle has no entry for the English format")
    func translateMissing() throws {
        try L10nAcc.withFrenchBundle(["Settings": "Réglages", "3 items": "trois éléments"]) { bundle in
            #expect(InterfaceText.translate("General", in: bundle) == nil)
            // The key is the format, "%@ items", not the text filled in.
            let n = 3
            #expect(InterfaceText.translate("\(n) items", in: bundle) == nil)
        }
        try L10nAcc.withFrenchBundle([:]) { bundle in
            #expect(InterfaceText.translate("Settings", in: bundle) == nil)
        }
    }

    @Test("translate: an entry the same as its key is a translation, not a missing one")
    func translateSameAsKey() throws {
        try L10nAcc.withFrenchBundle(["OK": "OK", "%@ ms": "%@ ms"]) { bundle in
            let n = 12
            #expect(InterfaceText.translate("OK", in: bundle) == "OK")
            #expect(InterfaceText.translate("\(n) ms", in: bundle) == "12 ms")
        }
    }

    @Test("translate: a translation referencing more arguments than given is nil, without crashing")
    func translateTooManyArguments() throws {
        try L10nAcc.withFrenchBundle(["Settings": "Réglages %@", "%@ items": "%@ éléments sur %@",
                                      "%@ files": "%2$@ fichiers",
                                      "Move %@ to %@": "Déplacer %1$@ vers %3$@"]) { bundle in
            let a = "a", b = "b"
            #expect(InterfaceText.translate("Settings", in: bundle) == nil)
            #expect(InterfaceText.translate("\(a) items", in: bundle) == nil)
            #expect(InterfaceText.translate("\(a) files", in: bundle) == nil)
            #expect(InterfaceText.translate("Move \(a) to \(b)", in: bundle) == nil)
        }
    }

    @Test("translate: a placeholder other than %@, %n$@ or %% is nil, without crashing")
    func translateOtherPlaceholders() throws {
        try L10nAcc.withFrenchBundle(["%@ items": "%d éléments", "%@ files": "%1$d fichiers",
                                      "%@ bytes": "%ld octets", "Name: %@": "Nom : %s",
                                      "100%% done": "100 % fait", "Settings": "Réglages %"]) { bundle in
            let n = 3, name = "notes"
            #expect(InterfaceText.translate("\(n) items", in: bundle) == nil)
            #expect(InterfaceText.translate("\(n) files", in: bundle) == nil)
            #expect(InterfaceText.translate("\(n) bytes", in: bundle) == nil)
            #expect(InterfaceText.translate("Name: \(name)", in: bundle) == nil)
            // "% f" is a printf conversion, not a percent sign.
            #expect(InterfaceText.translate("100% done", in: bundle) == nil)
            #expect(InterfaceText.translate("Settings", in: bundle) == nil)
        }
    }

    // MARK: InterfaceLanguage.builtIn

    @Test("builtIn: en and zh-Hans always ship")
    func builtIn() {
        #expect(InterfaceLanguage.builtIn.count == 2)
        #expect(Set(InterfaceLanguage.builtIn) == ["en", "zh-Hans"])
    }

    // MARK: InterfaceLanguage.pick

    @Test("pick: the first preferred language that matches a shipped one wins")
    func pickFirstMatch() {
        #expect(InterfaceLanguage.pick(preferred: ["fr", "zh-Hans"], shipped: L10nAcc.french) == "fr")
        #expect(InterfaceLanguage.pick(preferred: ["zh-Hans", "fr"], shipped: L10nAcc.french) == "zh-Hans")
        #expect(InterfaceLanguage.pick(preferred: ["de", "ko", "fr", "en"], shipped: L10nAcc.french) == "fr")
        #expect(InterfaceLanguage.pick(preferred: ["de", "en", "fr"], shipped: L10nAcc.french) == "en")
    }

    @Test("pick: en when no preferred language matches")
    func pickNone() {
        #expect(InterfaceLanguage.pick(preferred: [], shipped: L10nAcc.step1) == "en")
        #expect(InterfaceLanguage.pick(preferred: ["ja", "ko"], shipped: L10nAcc.step1) == "en")
        #expect(InterfaceLanguage.pick(preferred: ["de-DE", "ar"], shipped: L10nAcc.french) == "en")
    }

    @Test("pick: zh-Hans*, zh-CN, zh-SG and plain zh are zh-Hans",
          arguments: ["zh-Hans", "zh-Hans-CN", "zh-Hans-US", "zh-Hans-HK", "zh-CN", "zh-SG", "zh"])
    func pickSimplified(_ code: String) {
        #expect(InterfaceLanguage.pick(preferred: [code, "en"], shipped: L10nAcc.step1) == "zh-Hans")
        #expect(InterfaceLanguage.pick(preferred: [code, "en"], shipped: L10nAcc.hant) == "zh-Hans")
    }

    @Test("pick: zh-Hant*, zh-TW, zh-HK and zh-MO are zh-Hant when it ships",
          arguments: ["zh-Hant", "zh-Hant-TW", "zh-Hant-HK", "zh-Hant-CN", "zh-TW", "zh-HK", "zh-MO"])
    func pickTraditional(_ code: String) {
        #expect(InterfaceLanguage.pick(preferred: [code, "en"], shipped: L10nAcc.hant) == "zh-Hant")
        #expect(InterfaceLanguage.pick(preferred: [code, "en"], shipped: L10nAcc.wide) == "zh-Hant")
    }

    @Test("pick: zh-Hant*, zh-TW, zh-HK and zh-MO are zh-Hans, not English, when zh-Hant doesn't ship",
          arguments: ["zh-Hant", "zh-Hant-TW", "zh-Hant-HK", "zh-Hant-CN", "zh-TW", "zh-HK", "zh-MO"])
    func pickTraditionalFallback(_ code: String) {
        #expect(InterfaceLanguage.pick(preferred: [code, "en"], shipped: L10nAcc.step1) == "zh-Hans")
        #expect(InterfaceLanguage.pick(preferred: [code, "fr", "en"], shipped: L10nAcc.french) == "zh-Hans")
    }

    @Test("pick: en* is en", arguments: ["en", "en-US", "en-GB", "en-AU", "en-CN"])
    func pickEnglish(_ code: String) {
        #expect(InterfaceLanguage.pick(preferred: [code, "zh-Hans"], shipped: L10nAcc.step1) == "en")
        #expect(InterfaceLanguage.pick(preferred: [code, "zh-Hans"], shipped: L10nAcc.wide) == "en")
    }

    @Test("pick: another language with a region is that code when it ships")
    func pickRegionShipped() {
        #expect(InterfaceLanguage.pick(preferred: ["pt-BR", "en"], shipped: L10nAcc.wide) == "pt-BR")
        #expect(InterfaceLanguage.pick(preferred: ["pt-BR", "en"], shipped: ["en", "zh-Hans", "pt-BR"]) == "pt-BR")
    }

    @Test("pick: another language with a region is its language when the code doesn't ship")
    func pickRegionToLanguage() {
        #expect(InterfaceLanguage.pick(preferred: ["pt-BR", "en"], shipped: ["en", "zh-Hans", "pt"]) == "pt")
        #expect(InterfaceLanguage.pick(preferred: ["ja-JP", "en"], shipped: ["en", "zh-Hans", "ja"]) == "ja")
        #expect(InterfaceLanguage.pick(preferred: ["fr-CA", "zh-Hans"], shipped: L10nAcc.french) == "fr")
        #expect(InterfaceLanguage.pick(preferred: ["pt-PT", "en"], shipped: L10nAcc.wide) == "pt")
    }

    @Test("pick: [ja, en] is en and [ja, zh-Hans] is zh-Hans when ja doesn't ship")
    func pickJapaneseNotShipped() {
        for shipped in [L10nAcc.step1, L10nAcc.french] {
            #expect(InterfaceLanguage.pick(preferred: ["ja", "en"], shipped: shipped) == "en")
            #expect(InterfaceLanguage.pick(preferred: ["ja", "zh-Hans"], shipped: shipped) == "zh-Hans")
            #expect(InterfaceLanguage.pick(preferred: ["ja-JP", "en-JP"], shipped: shipped) == "en")
            #expect(InterfaceLanguage.pick(preferred: ["ja-JP", "zh-Hans-JP"], shipped: shipped) == "zh-Hans")
        }
    }

    @Test("pick: matching ignores case and reads _ as -", arguments: [
        (["ZH-HANS"], L10nAcc.step1, "zh-Hans"),
        (["zh_CN", "en"], L10nAcc.step1, "zh-Hans"),
        (["ZH_tw", "en"], L10nAcc.step1, "zh-Hans"),
        (["zh_hant_TW", "en"], L10nAcc.hant, "zh-Hant"),
        (["EN_us", "zh-Hans"], L10nAcc.step1, "en"),
        (["pt_BR", "en"], L10nAcc.wide, "pt-BR"),
        (["PT-br", "en"], L10nAcc.wide, "pt-BR"),
        (["JA_jp", "en"], L10nAcc.wide, "ja"),
    ])
    func pickCaseAndUnderscore(_ preferred: [String], _ shipped: [String], _ expected: String) {
        #expect(InterfaceLanguage.pick(preferred: preferred, shipped: shipped) == expected)
    }

    @Test("pick: the result is spelled as in shipped", arguments: [
        (["pt-BR", "en"], ["en", "zh-Hans", "pt_BR"], "pt_BR"),
        (["pt-BR", "en"], ["en", "zh-Hans", "pt-br"], "pt-br"),
        (["zh-TW", "en"], ["en", "zh-Hans", "zh_Hant"], "zh_Hant"),
    ])
    func pickSpelling(_ preferred: [String], _ shipped: [String], _ expected: String) {
        #expect(InterfaceLanguage.pick(preferred: preferred, shipped: shipped) == expected)
    }

    // MARK: InterfaceLanguage.code(forSetting:)

    @Test("code(forSetting:): today's \"zh\" and \"en\" are zh-Hans and en")
    func settingZhEn() {
        for shipped in [L10nAcc.step1, L10nAcc.hant, L10nAcc.wide] {
            #expect(InterfaceLanguage.code(forSetting: "zh", shipped: shipped) == "zh-Hans")
            #expect(InterfaceLanguage.code(forSetting: "en", shipped: shipped) == "en")
        }
    }

    @Test("code(forSetting:): a shipped code is itself", arguments: [
        ("zh-Hans", L10nAcc.step1),
        ("zh-Hant", L10nAcc.hant),
        ("fr", L10nAcc.french),
        ("pt", L10nAcc.wide),
        ("pt-BR", L10nAcc.wide),
    ])
    func settingShipped(_ value: String, _ shipped: [String]) {
        #expect(InterfaceLanguage.code(forSetting: value, shipped: shipped) == value)
    }

    @Test("code(forSetting:): a shipped code written another way comes back spelled as in shipped")
    func settingSpelling() {
        #expect(InterfaceLanguage.code(forSetting: "FR", shipped: L10nAcc.french) == "fr")
        #expect(InterfaceLanguage.code(forSetting: "pt_br", shipped: L10nAcc.wide) == "pt-BR")
        #expect(InterfaceLanguage.code(forSetting: "ZH_hant", shipped: L10nAcc.hant) == "zh-Hant")
    }

    @Test("code(forSetting:): nil, empty or not shipped is nil (follow the system)")
    func settingFollowsSystem() {
        #expect(InterfaceLanguage.code(forSetting: nil, shipped: L10nAcc.step1) == nil)
        #expect(InterfaceLanguage.code(forSetting: "", shipped: L10nAcc.step1) == nil)
        #expect(InterfaceLanguage.code(forSetting: "ja", shipped: L10nAcc.step1) == nil)
        #expect(InterfaceLanguage.code(forSetting: "fr", shipped: L10nAcc.step1) == nil)
        #expect(InterfaceLanguage.code(forSetting: "xx", shipped: L10nAcc.wide) == nil)
        // Not shipped is nil, not the nearest shipped language as `pick` would choose.
        #expect(InterfaceLanguage.code(forSetting: "zh-Hant", shipped: L10nAcc.step1) == nil)
    }
}
