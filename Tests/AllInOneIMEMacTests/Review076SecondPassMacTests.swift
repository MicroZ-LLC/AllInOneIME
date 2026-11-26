import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import Testing

/// What the second review of the 0.7.6 fixes found in `@open` on the Mac (AGENTS.md rule 20: each failed on the code as
/// reviewed): an alias whose target is on a volume that isn't mounted had the volume mounted to judge the row, and the
/// inside of an app bundle named in capitals (`Example.APP`) was listed.
@Suite(.serialized)
struct Review076SecondPassMacTests {
    /// The files inside an app bundle aren't what `@open` lists, whatever the case of ".app" (the file system doesn't
    /// tell them apart). (Failed: only ".app/" in small letters.)
    @Test(arguments: ["Example.APP", "Example.App", "Example.app"])
    func theInsideOfAnAppBundleIsNoCandidate(_ bundle: String) {
        #expect(!FileSearch.isCandidate("/Applications/\(bundle)/Contents/Resources/readme.txt"))
        #expect(FileSearch.isCandidate("/Applications/\(bundle)"), "the app itself is")
        #expect(FileSearch.isCandidate("/Applications/Snapp/readme.txt"), "a folder whose name only ends like one is")
    }

    private func hdiutil(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// A Finder alias to a file on a disk image that isn't mounted any more: judging what ⏎ does to it (done for each
    /// row as `@open` is typed) mounts nothing and asks nothing, and the row is shown in Finder. (Failed: resolving
    /// the alias mounted the image again, as it would a share, with its sign-in.)
    @Test func anAliasToAnUnmountedVolumeMountsNothing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("open-alias-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let name = "AliasTest\(UUID().uuidString.prefix(8))"
        let image = folder.appendingPathComponent("volume.dmg"), volume = URL(fileURLWithPath: "/Volumes/\(name)")
        // Where no disk image can be made or mounted (a sandboxed runner), there is nothing to test.
        guard hdiutil(["create", "-size", "2m", "-fs", "HFS+", "-volname", name, image.path]),
              hdiutil(["attach", image.path, "-nobrowse"]) else { return }
        defer { if FileManager.default.fileExists(atPath: volume.path) { _ = hdiutil(["detach", volume.path, "-force"]) } }
        let target = volume.appendingPathComponent("notes.txt")
        try Data("notes\n".utf8).write(to: target)
        let alias = folder.appendingPathComponent("notes alias")
        try URL.writeBookmarkData(target.bookmarkData(options: .suitableForBookmarkFile), to: alias)
        #expect(FileOpenPolicy.action(for: alias) == .open, "the premise: an alias to a plain file opens it")
        try #require(hdiutil(["detach", volume.path]) && !FileManager.default.fileExists(atPath: volume.path))

        #expect(FileOpenPolicy.action(for: alias) == .reveal, "its target isn't at hand: shown in Finder")
        #expect(!FileManager.default.fileExists(atPath: volume.path), "judging the row mounted the alias's volume")
    }
}
