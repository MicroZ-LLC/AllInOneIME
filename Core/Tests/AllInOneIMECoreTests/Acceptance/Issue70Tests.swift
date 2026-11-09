import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A provider stand-in that records the actual request made by a field's session.
final class PasswordFieldModel: AppleModelBackend, @unchecked Sendable {
    let availability = AppleModelAvailability.available
    let contextSize = 4096
    let supportedLanguages: Set<String> = ["en", "fr", "zh"]
    private let sent = Locked<[AppleModelRequest]>(initialState: [])
    var requests: [AppleModelRequest] { sent.withLock { $0 } }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        sent.withLock { $0.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.yield(AppleModelSnapshot(text: "OK"))
            continuation.finish()
        }
    }
}

/// A Mac-like field: Accessibility can report a password field while secure input remains off.
enum PasswordFieldRig {
    static func host(password: Bool, model: PasswordFieldModel = PasswordFieldModel(),
                     configure: (inout SessionServices) -> Void = { _ in }) -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.provider = .apple
        config.setOrder([Language.english, .chinese])
        config.setOrder([OutputLanguage.english, OutputLanguage("fr")])
        let fixed = config
        var services = SessionServices(
            converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: model),
            loadSettings: { fixed })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        configure(&services)
        let host = FakeHost(services: services)
        host.passwordField = password
        host.readsWhatIsWanted = true
        host.appTypesKeys = true
        host.focus()
        host.composer.setInputMode(.english)
        // This shell can read the field type with a key. The session remembers the result for later keys.
        var firstKey = host.context
        firstKey.field = FieldInfo(app: host.app, secure: password)
        host.press(FakeHost.enter, with: firstKey)
        return host
    }

    static func requestText(_ request: AppleModelRequest) -> String {
        ([request.instructions, request.prompt] + request.examples.flatMap { [$0.prompt, $0.response] })
            .joined(separator: "\n")
    }
}

/// #70: the text around the caret in a known password field must not be read for @reply or sent to its provider.
@Suite(.serialized)
struct Issue70Tests {
    private func reply(in host: FakeHost) {
        host.document = "hunter2"
        host.selection = 0..<0 // The caret is before the existing field text, so @ starts a command.
        host.type("@reply")
        host.press(FakeHost.tab)
        host.type("ok")
    }

    @Test func knownPasswordFieldKeepsReplyAwayFromFieldText() async {
        await withInterfaceLanguage("en") {
            let model = PasswordFieldModel()
            let host = PasswordFieldRig.host(password: true, model: model)
            reply(in: host)
            #expect(host.session.passwordField == .yes, "the test field must be known as a password field")
            let asked = host.session.fieldWants(for: FakeHost.enter, given: FieldContext(read: .secure))
            #expect(!asked.contains(.text), "Return requested the password field's text: \(asked)")
            #expect(!host.press(FakeHost.enter), "Return belongs to the password field, as during secure input")
            host.settle(timeout: 0.5) { !model.requests.isEmpty }
            #expect(model.requests.allSatisfy { !PasswordFieldRig.requestText($0).contains("hunter2") },
                    "the provider received the password field's text")
        }
    }

    @Test func normalFieldStillReadsReplyContext() async {
        await withInterfaceLanguage("en") {
            let model = PasswordFieldModel()
            let host = PasswordFieldRig.host(password: false, model: model)
            reply(in: host)
            #expect(host.session.passwordField == .no)
            #expect(host.composer.draftCommand == .reply)
            let asked = host.session.fieldWants(for: FakeHost.enter, given: FieldContext(read: .secure))
            #expect(asked.contains(.text), "normal @reply needs text around the caret")
            host.press(FakeHost.enter)
            #expect(host.settle(timeout: 2) { !model.requests.isEmpty }, "normal @reply starts a provider request")
            #expect(model.requests.contains { PasswordFieldRig.requestText($0).contains("hunter2") },
                    "normal @reply sends its field context")
        }
    }
}
