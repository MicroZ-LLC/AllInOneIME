import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// #71: a field Accessibility identifies as a password field must have the same AI and script boundaries as secure input.
@Suite(.serialized)
struct Issue71Tests {
    private func aiRows(_ host: FakeHost) -> [OneAt.Action] {
        host.composer.oneAtRows.filter { $0.command?.usesAI == true }
    }

    @Test func knownPasswordFieldHasNoOneAtAIAndReturnDoesNotSendIt() async {
        await withInterfaceLanguage("en") {
            let model = PasswordFieldModel()
            let host = PasswordFieldRig.host(password: true, model: model)
            host.type("x!@abc123")
            #expect(host.session.passwordField == .yes)
            #expect(aiRows(host).isEmpty, "AI rows were listed for the password: \(aiRows(host))")
            host.press(FakeHost.enter)
            host.settle(timeout: 0.3) { !model.requests.isEmpty }
            #expect(model.requests.isEmpty, "Return started an AI request in the password field")
            #expect(host.document == "x!@abc123" && host.composer.draft.isEmpty,
                    "Return should leave the password as typed: \(host.document) / \(host.composer.draft)")
        }
    }

    @Test func normalFieldKeepsOneAtAIAndReturnSendsIt() async {
        await withInterfaceLanguage("en") {
            let model = PasswordFieldModel()
            let host = PasswordFieldRig.host(password: false, model: model)
            host.type("x!@abc123")
            #expect(host.session.passwordField == .no)
            #expect(!aiRows(host).isEmpty, "normal field still offers an AI row")
            host.press(FakeHost.enter)
            #expect(host.settle(timeout: 2) { !model.requests.isEmpty }, "normal field starts the selected AI row")
            #expect(model.requests.contains { PasswordFieldRig.requestText($0).contains("abc123") },
                    "normal field sends the text after @")
        }
    }

    @Test func knownPasswordFieldDoesNotTranslateAsYouType() async {
        await withInterfaceLanguage("en") {
            let model = PasswordFieldModel()
            let host = PasswordFieldRig.host(password: true, model: model)
            _ = host.composer.setTranslateMode(TranslateMode.Session(target: OutputLanguage("fr")))
            host.type("Qwerty")
            #expect(host.session.passwordField == .yes)
            #expect(host.document == "Qwerty" && host.composer.draft.isEmpty,
                    "the password must enter as typed: \(host.document) / \(host.composer.draft)")
            #expect(!host.press(FakeHost.enter), "Return belongs to the password field")
            host.settle(timeout: 0.3) { !model.requests.isEmpty }
            #expect(model.requests.isEmpty, "Return started a translation request")
            #expect(host.document == "Qwerty")
        }
    }

    @Test func normalFieldStillTranslatesAsYouType() async {
        await withInterfaceLanguage("en") {
            let model = PasswordFieldModel()
            let host = PasswordFieldRig.host(password: false, model: model)
            _ = host.composer.setTranslateMode(TranslateMode.Session(target: OutputLanguage("fr")))
            host.type("Qwerty")
            #expect(host.session.passwordField == .no)
            #expect(host.composer.draft == "Qwerty" && host.document.isEmpty,
                    "normal field collects the text for translation")
            host.press(FakeHost.enter)
            #expect(host.settle(timeout: 2) { !model.requests.isEmpty }, "normal field starts a translation request")
            #expect(model.requests.contains { PasswordFieldRig.requestText($0).contains("Qwerty") },
                    "normal translation sends the typed text")
        }
    }

    private func backgroundHost(password: Bool, calls: Locked<[String]>) -> FakeHost {
        let file = URL(fileURLWithPath: "/tmp/password-field-acceptance/sync.sh")
        let script = ScriptCommand(file: file, name: "sync", title: "Sync", background: true)
        return PasswordFieldRig.host(password: password) { services in
            services.loadExtensions = { _, _ in ExtensionIndex(commands: [script]) }
            services.startScriptInBackground = { _, arguments, _, _ in
                calls.withLock { $0.append(arguments.joined(separator: " ")) }
            }
        }
    }

    private func runBackgroundCommand(in host: FakeHost) {
        host.type("@sync")
        host.press(FakeHost.tab)
        host.type("abc123")
        host.press(FakeHost.enter)
    }

    @Test func knownPasswordFieldDoesNotGiveItsTextToABackgroundScript() async {
        await withInterfaceLanguage("en") {
            let calls = Locked<[String]>(initialState: [])
            let host = backgroundHost(password: true, calls: calls)
            runBackgroundCommand(in: host)
            #expect(host.session.passwordField == .yes)
            #expect(calls.withLock { $0 }.isEmpty, "a background script received password text")
        }
    }

    @Test func normalFieldStillRunsBackgroundScript() async {
        await withInterfaceLanguage("en") {
            let calls = Locked<[String]>(initialState: [])
            let host = backgroundHost(password: false, calls: calls)
            runBackgroundCommand(in: host)
            #expect(host.session.passwordField == .no)
            #expect(calls.withLock { $0 }.contains { $0.contains("abc123") },
                    "a normal field passes the command input to its background script")
        }
    }

    private func lookupHost(password: Bool, file: URL) -> FakeHost {
        let lookup = ScriptCommand(file: file, name: "lookup", title: "Lookup", output: .list, queryDelay: 0,
                                   launch: ["/bin/sh", file.path])
        return PasswordFieldRig.host(password: password) { services in
            services.loadExtensions = { _, _ in ExtensionIndex(commands: [lookup]) }
        }
    }

    private func typeLookup(in host: FakeHost) {
        host.type("@lookup")
        host.press(FakeHost.tab)
        host.type("abc123")
    }

    @Test func knownPasswordFieldDoesNotGiveItsTextToASuggestionLookup() async {
        await withInterfaceLanguage("en") {
            let folder = ScriptFolder()
            let marker = folder.url.appendingPathComponent("query.txt")
            let file = folder.add("lookup.sh", "#!/bin/sh\nprintf '%s' \"$1\" > '\(marker.path)'\nprintf '{\"items\":[]}'\n")
            let host = lookupHost(password: true, file: file)
            typeLookup(in: host)
            #expect(host.session.passwordField == .yes)
            host.settle(timeout: 0.4) { (try? String(contentsOf: marker, encoding: .utf8))?.contains("abc123") == true }
            let received = (try? String(contentsOf: marker, encoding: .utf8)) ?? ""
            #expect(!received.contains("abc123"), "a suggestion lookup received password text: \(received)")
        }
    }

    @Test func normalFieldStillRunsSuggestionLookup() async {
        await withInterfaceLanguage("en") {
            let folder = ScriptFolder()
            let marker = folder.url.appendingPathComponent("query.txt")
            let file = folder.add("lookup.sh", "#!/bin/sh\nprintf '%s' \"$1\" > '\(marker.path)'\nprintf '{\"items\":[]}'\n")
            let host = lookupHost(password: false, file: file)
            typeLookup(in: host)
            #expect(host.session.passwordField == .no)
            #expect(host.settle(timeout: 2) { (try? String(contentsOf: marker, encoding: .utf8)) == "abc123" },
                    "a normal field passes its query to the suggestion script")
        }
    }
}
