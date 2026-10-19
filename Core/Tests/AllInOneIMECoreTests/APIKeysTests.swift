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
