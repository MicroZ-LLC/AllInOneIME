import AllInOneIMECore
import Foundation
import Testing

/// The system identity since 0.7.2 (`SystemIdentity`): an installed copy told apart by its bundle ID alone, and the
/// update that moved this Mac to it.
struct SystemIdentityTests {
    static let other = "com.example.inputmethod.Before"

    @Test func anInstallIsToldApartByItsBundleID() {
        var asked = 0
        func check(_ answer: String?) -> () -> String? { { asked += 1; return answer } }
        #expect(SystemIdentity.installed(info: nil, check: check(nil)) == .none)
        #expect(SystemIdentity.installed(info: ["CFBundleIdentifier": Updater.bundleID, "CFBundleShortVersionString": "0.7.2.1"],
                                         check: check(nil)) == .this)
        // This identity's is never asked to move.
        #expect(asked == 0)
        let before: [String: Any] = ["CFBundleIdentifier": Self.other, "CFBundleShortVersionString": "0.7.1"]
        #expect(SystemIdentity.installed(info: before, check: check("migrate-identity: 1")) == .movable(version: "0.7.1"))
        // An earlier version: the option is unknown to it (it says so, and fails), or it answers nothing at all.
        #expect(SystemIdentity.installed(info: before, check: check("unknown option --migrate-identity")) == .tooOld(version: "0.7.1"))
        #expect(SystemIdentity.installed(info: [:], check: check(nil)) == .tooOld(version: nil))
        #expect(asked == 3)
    }

    @Test func anUpdateFromAVersionBeforeTheIdentityMovedThisMac() {
        #expect(SystemIdentity.moved(UpdateResult(from: "0.7.1", to: "0.7.2", ok: true)))
        #expect(SystemIdentity.moved(UpdateResult(from: "0.6.9", to: "0.7.4", ok: true)))
        #expect(!SystemIdentity.moved(UpdateResult(from: "0.7.1", to: "0.7.2", ok: false, error: "rolled back")))
        #expect(!SystemIdentity.moved(UpdateResult(from: "0.7.2", to: "0.7.2.1", ok: true)))
        // The helper's "none" (nothing was installed) and an unreadable version aren't a version before it.
        #expect(!SystemIdentity.moved(UpdateResult(from: "none", to: "0.7.2", ok: true)))
        #expect(!SystemIdentity.moved(UpdateResult(from: "?", to: "0.7.2", ok: true)))
    }

    /// Started right after the move with its input source not added yet (macOS leaves that to the user): the step to add
    /// it is the first thing shown; once it is added, the permissions; nothing of the kind after any other launch.
    @Test func theStepToAddTheInputSourceIsShownFirstAfterTheMove() {
        let moved = UpdateResult(from: "0.7.1", to: "0.7.2", ok: true)
        #expect(SystemIdentity.firstShown(after: moved, inputSourceEnabled: false) == .inputSourceStep)
        #expect(SystemIdentity.firstShown(after: moved, inputSourceEnabled: true) == .permissions)
        for result in [nil, UpdateResult(from: "0.7.2", to: "0.7.2.1", ok: true), UpdateResult(from: "0.7.1", to: "0.7.2", ok: false)] {
            #expect(SystemIdentity.firstShown(after: result, inputSourceEnabled: false) == .nothing)
            #expect(SystemIdentity.firstShown(after: result, inputSourceEnabled: true) == .nothing)
        }
    }
}
