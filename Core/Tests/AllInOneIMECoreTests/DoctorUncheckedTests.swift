import Foundation
import Testing
@testable import AllInOneIMECore

/// Troubleshoot's findings told as each check ends (`Doctor.Facts.unchecked`): an area whose check hasn't ended shows
/// nothing, not even what its facts' defaults would call fine; once all have, every finding is there as before.
struct DoctorUncheckedTests {
    @Test func whatIsNotCheckedYetIsLeftOut() {
        var facts = Doctor.Facts()
        facts.config = .default
        facts.unchecked = Set(Doctor.Area.allCases).subtracting([.connection, .inputMethod, .secureInput])
        let first = Doctor.findings(facts, language: "en")
        #expect(Set(first.map(\.area)) == [.inputMethod, .secureInput], "\(first.map(\.area))")
        // The logs not read yet: no "No recent errors" before they are.
        #expect(!first.contains { $0.area == .recentErrors })
        facts.unchecked.remove(.recentErrors)
        #expect(Doctor.findings(facts, language: "en").contains { $0.area == .recentErrors && $0.status == .ok })
        // All checked: the same findings as facts told whole.
        facts.unchecked = []
        var whole = facts
        whole.unchecked = []
        #expect(Doctor.findings(facts, language: "en") == Doctor.findings(whole, language: "en"))
        #expect(Doctor.findings(facts, language: "en").count > first.count)
    }

    /// Checks run again: what the last ones found stays for the areas not checked again yet, in Doctor's order (problems
    /// first), never "Everything looks good" for a moment.
    @Test func checksRunAgainKeepWhatTheLastFoundMeanwhile() {
        var before = Doctor.Facts()
        before.config = .default
        before.accessibility = .denied
        let last = Doctor.findings(before, language: "en")
        #expect(last.contains { $0.area == .permissions && $0.status != .ok })
        var partial = Doctor.Facts()
        partial.unchecked = Set(Doctor.Area.allCases).subtracting([.connection, .inputMethod, .secureInput, .iCloudSync])
        let shown = Doctor.findings(partial, language: "en", keeping: last)
        #expect(shown.contains { $0.area == .permissions && $0.status != .ok }, "the problem stays while it's checked again")
        #expect(shown.first?.status != .ok && Set(shown.map(\.area)) == Set(last.map(\.area)))
        #expect(shown == Doctor.ordered(shown))
        // All checked: only the new ones.
        partial.unchecked = []
        partial.config = .default
        partial.accessibility = .granted
        #expect(Doctor.findings(partial, language: "en", keeping: last) == Doctor.findings(partial, language: "en"))
    }

    /// The connection test is never one of them: its row says it runs, then how it went.
    @Test func theConnectionTestShowsWhileItRuns() {
        var facts = Doctor.Facts()
        facts.config = .default
        facts.unchecked = [.permissions]
        facts.connection = .running
        #expect(Doctor.findings(facts, language: "en").contains { $0.area == .connection })
        #expect(!Doctor.findings(facts, language: "en").contains { $0.area == .permissions })
    }
}
