import Foundation
import Testing
@testable import AllInOneIMECore

/// The status lines' last values kept across launches (`StatusFile`, `StatusSchedule.kept`): shown at once after a launch,
/// until they're refreshed as their refresh time says.
struct StatusFileTests {
    func command(_ name: String, refresh: TimeInterval = 60) -> ScriptCommand {
        ScriptCommand(id: name, file: URL(fileURLWithPath: "/x/\(name).sh"), name: name,
                      status: ScriptCommand.Status(launch: ["/x/\(name).sh"], refresh: refresh, isSelf: true))
    }

    @Test func theLastValuesShowAfterALaunchUntilRefreshed() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("status-file-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = StatusFile(url: folder.appendingPathComponent("script-statuses.json"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var schedule = StatusSchedule()
        _ = schedule.due([command("mail"), command("build")], now: now)
        let changed = schedule.finished("mail", line: "3 unread", now: now)
        let failed = schedule.finished("build", line: nil, now: now)
        #expect(changed && !failed)
        file.write(schedule.kept)
        // Readable by the user only; a failed status with no value isn't kept.
        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(file.read() == ["mail": StatusSchedule.Kept(text: "3 unread", at: now)])

        // The next launch: shown at once, run again only once its refresh time is up.
        var next = StatusSchedule(kept: file.read())
        #expect(next.text(for: "mail") == "3 unread")
        let early = next.due([command("mail")], now: now.addingTimeInterval(30))
        let due = next.due([command("mail")], now: now.addingTimeInterval(61)).map(\.id)
        #expect(early.isEmpty && due == ["mail"])
        #expect(next.text(for: "mail") == "3 unread", "shown while it runs again")
        let refreshed = next.finished("mail", line: "5 unread", now: now.addingTimeInterval(62))
        #expect(refreshed && next.text(for: "mail") == "5 unread")

        // None left: the file goes; one that doesn't read is none.
        file.write([:])
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file.url)
        #expect(file.read().isEmpty)
    }

    @Test func theNewestAreKept() {
        var schedule = StatusSchedule()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let commands = (0..<(StatusFile.limit + 10)).map { command("c\($0)") }
        for (index, command) in commands.enumerated() {
            _ = schedule.due([command], now: start)
            schedule.finished(command.id, line: "\(index)", now: start.addingTimeInterval(TimeInterval(index)))
        }
        let kept = schedule.kept
        #expect(kept.count == StatusFile.limit && kept["c0"] == nil && kept["c\(StatusFile.limit + 9)"]?.text == "\(StatusFile.limit + 9)")
    }
}
