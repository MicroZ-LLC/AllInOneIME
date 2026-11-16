import Foundation
import Testing
import AllInOneIMECore

/// Every host scenario (Tests/HostScenarios/, its subfolders too) replayed through the core against every profile it
/// names (`HostRun`): one test each, named by the file and the profile. A failure points at the scenario's line.
struct HostScenarioTests {
    @Test(arguments: HostScenarioFiles.runs())
    func scenario(_ run: HostScenarioRun) throws {
        let scenario: HostCase
        do {
            scenario = try HostScenarioFiles.read(run.file)
        } catch let error as HostCaseError {
            Issue.record(Comment(rawValue: "can't be read: \(error.message)"), sourceLocation: run.location(line: error.line ?? 1))
            return
        }
        guard let profile = run.profile else {
            Issue.record("\(run.file.lastPathComponent) couldn't be read when the runs were listed")
            return
        }
        let failures = UIText.$scopedInterface.withValue(UIText.ScopedInterface(choice: "en", commandTrigger: "@")) {
            HostRun(scenario, profile: profile).run()
        }
        for failure in failures {
            Issue.record(Comment(rawValue: "\(scenario.name) [\(profile.rawValue)]: \(failure.message)"),
                         sourceLocation: run.location(line: failure.line))
        }
    }

    /// The samples are there, and every file reads: one that doesn't fails its own test (`scenario`).
    @Test func theScenariosAreFound() throws {
        let files = HostScenarioFiles.all()
        #expect(files.contains { $0.pathComponents.contains("samples") }, "no samples in \(HostScenarioFiles.folder.path)")
        #expect(HostScenarioFiles.runs().count >= files.count)
    }
}

/// One file replayed against one profile; a file that can't be read is one run with no profile (its error recorded).
struct HostScenarioRun: Sendable, CustomTestStringConvertible {
    let file: URL
    let profile: HostProfile?

    var testDescription: String {
        let path = file.path.replacingOccurrences(of: HostScenarioFiles.folder.path + "/", with: "")
        return path + (profile.map { " · \($0.rawValue)" } ?? "")
    }

    func location(line: Int) -> SourceLocation {
        SourceLocation(fileID: "AllInOneIMEHostTests/\(file.lastPathComponent)", filePath: file.path, line: max(line, 1), column: 1)
    }
}

enum HostScenarioFiles {
    /// Core/Tests/HostScenarios, beside this target's folder.
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("HostScenarios")

    /// Every `.hostcase` file in the folder and its subfolders, in order.
    static func all() -> [URL] {
        guard let found = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return found.compactMap { $0 as? URL }.filter { $0.pathExtension == "hostcase" }
            .sorted { $0.path < $1.path }
    }

    static func read(_ file: URL) throws -> HostCase {
        try HostCaseParser.parse(try String(contentsOf: file, encoding: .utf8), fallbackName: file.deletingPathExtension().lastPathComponent)
    }

    /// Each file with each profile it names; a file that can't be read once, with none.
    static func runs() -> [HostScenarioRun] {
        all().flatMap { file -> [HostScenarioRun] in
            guard let scenario = try? read(file), !scenario.profiles.isEmpty else { return [HostScenarioRun(file: file, profile: nil)] }
            return scenario.profiles.sorted().map { HostScenarioRun(file: file, profile: $0) }
        }
    }
}
