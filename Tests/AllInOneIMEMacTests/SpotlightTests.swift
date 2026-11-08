import Foundation
import Testing
@testable import AllInOneIMECore

/// `Spotlight`'s process handling, with a shell standing in for mdfind.
struct SpotlightTests {
    let shell = URL(fileURLWithPath: "/bin/sh")

    /// `body` on a thread of its own (it blocks), awaited. A `Thread`, not a dispatch queue: while tests that wait for a
    /// child process fill every thread of the test run's pool, a global queue gets no thread for seconds, the time limit
    /// passes before the shell has started, and what it would print is lost.
    func inBackground<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            Thread { continuation.resume(returning: body()) }.start()
        }
    }

    @Test func stopsAtTheTimeLimitAndKeepsWhatWasPrinted() async {
        // A limit of 2 s leaves the shell time to start and print under load; it would sleep five minutes (`Timing`).
        let spotlight = Spotlight(until: .now() + 2, executable: shell)
        let started = Date()
        let output = await inBackground { spotlight.mdfind(["-c", "echo first; exec sleep \(Timing.longSleep)"]) }
        #expect(output.map { String(decoding: $0, as: UTF8.self) } == "first\n")
        #expect(Date().timeIntervalSince(started) < Timing.wellBeforeLongSleep)
        #expect(!spotlight.hasTimeLeft && !spotlight.isCancelled)
    }

    @Test func readsMoreThanAPipeHolds() async {
        // A pipe holds 64 KB: the output is read while the program runs, or neither would finish.
        // Both on the one thread: the time limit is the shells', not spent waiting for the test's turn in between.
        let spotlight = Spotlight(until: .now() + 10, executable: shell)
        let (output, both) = await inBackground {
            (spotlight.mdfind(["-c", "head -c 300000 /dev/zero | tr '\\0' x"]),
             spotlight.mdfind(each: [["-c", "echo one"], ["-c", "sleep 0.2; echo two"], ["-c", "exit 3"]]))
        }
        #expect(output?.count == 300_000 && output?.allSatisfy { $0 == UInt8(ascii: "x") } == true)
        #expect(both?.map { String(decoding: $0, as: UTF8.self) } == ["one\n", "two\n", ""])
    }

    @Test func cancellingStopsItAndDropsWhatWasPrinted() async throws {
        // Five minutes of sleep with a limit past it: only the cancel can stop it well before (`Timing`).
        let spotlight = Spotlight(until: .now() + Double(Timing.longSleep * 2), executable: shell)
        let started = Date()
        let running = Task { await inBackground { spotlight.mdfind(["-c", "echo early; exec sleep \(Timing.longSleep)"]) } }
        try await Task.sleep(for: .milliseconds(300))
        let cancelling = Date()
        spotlight.cancel()
        #expect(Date().timeIntervalSince(cancelling) < Timing.wellBeforeLongSleep)  // never waits for the process to end
        #expect(await running.value == nil)
        #expect(Date().timeIntervalSince(started) < Timing.wellBeforeLongSleep)
        // Nothing starts after that.
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("SpotlightTests-\(UUID().uuidString)")
        let later = await inBackground { spotlight.mdfind(["-c", "touch '\(marker.path)'; echo late"]) }
        let each = await inBackground { spotlight.mdfind(each: [["-c", "touch '\(marker.path)'"]]) }
        #expect(later == nil && each == nil && !FileManager.default.fileExists(atPath: marker.path))
        #expect(spotlight.isCancelled && !spotlight.hasTimeLeft)
    }

    @Test func aProgramThatCantStartPrintsNothing() async {
        let spotlight = Spotlight(until: .now() + 5, executable: URL(fileURLWithPath: "/no/such/mdfind"))
        #expect(await inBackground { spotlight.mdfind(["-name", "x"]) } == Data())
    }
}
