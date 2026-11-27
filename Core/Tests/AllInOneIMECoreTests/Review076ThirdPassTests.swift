import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// What the third review of the 0.7.6 review's fixes found in the core, each test one finding.
@Suite("0.7.6 review, third pass: the right Option across secure input, iCloud sync's checks and the keychain", .serialized)
struct Review076ThirdPassTests {
    // MARK: The right Option released untold under secure input

    private func host() -> FakeHost {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.shapeCode = "moqi"
        config.actionKey = .optionSpace
        let fixed = config
        let engine = FakeEngine()
        engine.dictionary = ["yu": ["与", "于"]]
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(engine) }
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    /// The right Option pressed or released, nothing else down: whether it was kept from the app.
    private func rightOption(_ host: FakeHost, down: Bool, at time: Double) -> Bool {
        let change = ModifierChange(key: .modifier(.option, .right), modifiers: down ? [.option, .rightOption] : [], timestamp: time)
        return host.session.handle(.modifiers(change, host.context)).handled
    }

    /// The right Option down while pinyin is typed with shape codes on (its press kept from the app), secure input
    /// turned on, the key released untold, and a plain key typed there: pinyin is over.
    private func releasedUntoldInSecureInput() -> FakeHost {
        let host = host()
        host.type("yu")
        #expect(rightOption(host, down: true, at: 1), "the press of what may be the shape-code tap is kept from the app")
        host.secure = true
        host.press(KeyEvent(keyCode: 0, characters: "a"))
        host.secure = false
        #expect(!host.composer.isComposing, "secure input ends what was typed")
        return host
    }

    @Test func theNextPressAfterSecureInputIsTheApps() {
        let host = releasedUntoldInSecureInput()
        #expect(!rightOption(host, down: true, at: 10), "a new press with no pinyin was kept from the app")
        #expect(!rightOption(host, down: false, at: 10.1), "its release was kept from the app")
    }

    // MARK: iCloud sync's check of a provider's key never asks the keychain itself (rule 12)

    /// The platform's secret store holding OpenAI's key, saved for api.openai.com, and how often its items were asked.
    private func withOpenAIKeySaved<T>(_ body: (_ asked: Locked<Int>) throws -> T) rethrows -> T {
        let asked = Locked(initialState: 0)
        var store = APIKeys.Keychain.inMemory()
        _ = store.write(Provider.openai.rawValue, "sk-test-openai-EXAMPLE", "AllInOneIME: OpenAI", "api.openai.com", "MPLE", Date())
        let (attributes, read) = (store.attributes, store.read)
        store.attributes = { account in
            asked.withLock { $0 += 1 }
            return attributes(account)
        }
        store.read = { account in
            asked.withLock { $0 += 1 }
            return read(account)
        }
        var platform = Platform.current
        platform.secrets = store
        return try Platform.$override.withValue(platform) { try body(asked) }
    }

    private static let deepSeek: [String: AIConfig.JSONValue?] = [
        "provider": .string("openai"), "openai": .object(["model": .string("deepseek-chat"), "baseURL": .string("https://api.deepseek.com/v1")]),
    ]

    /// The checks ask only what their environment gives them (`ICloudSync.Environment`): with a key source of the
    /// test's, what this Mac's keychain holds changes nothing, and it isn't asked.
    @Test func theChecksAskOnlyTheirEnvironment() {
        withOpenAIKeySaved { asked in
            let saved = ICloudSync.applying(Self.deepSeek, to: .default, environment: .init(keySource: { _ in .keychain }))
            #expect(saved.rejected.isEmpty && saved.config.provider == .openai, "this Mac's keychain decided: \(saved.rejected)")
            let has = ICloudSync.applying(Self.deepSeek, to: .default, environment: .init(hasKey: { _ in true }))
            #expect(has.rejected.isEmpty && has.config.provider == .openai, "this Mac's keychain decided: \(has.rejected)")
            #expect(asked.withLock { $0 } == 0, "the checks asked the platform's keychain")
        }
    }
}
