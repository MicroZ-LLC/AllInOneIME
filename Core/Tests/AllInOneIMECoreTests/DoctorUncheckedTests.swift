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
