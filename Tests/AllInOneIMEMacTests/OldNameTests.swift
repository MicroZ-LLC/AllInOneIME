import Foundation
import Testing

/// From 0.7.2 on, the name AllInOneIME's system identity had before (the input method's first name) is in no file of the
/// repository, in any case: code, tests, fixtures, plists, scripts, the Makefile, docs, the changelogs, the site. Only
/// git's history has it. (It is spelled here in pieces, so that this file doesn't have it either.)
struct OldNameTests {
    @Test func noFileOfTheRepositoryHasTheOldName() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // The files git tracks, and those it would (new, not ignored).
        git.arguments = ["-C", root.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
        let output = Pipe()
        git.standardOutput = output
        git.standardError = FileHandle.nullDevice
        try git.run()
        let listed = output.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        try #require(git.terminationStatus == 0, "git ls-files failed in \(root.path)")
        let paths = listed.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        try #require(paths.count > 100)

        let name = Data(("ai" + "pin" + "yin").utf8)
        var found: [String] = []
        for path in paths {
            if path.lowercased().contains(String(decoding: name, as: UTF8.self)) {
                found.append(path)
                continue
            }
            // A file deleted and not committed yet isn't there to read.
            guard let data = FileManager.default.contents(atPath: root.appendingPathComponent(path).path) else { continue }
            // ASCII letters lowercased, byte by byte: the name in any case, in any file (a binary one too).
            let lowered = Data(data.map { (0x41...0x5A).contains($0) ? $0 | 0x20 : $0 })
            if lowered.range(of: name) != nil { found.append(path) }
        }
        #expect(found.isEmpty, "the old name is in \(found.count) file(s): \(found.joined(separator: ", "))")
    }
}
