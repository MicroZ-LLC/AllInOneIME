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
}
