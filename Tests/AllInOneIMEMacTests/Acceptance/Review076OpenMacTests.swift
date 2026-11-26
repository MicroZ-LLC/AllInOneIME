@testable import AllInOneIMEMac
import AllInOneIMECore
import Foundation
import Testing

// Reproductions for the 0.7.6 review's `@open` items that are the Mac's (AGENTS.md rule 20), written from the review's
// text by the independent test author; the core's (the folder Tab completed, LOCALHOST) are in
// Core/Tests/AllInOneIMECoreTests/Acceptance/Review076OpenTests.swift. All of it on temporary files: nothing is opened,
// no Finder, no Spotlight.
//  7. A Finder alias to a script or a program gets round "what opening would run is shown in Finder instead":
//     `FileOpenPolicy.action` follows symbolic links only, and an alias is a plain file with no execute bit, which
//     `NSWorkspace.open` then resolves and runs.
//  9. A folder named like a script ("foo.command"): its row says "open" (`SearchResult.reveals` false, a folder), but
//     ⏎ shows it in Finder (`FileOpenPolicy.action` goes by the name before it looks at what it is).
// 10. An app bundle whose extension is in capitals ("Example.APP") is listed as a folder (Tab goes into it, the folder
//     icon), where "Example.app" is an app: the extension is compared as written.

struct Review076OpenMacTests {
    /// A folder of its own under the temporary folder, removed after `body`.
    private func inScratch<T>(_ body: (URL) throws -> T) throws -> T {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("review076-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try body(folder)
    }

    /// A Finder alias at `alias` to `target` (a bookmark file, what Finder's "Make Alias" writes).
    private func makeAlias(at alias: URL, to target: URL) throws {
        let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(bookmark, to: alias)
    }

    /// The row `FileSearch.complete` lists for `name` in `folder` (a path's folder, as `@open ~/folder/` lists it).
    private func listed(_ name: String, in folder: URL) throws -> SearchResult {
        let rows = FileSearch.complete(folder.path + "/", limit: 50)
        return try #require(rows.first { ($0.path as NSString).lastPathComponent == name }, "\(name) isn't listed: \(rows.map(\.path))")
    }

    // MARK: 7. A Finder alias

    /// Item 7. An alias to what opening would run (a `.command`, a `.terminal` file, a file with an execute bit) is shown
    /// in Finder on ⏎, as a symbolic link to it is, and its row says so. (Fails today: the alias is a regular file with no
    /// execute bit and no such extension, so it is opened, and opening an alias opens what it leads to.)
    @Test(arguments: ["payload.command", "profile.terminal", "run-with-execute-bit"])
    func anAliasToWhatWouldRunIsShownInFinder(_ name: String) throws {
        try inScratch { folder in
            let target = folder.appendingPathComponent(name)
            try Data("echo safe test\n".utf8).write(to: target)
            if name == "run-with-execute-bit" {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            }
            let alias = folder.appendingPathComponent("readme")
            try makeAlias(at: alias, to: target)
            // The premise: it is an alias Finder and NSWorkspace resolve, and not a symbolic link.
            try #require(try alias.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey]).isAliasFile == true)
            try #require(try alias.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
            let resolved = try URL(resolvingAliasFileAt: alias)
            try #require(resolved.resolvingSymlinksInPath().path == target.resolvingSymlinksInPath().path)
            try #require(FileOpenPolicy.action(for: target) == .reveal, "the target itself is shown in Finder")

            #expect(FileOpenPolicy.action(for: alias) == .reveal, "⏎ on an alias to \(name) opens it: what it leads to runs")
            #expect(try listed("readme", in: folder).reveals, "the alias's row says it opens")
            #expect(FileSearch.result(for: alias.path).reveals, "the search's row for the alias says it opens")
        }
    }

    /// The control (passes today): an alias to a document or to a folder opens, as before; a symbolic link to a script
    /// is shown in Finder.
    @Test func anAliasToADocumentOrAFolderStillOpens() throws {
        try inScratch { folder in
            let document = folder.appendingPathComponent("notes.txt")
            try Data("notes\n".utf8).write(to: document)
            let inner = folder.appendingPathComponent("Inner", isDirectory: true)
            try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
            let toDocument = folder.appendingPathComponent("notes alias")
            let toFolder = folder.appendingPathComponent("inner alias")
            try makeAlias(at: toDocument, to: document)
            try makeAlias(at: toFolder, to: inner)
            #expect(FileOpenPolicy.action(for: toDocument) == .open && FileOpenPolicy.action(for: toFolder) == .open)

            let script = folder.appendingPathComponent("payload.command")
            try Data("echo safe test\n".utf8).write(to: script)
            let link = folder.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: script)
            #expect(FileOpenPolicy.action(for: link) == .reveal)
        }
    }

    // MARK: 9. A folder named like a script

    /// Item 9. What a row says ⏎ does is what ⏎ does: for a folder named "foo.command" (or .tool, .sh, .terminal) the
    /// row's `reveals` and `FileOpenPolicy.action` agree, in a path's listing and in the search's rows. A folder opens
    /// (`FileOpenPolicy`: "Folders and app bundles open"), so both say open; the test only holds them to each other.
    /// (Fails today: the row says "open", ⏎ shows it in Finder.)
    @Test(arguments: ["foo.command", "tools.tool", "scripts.sh", "profiles.terminal"])
    func aFolderNamedLikeAScriptDoesWhatItsRowSays(_ name: String) throws {
        try inScratch { folder in
            let named = folder.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: named, withIntermediateDirectories: true)
            let shown = FileOpenPolicy.action(for: URL(fileURLWithPath: named.path)) == .reveal

            let row = try listed(name, in: folder)
            #expect(row.isFolder, "\(name) is listed as a folder")
            #expect(row.reveals == shown, "\(name) listed in its folder: the row says \(row.reveals ? "show in Finder" : "open"), ⏎ does \(shown ? "show in Finder" : "open")")
            let found = FileSearch.result(for: named.path)
            #expect(found.reveals == shown, "\(name) found by the search: the row says \(found.reveals ? "show in Finder" : "open"), ⏎ does \(shown ? "show in Finder" : "open")")
        }
    }

    // MARK: 10. An app bundle in capitals

    /// Item 10. "Example.APP" is the app bundle "Example.app" is (the file system and Launch Services compare the
    /// extension whatever its capitals): not a folder, in a path's listing and in the search's rows, and not sorted with
    /// the folders. (Fails today: `hasSuffix(".app")` as written, so it's a folder Tab goes into.)
    @Test(arguments: ["Example.APP", "Example.App"])
    func anAppBundleInCapitalsIsNotAFolder(_ name: String) throws {
        try inScratch { folder in
            let app = folder.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            #expect(try !listed(name, in: folder).isFolder, "\(name) is listed as a folder in its folder")
            #expect(!FileSearch.result(for: app.path).isFolder, "\(name) found by the search is a folder")
            #expect(FileOpenPolicy.action(for: app) == .open)
        }
    }

    /// The control (passes today): "Example.app" is no folder, a plain folder is one.
    @Test func anAppBundleInSmallLettersIsNotAFolderAndAFolderIsOne() throws {
        try inScratch { folder in
            let app = folder.appendingPathComponent("Example.app", isDirectory: true)
            let plain = folder.appendingPathComponent("Plain", isDirectory: true)
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
            #expect(try !listed("Example.app", in: folder).isFolder && !FileSearch.result(for: app.path).isFolder)
            #expect(try listed("Plain", in: folder).isFolder && FileSearch.result(for: plain.path).isFolder)
        }
    }
}
