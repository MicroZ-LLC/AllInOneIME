import Foundation
import Testing
@testable import AllInOneIMECore

/// The stand-ins macOS keeps in /usr/bin for the developer tools (`DeveloperTools`, moved with it from InlineCodeTests).
struct DeveloperToolsTests {
    @Test func standInsCountOnlyWithTheDeveloperTools() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("inline-code-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let standIn = folder.appendingPathComponent("stand-in")
        let other = folder.appendingPathComponent("other")
        try Data("#!/bin/sh\n".utf8).write(to: standIn)
        try Data("#!/bin/sh\n".utf8).write(to: other)
        let hardLink = folder.appendingPathComponent("python3")
        try fm.linkItem(at: standIn, to: hardLink)
        let symbolicLink = folder.appendingPathComponent("git")
        try fm.createSymbolicLink(at: symbolicLink, withDestinationURL: hardLink)
        // One file under several names, also through a symbolic link.
        #expect(DeveloperTools.isStandIn(hardLink, standIn: standIn.path) && DeveloperTools.isStandIn(symbolicLink, standIn: standIn.path))
        #expect(!DeveloperTools.isStandIn(other, standIn: standIn.path))
        #expect(!DeveloperTools.isStandIn(folder.appendingPathComponent("missing"), standIn: standIn.path))
        // The tools are there when a developer folder has its usr/bin.
        let tools = folder.appendingPathComponent("CommandLineTools")
        try fm.createDirectory(at: tools.appendingPathComponent("usr/bin"), withIntermediateDirectories: true)
        #expect(DeveloperTools.installed(in: [folder.appendingPathComponent("Xcode").path, tools.path]))
        #expect(!DeveloperTools.installed(in: [folder.appendingPathComponent("Xcode").path]) && !DeveloperTools.installed(in: []))
        #expect(DeveloperTools.folders.suffix(2) == ["/Applications/Xcode.app/Contents/Developer", "/Library/Developer/CommandLineTools"])
        // /usr/bin/python3 is a stand-in: it counts only with Xcode or the command line tools.
        #expect(!CommandRunner.isInstalled("python3", path: "/usr/bin", developerFolders: []))
        #expect(CommandRunner.isInstalled("python3", path: "/usr/bin", developerFolders: [tools.path])
            == fm.isExecutableFile(atPath: "/usr/bin/python3"))
        #expect(CommandRunner.isInstalled("sh", path: "/bin", developerFolders: []))  // a program of its own
        #expect(!CommandRunner.isInstalled("no-such-program-here", path: "/bin:/usr/bin"))
    }
}
