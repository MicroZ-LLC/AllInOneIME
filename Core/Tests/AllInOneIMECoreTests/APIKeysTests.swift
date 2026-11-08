import Foundation
import Testing
@testable import AllInOneIMECore

/// The keys kept in memory once read (`APIKeys.KeyCache`), with reads counted instead of the keychain's.
struct KeyCacheTests {
    typealias Stamp = APIKeys.KeyCache.Stamp
    let saved = Stamp(created: Date(timeIntervalSince1970: 1000), modified: Date(timeIntervalSince1970: 1000))

    final class Reads: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: String? = "sk-one"
        var made: Int { lock.withLock { count } }
        func read() -> String? {
            lock.withLock { count += 1 }
            return value
        }
    }

    @Test func aKeyIsReadOncePerProcess() {
        let cache = APIKeys.KeyCache(), reads = Reads()
        for _ in 0..<5 { #expect(cache.key("anthropic", stamp: saved, read: reads.read) == "sk-one") }
        #expect(reads.made == 1)
    }

    @Test func eachAccountHasItsOwn() {
        let cache = APIKeys.KeyCache(), reads = Reads()
        _ = cache.key("anthropic", stamp: saved, read: reads.read)
        reads.value = "sk-two"
        #expect(cache.key("gemini", stamp: saved, read: reads.read) == "sk-two")
        #expect(cache.key("anthropic", stamp: saved, read: reads.read) == "sk-one")
        #expect(reads.made == 2)
    }

    @Test func savedOrRemovedHereItIsReadAgain() {
        let cache = APIKeys.KeyCache(), reads = Reads()
        _ = cache.key("anthropic", stamp: saved, read: reads.read)
        cache.forget("anthropic")  // as `APIKeys.save` does
        reads.value = "sk-new"
        #expect(cache.key("anthropic", stamp: saved, read: reads.read) == "sk-new")
        #expect(reads.made == 2)
    }

    @Test func changedInAnotherAppItIsReadAgain() {
        let cache = APIKeys.KeyCache(), reads = Reads()
        _ = cache.key("anthropic", stamp: saved, read: reads.read)
        reads.value = "sk-new"
        let changed = Stamp(created: saved.created, modified: Date(timeIntervalSince1970: 2000))
        #expect(cache.key("anthropic", stamp: changed, read: reads.read) == "sk-new")
        // Removed and saved again (made anew).
        reads.value = "sk-newer"
        let remade = Stamp(created: Date(timeIntervalSince1970: 3000), modified: changed.modified)
        #expect(cache.key("anthropic", stamp: remade, read: reads.read) == "sk-newer")
        #expect(reads.made == 3)
    }

    @Test func removedInAnotherAppThereIsNone() {
        let cache = APIKeys.KeyCache(), reads = Reads()
        _ = cache.key("anthropic", stamp: saved, read: reads.read)
        #expect(cache.key("anthropic", stamp: nil, read: reads.read) == nil)
        #expect(reads.made == 1)  // no item: nothing to read
        // Saved again with the same dates (to the second): read, not the key kept before.
        reads.value = "sk-again"
        #expect(cache.key("anthropic", stamp: saved, read: reads.read) == "sk-again")
    }

    @Test func aReadThatFailedIsTriedAgain() {
        // Denied (or the prompt closed): asked again next time, as before.
        let cache = APIKeys.KeyCache(), reads = Reads()
        reads.value = nil
        #expect(cache.key("anthropic", stamp: saved, read: reads.read) == nil)
        reads.value = "sk-one"
        #expect(cache.key("anthropic", stamp: saved, read: reads.read) == "sk-one")
        #expect(reads.made == 2)
    }

    @Test func tyingTheKeyToAHostDoesNotReadItAgain() {
        let cache = APIKeys.KeyCache(), reads = Reads()
        _ = cache.key("anthropic", stamp: saved, read: reads.read)
        let bound = Stamp(created: saved.created, modified: Date(timeIntervalSince1970: 2000))
        cache.restamp("anthropic", bound)
        #expect(cache.key("anthropic", stamp: bound, read: reads.read) == "sk-one")
        #expect(reads.made == 1)
        // Nothing kept, or no item: nothing to restamp.
        cache.restamp("gemini", bound)
        cache.restamp("anthropic", nil)
        #expect(cache.key("anthropic", stamp: bound, read: reads.read) == "sk-one")
        #expect(reads.made == 2)
    }

    @Test func requestsMadeTogetherReadOnce() {
        // Two prompts at once for one key (an @improve's parallel requests) would be one too many.
        let cache = APIKeys.KeyCache(), reads = Reads()
        let read: @Sendable () -> String? = {
            Thread.sleep(forTimeInterval: 0.05)
            return reads.read()
        }
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            #expect(cache.key("anthropic", stamp: saved, read: read) == "sk-one")
        }
        #expect(reads.made == 1)
    }

    /// A read held up (a prompt not answered yet) until `release` is signalled, with `started` signalled first.
    func heldRead(_ reads: Reads, started: DispatchSemaphore, release: DispatchSemaphore) -> @Sendable () -> String? {
        {
            started.signal()
            release.wait()
            return reads.read()
        }
    }

    @Test func aPromptForOneKeyDoesNotHoldUpAnother() {
        let cache = APIKeys.KeyCache(), held = Reads(), other = Reads()
        let (started, release, done) = (DispatchSemaphore(value: 0), DispatchSemaphore(value: 0), DispatchSemaphore(value: 0))
        let read = heldRead(held, started: started, release: release)
        // The requests on threads of their own: a busy test run's synchronous tests can take every thread of the
        // global queues for longer than the waits below.
        Thread {
            _ = cache.key("hosted", stamp: saved, read: read)
            done.signal()
        }.start()
        // The waits only catch a hang (the first read is held until it's released): long enough for a busy test run.
        #expect(started.wait(timeout: .now() + 20) == .success)
        // Another account's key comes while the first's read (its prompt) is still up.
        let otherDone = DispatchSemaphore(value: 0)
        Thread {
            #expect(cache.key("anthropic", stamp: saved, read: other.read) == "sk-one")
            otherDone.signal()
        }.start()
        #expect(otherDone.wait(timeout: .now() + 20) == .success)
        release.signal()
        #expect(done.wait(timeout: .now() + 20) == .success)
        #expect(held.made == 1 && other.made == 1)
    }

    @Test func savedDuringAReadTheOldKeyIsNotKept() {
        // Saved in the settings while a request's read was under way, within the same second (same stamp).
        let cache = APIKeys.KeyCache(), reads = Reads()
        let (started, release, done) = (DispatchSemaphore(value: 0), DispatchSemaphore(value: 0), DispatchSemaphore(value: 0))
        let read = heldRead(reads, started: started, release: release)
        Thread {  // on a thread of its own, as above
            #expect(cache.key("anthropic", stamp: saved, read: read) == "sk-one")  // that request gets what it read
            done.signal()
        }.start()
        #expect(started.wait(timeout: .now() + 20) == .success)
        cache.forget("anthropic")  // as `APIKeys.save` does
        release.signal()
        #expect(done.wait(timeout: .now() + 20) == .success)
        reads.value = "sk-new"
        #expect(cache.key("anthropic", stamp: saved, read: reads.read) == "sk-new")
        #expect(reads.made == 2)
    }
}

/// A key is removed only by `APIKeys.remove` (Settings' Remove Key…, confirmed): a save with an empty or blank key —
/// a key field submitted, left or closed empty — never removes it. In an in-memory keychain: the user's isn't touched.
struct KeyRemovalTests {
    let label = "AllInOneIME: Gemini API"

    @Test func anEmptyOrBlankSaveNeverRemovesAKey() throws {
        let store = APIKeys.Keychain.inMemory()
        try APIKeys.save("sk-test-gemini", account: "gemini", label: label, in: store)
        for empty in ["", " ", "   ", "\n", "\t \n"] {
            #expect(throws: APIKeys.EmptyKey.self) { try APIKeys.save(empty, account: "gemini", label: label, in: store) }
        }
        #expect(store.read("gemini") == "sk-test-gemini")
        #expect(APIKeys.hasKeychainKey(account: "gemini", in: store))
        // Nor is one made for an account without a key.
        #expect(throws: APIKeys.EmptyKey.self) { try APIKeys.save("", account: "openai", label: label, in: store) }
        #expect(!APIKeys.hasKeychainKey(account: "openai", in: store))
    }

    @Test func onlyRemoveRemovesAndOnlyThatKey() throws {
        let store = APIKeys.Keychain.inMemory()
        try APIKeys.save("sk-test-gemini", account: "gemini", label: label, in: store)
        try APIKeys.save("sk-test-openai", account: "openai", label: label, in: store)
        try APIKeys.remove(account: "gemini", in: store)
        #expect(!APIKeys.hasKeychainKey(account: "gemini", in: store) && store.read("openai") == "sk-test-openai")
        try APIKeys.remove(account: "gemini", in: store)  // none there: nothing to do, no error
    }

    /// Settings says which key is saved by its last 4 characters, kept with it at save time (an attribute: the key isn't
    /// read to show it); none for a key shorter than 12, nor for one saved before endings were kept.
    @Test func aSavedKeyKeepsItsLast4ForTheStatus() throws {
        #expect(APIKeys.ending(of: "sk-test-abcdef-a1b2") == "a1b2")
        #expect(APIKeys.ending(of: "  sk-test-abcdef-a1b2\n") == "a1b2")
        #expect(APIKeys.ending(of: "short-a1b2") == nil && APIKeys.ending(of: "12345678901") == nil)
        #expect(APIKeys.ending(of: "123456789012") == "9012")
        let store = APIKeys.Keychain.inMemory()
        try APIKeys.save("sk-test-abcdef-a1b2", account: "openai", label: label, in: store)
        #expect(APIKeys.keyEnding(account: "openai", in: store) == "a1b2")
        try APIKeys.save("short-c3d4", account: "openai", label: label, in: store)  // replaced by a short one: no ending
        #expect(APIKeys.keyEnding(account: "openai", in: store) == nil)
        #expect(APIKeys.keyEnding(account: "gemini", in: store) == nil)
        // The attribute as the keychain keeps it: only "ends:" and 4 characters count.
        #expect(APIKeys.ending(fromAttribute: APIKeys.endingAttribute("a1b2")) == "a1b2")
        #expect(APIKeys.ending(fromAttribute: APIKeys.endingAttribute(nil)) == nil)
        #expect(APIKeys.ending(fromAttribute: Data("ends:a1b2c3".utf8)) == nil && APIKeys.ending(fromAttribute: nil) == nil)
    }

    @Test func aSaveReplacesTheKeyInPlace() throws {
        let store = APIKeys.Keychain.inMemory()
        try APIKeys.save("sk-test-one", account: "gemini", label: label, host: "Generativelanguage.googleapis.com", in: store)
        let created = store.attributes("gemini")?.created
        try APIKeys.save("  sk-test-two \n", account: "gemini", label: label, in: store)
        #expect(store.read("gemini") == "sk-test-two" && store.attributes("gemini")?.created == created)
    }
}

/// A key set in the login shell (OPENAI_API_KEY, …) goes only to its provider's own service and to this computer
/// (`APIKeys.shellKeyGoes`): a base URL changed to another service (DeepSeek, a relay) gets a key saved for it in
/// Settings, never the user's OpenAI one, and Settings doesn't show it as set there. In memory, with the shell's
/// variables given (`MemorySecrets`): the user's keychain and shell are never read.
@Suite(MemorySecrets(environment: ["OPENAI_API_KEY": "sk-proj-shell-0000-a1b2", "ANTHROPIC_API_KEY": "sk-ant-shell-0000-c3d4",
                                   "GOOGLE_API_KEY": "AIza-shell-0000-e5f6"]))
struct ShellKeyHostTests {
    let openAI = "sk-proj-shell-0000-a1b2"

    @Test func aShellKeyGoesToItsOwnServiceAndThisComputer() throws {
        #expect(try APIKeys.load(.openai, for: "api.openai.com") == openAI)
        #expect(try APIKeys.load(.openai, for: "API.OpenAI.com") == openAI)
        for local in ["localhost", "127.0.0.1", "127.1.2.3", "::1", "[::1]"] {
            #expect(try APIKeys.load(.openai, for: local) == openAI, "\(local)")
        }
        #expect(try APIKeys.load(.anthropic, for: "api.anthropic.com") == "sk-ant-shell-0000-c3d4")
        #expect(try APIKeys.load(.gemini, for: "generativelanguage.googleapis.com") == "AIza-shell-0000-e5f6")
    }

    @Test func anotherHostGetsAClearErrorNotTheKey() {
        let others = ["api.deepseek.com", "openrouter.ai", "relay.example", "api.openai.com.relay.example", "api.anthropic.com",
                      "192.168.1.20", "10.0.0.2", "printer.local", "localhost.relay.example", "127.0.0.1.nip.io", "127.0.0", ""]
        for host in others {
            #expect(throws: ProviderError.shellKeyForAnotherHost(.openai, variable: "OPENAI_API_KEY"), "\(host)") {
                try APIKeys.load(.openai, for: host)
            }
        }
        #expect(throws: ProviderError.shellKeyForAnotherHost(.anthropic, variable: "ANTHROPIC_API_KEY")) {
            try APIKeys.load(.anthropic, for: "claude-relay.example")
        }
        #expect(throws: ProviderError.shellKeyForAnotherHost(.gemini, variable: "GOOGLE_API_KEY")) {
            try APIKeys.load(.gemini, for: "gemini-proxy.example")
        }
        // What the user reads: where that key goes, and to save one for this service.
        let error = ProviderError.shellKeyForAnotherHost(.openai, variable: "OPENAI_API_KEY")
        #expect(error.errorDescription == "$OPENAI_API_KEY is sent only to api.openai.com, not this base URL: save a key for this service in the settings")
        UIText.$scopedLanguage.withValue("en") {
            #expect(UIText.describe(error) == error.errorDescription)
        }
        #expect(AIConfigService.TooLong(provider: .openai, providerError: error).providerNotSetUp)
    }

    /// Settings shows a key in the shell as set only for a base URL it is sent to (the same rule as the request's).
    @Test func settingsShowAShellKeyOnlyWhereItIsSent() {
        let shell = APIKeys.source(.openai)
        #expect(shell == .environment("OPENAI_API_KEY"))
        #expect(shell.sent(by: .openai, to: "api.openai.com") == shell && shell.sent(by: .openai, to: "localhost") == shell)
        #expect(shell.sent(by: .openai, to: "api.deepseek.com") == .none && shell.sent(by: .openai, to: nil) == .none)
        #expect(APIKeys.Source.keychain.sent(by: .openai, to: "api.deepseek.com") == .keychain)
        #expect(APIKeys.Source.none.sent(by: .openai, to: "api.openai.com") == .none)
        let deepseek = HTTPProviders.host(of: ProviderSettings(baseURL: "https://api.deepseek.com/v1").resolved(for: .openai))
        #expect(!KeyState(shell.sent(by: .openai, to: deepseek), ending: nil).isSet)
        #expect(KeyState(shell.sent(by: .openai, to: HTTPProviders.host(of: .defaults(for: .openai))), ending: nil).isSet)
    }

    /// A keychain item that couldn't be read (its password prompt denied) is asked for once per request, not again on
    /// the way to the shell's key.
    @Test func aDeniedKeychainReadIsNotAskedAgain() throws {
        final class Reads: @unchecked Sendable {
            let lock = NSLock()
            var count = 0
        }
        let reads = Reads()
        let stamp = Date(timeIntervalSince1970: 1_234_567.891)
        let denied = APIKeys.Keychain(
            attributes: { $0 == "openai" ? APIKeys.ItemAttributes(created: stamp, modified: stamp, comment: nil) : nil },
            read: { _ in reads.lock.withLock { reads.count += 1 }; return nil },
            write: { _, _, _, _, _, _ in .failed(-1) }, setComment: { _, _ in .failed(-1) }, delete: { _ in .failed(-1) })
        var platform = Platform.current
        platform.secrets = denied
        try Platform.$override.withValue(platform) { () throws -> Void in
            #expect(try APIKeys.load(.openai, for: "api.openai.com") == openAI)
            #expect(reads.lock.withLock { reads.count } == 1)
            #expect(throws: ProviderError.shellKeyForAnotherHost(.openai, variable: "OPENAI_API_KEY")) {
                try APIKeys.load(.openai, for: "api.deepseek.com")
            }
            #expect(reads.lock.withLock { reads.count } == 2)
        }
    }

    /// The whole way through the converter, with its own key lookup: nothing is sent to another host with the shell's
    /// key; to a model on this computer it goes.
    @Test func noRequestGoesToAnotherHostWithTheShellKey() async throws {
        let relay = "relay.shell-key.test", local = "127.0.0.2"
        let sse = #"data: {"choices":[{"delta":{"content":"EN: Hi\n"}}]}"# + "\n\ndata: [DONE]\n\n"
        StubURLProtocol.register(host: relay, .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [Data(sse.utf8)]))
        StubURLProtocol.register(host: local, .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [Data(sse.utf8)]))
        func converter(_ base: String) -> Converter {
            var config = Config.default
            config.provider = .openai
            config.openai.baseURL = base
            config.openai.model = "deepseek-chat"
            config.rewriteStyles = []
            let fixed = config
            return Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { fixed })
        }
        await #expect(throws: ProviderError.shellKeyForAnotherHost(.openai, variable: "OPENAI_API_KEY")) {
            for try await _ in converter("https://\(relay)/v1").convert("你好") {}
        }
        #expect(StubURLProtocol.requests(host: relay).isEmpty)
        for try await _ in converter("http://\(local):11434/v1").convert("你好") {}
        #expect(StubURLProtocol.lastRequest(host: local)?.value(forHTTPHeaderField: "Authorization") == "Bearer \(openAI)")
    }
}
