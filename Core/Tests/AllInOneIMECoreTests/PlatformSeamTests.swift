import Foundation
import Testing
@testable import AllInOneIMECore

/// The platform's small-value store and clock (`Platform.defaults`, `Platform.clock`).
struct PlatformSeamTests {
    @Test func memoryStoreKeepsTypedValues() {
        let store = MemoryKeyValueStore()
        #expect(store.data(forKey: "a") == nil && store.string(forKey: "a") == nil && !store.bool(forKey: "a"))
        store.set("x", forKey: "a")
        store.set(true, forKey: "b")
        store.set(Data([1, 2]), forKey: "c")
        #expect(store.string(forKey: "a") == "x" && store.bool(forKey: "b") && store.data(forKey: "c") == Data([1, 2]))
        #expect(store.data(forKey: "a") == nil && !store.bool(forKey: "a"))
        store.removeValue(forKey: "a")
        #expect(store.string(forKey: "a") == nil)
    }

    @Test func aClockATestMoves() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = FixedWallClock(start)
        #expect(clock.now == start)
        clock.advance(by: 90)
        #expect(clock.now == start.addingTimeInterval(90))
        let platform = Platform(defaults: MemoryKeyValueStore(), clock: clock)
        Platform.$override.withValue(platform) {
            #expect(Platform.current.clock.now == start.addingTimeInterval(90))
            // What the core dates goes by it.
            #expect(NoteDraft(text: "x").created == start.addingTimeInterval(90))
        }
    }
}
