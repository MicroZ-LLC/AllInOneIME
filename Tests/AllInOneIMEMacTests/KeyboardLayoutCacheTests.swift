import AllInOneIMEMac
import Foundation
import Testing

/// `KeyboardLayout.cached(id:)` (0.7.6): the layout a language is set to type with is looked up once, not with every
/// key (listing the installed layouts takes a millisecond or two), and again once the input sources change.
@Suite(.serialized)
struct KeyboardLayoutCacheTests {
    /// Counts the lookups (any thread).
    final class Lookups: @unchecked Sendable {
        private let lock = NSLock()
        private var made = 0
        var count: Int { lock.withLock { made } }
        func add() { lock.withLock { made += 1 } }
    }

    @Test func aLayoutIsLookedUpOnceUntilTheInputSourcesChange() {
        let cache = KeyboardLayout.Cache.shared
        let before = cache.lookUp
        defer { cache.lookUp = before }
        let lookups = Lookups()
        cache.lookUp = { _ in
            lookups.add()
            return KeyboardLayout.current()
        }
        for _ in 0..<5 { _ = KeyboardLayout.cached(id: "com.example.keylayout.Test") }
        #expect(lookups.count == 1, "keys after the first take the layout kept: \(lookups.count)")
        cache.forget()  // the selected or enabled input sources changed
        for _ in 0..<5 { _ = KeyboardLayout.cached(id: "com.example.keylayout.Test") }
        #expect(lookups.count == 2, "looked up once more: \(lookups.count)")
    }

    @Test func aLayoutNotInstalledIsLookedUpOnceToo() {
        let cache = KeyboardLayout.Cache.shared
        let before = cache.lookUp
        defer { cache.lookUp = before }
        let lookups = Lookups()
        cache.lookUp = { _ in
            lookups.add()
            return nil
        }
        for _ in 0..<3 { #expect(KeyboardLayout.cached(id: "com.example.keylayout.Missing") == nil) }
        #expect(lookups.count == 1)
    }
}
