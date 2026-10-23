import Foundation
import Testing
@testable import AllInOneIMECore

/// Voice input is off for now (`Features.voiceInput`): what ships has none of it, whatever the user's `voiceInput`
/// setting says, and the setting is kept. The tests of dictation itself turn it on for the composer they make (or, through
/// the session, `Features.$voiceInputInTests`).
@Suite(.serialized, MemorySecrets())
struct VoiceOffTests {
    /// What tells of voice input in a settings document or the Assistant's prompt.
    static let voiceWords = ["voiceInput", "dictat", "Hold right", "speech", "microphone", "说话", "语音", "麦克风"]

    @Test func theShippedSwitchIsOff() {
        #expect(!Features.voiceInputShipped && !Features.voiceInput)
        #expect(Features.$voiceInputInTests.withValue(true) { Features.voiceInput })
        #expect(!Features.voiceInput)
    }

    /// The Mac's and Windows' documents, in English and Chinese, with voice on in the config and ⌥ tapped as the action
    /// key (whose note told of holding the right ⌥): no voice field, no word of it. The field can't be set either.
    @Test func theSettingsDocumentsHaveNoVoiceFields() throws {
        for language in ["en", "zh"] {
            for platform in [SettingsPlatform.mac, .windows] {
                let (service, url) = try service(#"{"uiLanguage": "\#(language)", "voiceInput": true, "actionKey": "optionTap"}"#,
                                                 platform: platform)
                let document = service.document()
                #expect(document.field("voiceInput") == nil, "\(platform) \(language)")
                let text = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
                for word in Self.voiceWords { #expect(!text.contains(word), "\(platform) \(language): \(word)") }
                if case let .failure(problem) = service.set("voiceInput", to: .bool(false)) {
                    #expect(problem.code == .unknownField)
                } else {
                    Issue.record("voiceInput was set (\(platform))")
                }
                // The user's setting is kept as it is, through a change of another.
                #expect((try? service.set("typeOut", to: .bool(true)).get()) != nil)
                #expect(try Config.load(from: url).voiceInput)
            }
        }
    }

    @Test func theActionKeysNoteDoesNotTellOfDictation() {
        for terms in [PlatformTerms.mac, .windows] {
            for key in [ActionKey.enter, .optionTap, .optionSpace, .space] {
                #expect(!UIText.actionKeyNote(key, terms: terms).contains("dictat"), "\(key)")
            }
        }
    }

    /// A session with voice on in the settings and speech recognition on the system: its composer has voice off, and
    /// so has one made with nothing said.
    @Test func theComposerHasVoiceDisabled() async {
        #expect(!Composer().voiceEnabled)
        await withInterfaceLanguage("en") {
            let host = host()
            #expect(!host.composer.voiceEnabled)
            #expect(!host.composer.messages.codeNotRun.contains("dictated"))
        }
    }

    /// Held, the right ⌥ arms nothing, starts nothing, and let go says nothing: no "Hold right ⌥ to talk".
    @Test func holdingTheRightOptionDoesNothing() async {
        await withInterfaceLanguage("en") {
            let host = host()
            let before = host.outputs.count
            host.modifiers(ModifierChange(key: .modifier(.option, .right), modifiers: [.option, .rightOption], timestamp: 100))
            #expect(!host.timers.contains { if case .voiceHold = $0 { true } else { false } }, "\(host.timers)")
            host.fireTimers()
            host.modifiers(ModifierChange(key: .modifier(.option, .right), modifiers: [], timestamp: 103))
            #expect(host.composer.voice == .off && !host.composer.isComposing)
            #expect(!host.platformActions.contains { if case .startVoice = $0 { true } else { false } }, "\(host.platformActions)")
            let notices = host.outputs.dropFirst(before).filter { if case .notice = $0 { true } else { false } }
            #expect(notices.isEmpty && host.noticeAlone == nil, "\(notices)")
        }
    }

    /// The Assistant isn't told of voice, so it never offers to turn it on.
    @Test func theAssistantIsNotToldOfVoice() {
        var config = Config.default
        config.voiceInput = false
        for compact in [false, true] {
            let request = AIConfigPrompt.request("turn on voice input", context: .init(config: config), compact: compact)
            let system = request.system.map(\.text).joined()
            for word in Self.voiceWords + ["voice"] { #expect(!system.contains(word), "compact \(compact): \(word)") }
        }
    }

    /// The doctor checks the microphone only when told about it, which the Mac's shell does only with voice on.
    @Test func theDoctorHasNoMicrophoneCheck() {
        var facts = Doctor.Facts()
        facts.config = .default
        #expect(!Doctor.findings(facts, chinese: false).contains { $0.fix == .openPrivacy(.microphone) || $0.title.contains("microphone") })
    }

    // MARK: - Helpers

    func service(_ text: String, platform: SettingsPlatform) throws -> (SettingsService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("voice-off-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        return (SettingsService(store: SettingsStore(configURL: url), platform: platform, library: library), url)
    }

    /// A session in a focused field whose settings have voice on, on a system that can recognize speech, the right ⌥
    /// held.
    func host() -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.voiceInput = true
        let engine = FakeEngine()
        var services = SessionServices(loadSettings: { config })
        services.levelOne = { .engine(engine) }
        services.voiceSupported = { true }
        services.isVoiceKeyHeld = { true }
        let host = FakeHost(services: services)
        host.focus()
        return host
    }
}
