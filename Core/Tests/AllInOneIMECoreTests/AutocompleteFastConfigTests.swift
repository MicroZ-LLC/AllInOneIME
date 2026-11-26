import Foundation
import Testing
@testable import AllInOneIMECore

/// One answer to "can autocomplete run, and which model does it ask", for Settings → Common, the input menu and the
/// menu-bar panel as for a request (`Config.fastConfig`, `Converter.fastConfig`): with a CLI chosen as the AI, its fast
/// fallback's settings, or none. The review found the input menu and the panel showing Autocomplete on, clickable and
/// naming "Claude API" with a CLI chosen and no faster AI, where Settings showed it off with the reason, and the field
/// asked nothing.
struct AutocompleteFastConfigTests {
    func config(_ ai: AIChoice, provider: Provider = .anthropic) -> Config {
        var config = Config.default
        config.provider = provider
        config.ai = ai
        return config
    }

    @Test func aProviderChosenIsWhatAutocompleteAsks() {
        for provider in Provider.allCases {
            let chosen = config(.provider(provider), provider: provider)
            #expect(chosen.fastConfig(ready: { _ in false }, apple: .unsupportedSystem) == chosen)
        }
    }

    @Test func aCLIChosenGoesByItsFastFallbackOrNone() throws {
        let cli = config(.cli(.claude))
        // The provider set up before: its settings, the CLI still chosen.
        let keyed = try #require(cli.fastConfig(ready: { $0 == .anthropic }, apple: .unsupportedSystem))
        #expect(keyed.provider == .anthropic && keyed.ai == .cli(.claude))
        // Not set up, Apple's model available: Apple's, never "Claude API" (the input menu's model then).
        let apple = try #require(cli.fastConfig(ready: { _ in false }, apple: .available))
        #expect(apple.provider == .apple && Autocomplete.route(apple) == .onDevice)
        #expect(Autocomplete.Words(language: "en").model(apple) == "Apple Intelligence on this Mac")
        // Neither: none, autocomplete can't run.
        #expect(cli.fastConfig(ready: { _ in false }, apple: .appleIntelligenceNotEnabled) == nil)
        #expect(cli.fastConfig(AIFacts()) == nil)
        #expect(cli.fastConfig(AIFacts(keys: [.anthropic: .saved(ending: nil)]))?.provider == .anthropic)
    }

    /// As a request finds it (the keychain, the AWS profile's files: never on the main thread): what the Mac's input menu
    /// and menu-bar panel look up, the same as the field's own route (`Converter.fast`).
    @Test func theConverterAnswersAsARequestWould() {
        let cli = config(.cli(.codex))
        func converter(key: String?, apple: AppleModelAvailability) -> Converter {
            Converter(loadConfig: { cli }, loadKey: { _, _ in key }, appleModel: StubAppleModel(apple), hasAWSProfile: { _ in false })
        }
        #expect(converter(key: nil, apple: .deviceNotEligible).fastConfig(cli) == nil)
        #expect(converter(key: nil, apple: .available).fastConfig(cli)?.provider == .apple)
        #expect(converter(key: "sk-ant-EXAMPLE", apple: .available).fastConfig(cli)?.provider == .anthropic)
        let none = converter(key: nil, apple: .deviceNotEligible)
        #expect(none.fast(cli).slow && none.fastConfig(cli) == nil, "the field's route and the switch disagree")
        let provider = config(.provider(.gemini), provider: .gemini)
        #expect(none.fastConfig(provider) == provider)
    }
}
