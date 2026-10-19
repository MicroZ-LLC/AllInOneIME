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
        store.removeValue(forKey: "a")
        #expect(store.string(forKey: "a") == nil)
    }

    /// Each value set, and what string, Boolean and data reading it as each type gives.
    static let readings: [(set: @Sendable (any KeyValueStore) -> Void, string: String?, bool: Bool, data: Data?)] = [
        ({ $0.set(true, forKey: "k") }, "1", true, nil),
        ({ $0.set(false, forKey: "k") }, "0", false, nil),
        ({ $0.set("true", forKey: "k") }, "true", true, nil),
        ({ $0.set("TRUE", forKey: "k") }, "TRUE", true, nil),
        ({ $0.set("yEs", forKey: "k") }, "yEs", true, nil),
        ({ $0.set("1", forKey: "k") }, "1", true, nil),
        ({ $0.set("2", forKey: "k") }, "2", false, nil),
        ({ $0.set(" yes", forKey: "k") }, " yes", false, nil),
        ({ $0.set("y", forKey: "k") }, "y", false, nil),
        ({ $0.set("no", forKey: "k") }, "no", false, nil),
        ({ $0.set("", forKey: "k") }, "", false, nil),
        ({ $0.set(Data("hi".utf8), forKey: "k") }, nil, false, Data("hi".utf8)),
    ]

    /// A value read as another type reads as UserDefaults reads it, so what a shell keeps in its own store and the tests'
    /// memory agree.
    @Test func memoryStoreReadsOtherTypesAsUserDefaultsDoes() {
        for (index, reading) in Self.readings.enumerated() {
            let store = MemoryKeyValueStore()
            reading.set(store)
            #expect(store.string(forKey: "k") == reading.string && store.bool(forKey: "k") == reading.bool
                    && store.data(forKey: "k") == reading.data, "reading \(index)")
        }
    }

    #if canImport(Darwin)
    @Test func userDefaultsReadsTheSame() throws {
        let suite = "AllInOneIMECoreTests.PlatformSeam.\(UUID().uuidString)"
        let store = try #require(UserDefaultsStore(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        for (index, reading) in Self.readings.enumerated() {
            store.removeValue(forKey: "k")
            reading.set(store)
            #expect(store.string(forKey: "k") == reading.string && store.bool(forKey: "k") == reading.bool
                    && store.data(forKey: "k") == reading.data, "reading \(index)")
        }
    }
    #endif

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

    /// AWS checks a request's signature against the real time, and credentials expire by it: a shell's or a test's clock
    /// changes neither.
    @Test func signingAndCredentialsGoByTheRealTime() throws {
        let fixed = Platform(defaults: MemoryKeyValueStore(), clock: FixedWallClock(Date(timeIntervalSince1970: 1_000_000)))
        try Platform.$override.withValue(fixed) {
            let today = SigV4Signer.amzDate(Date()).prefix(8)  // yyyyMMdd
            var request = URLRequest(url: try #require(URL(string: "https://bedrock-runtime.us-east-1.amazonaws.com/x")))
            SigV4Signer(credentials: AWSCredentials(accessKeyId: "AKID", secretAccessKey: "secret"), region: "us-east-1",
                        service: "bedrock").sign(&request, body: Data())
            #expect(request.value(forHTTPHeaderField: "X-Amz-Date")?.hasPrefix(today) == true)
            #expect(abs(AWSCredentialContext().now().timeIntervalSinceNow) < 60)
            // Credentials that expire in ten seconds: the settings look again then (by the fixed clock, decades away).
            var status = AWSProfileStatus(profile: "p")
            status.hasCredentials = true
            status.expiration = Date().addingTimeInterval(10)
            #expect((9...11).contains(status.secondsUntilChange()))
        }
    }

    /// A default clock is the one of the platform in use where the value is made: read then, it holds on another queue,
    /// which doesn't see `Platform.$override`.
    @Test func defaultClocksAreReadWhereTheyAreMade() async {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let fixed = Platform(defaults: MemoryKeyValueStore(), clock: FixedWallClock(start))
        let manager = Platform.$override.withValue(fixed) { ExtensionSourceManager(git: SwapRecoveryTests.NoGit()) }
        let elsewhere = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: manager.now()) }
        }
        #expect(elsewhere == start && manager.now() == start)
    }
}
