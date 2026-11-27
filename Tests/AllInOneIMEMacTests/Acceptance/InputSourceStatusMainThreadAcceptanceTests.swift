import AllInOneIMEMac
import Foundation
import Testing

/// The unregistered input source's registration wait, using a seam so the test never calls
/// `TISRegisterInputSource` or changes the user's input sources.
struct InputSourceStatusMainThreadAcceptanceTests {
    private let missingID = "com.example.allinoneime.never"

    @Test @MainActor func measureCurrentRegistrationWait() {
        let check = InputSourceCheck(id: missingID, state: { InputSourceState() }, register: {
            // This test-only seam models the system registration poll on the main thread.
            // swiftlint:disable:next blocking_call
            Thread.sleep(forTimeInterval: 2)
        })
        let started = Date()
        let enabled = check.isEnabled()
        let elapsed = Date().timeIntervalSince(started)
        print(String(format: "INPUT SOURCE MAIN THREAD MEASURE %.3f s", elapsed))
        #expect(!enabled)
    }

    /// Expected API: `InputSourceCheck.isEnabled(completion: @escaping @MainActor (Bool) -> Void)`.
    /// The About page can call it on the main actor; registration runs elsewhere and the answer returns here.
    @Test @MainActor func unregisteredSourceReturnsFromMainThreadBeforeRegistrationFinishes() async throws {
        let check = InputSourceCheck(id: missingID, state: { InputSourceState() }, register: {
            // This test-only seam models the system registration poll without touching macOS input sources.
            // swiftlint:disable:next blocking_call
            Thread.sleep(forTimeInterval: 2)
        })
        var answer: Bool?
        let started = Date()
        check.isEnabled(completion: { enabled in answer = enabled })
        let callElapsed = Date().timeIntervalSince(started)
        #expect(callElapsed < 0.1, "The main thread waited \(callElapsed) s for input source registration")

        let deadline = started.addingTimeInterval(3)
        while answer == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(answer == false, "The missing input source did not report disabled within 3 s")
    }
}
