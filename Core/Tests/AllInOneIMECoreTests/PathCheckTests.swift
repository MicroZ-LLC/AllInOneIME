import Foundation
import Testing
@testable import AllInOneIMECore

/// Paths that a manifest, an index or the settings give relative to a folder stay in it, on every system's terms: on
/// Windows "\" is a separator too, and a drive or a share is a way out.
struct PathCheckTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString)", isDirectory: true)

    /// Out of the folder however it is spelled, on every system (here and on Windows alike).
    static let outEverywhere = ["", "..", "../x.sh", "a/../../x.sh", "a/..", "/etc/x.sh", "//server/x.sh", "\\\\server\\x.sh",
                                "\\x.sh", "C:x.sh", "C:/x.sh", "c:\\x.sh", "a\0b.sh"]
    #if os(Windows)
    /// Out of it only where "\" separates, a ":" names a drive or a stream, and trailing dots and spaces are dropped.
    static let outOnWindows = ["..\\x.sh", "a\\..\\..\\x.sh", "a/..\\..\\x.sh", "x.sh:stream", "a/C:/x.sh", "... ", ".. /x.sh", "a/ . /x.sh",
                               // A device, not a file: in any case, with an extension or not.
                               "CON", "nul", "a/NUL.sh", "aux.tar.gz", "prn ", "COM1", "lpt9.log", "a\\Com5.sh", "CONIN$", "conout$.sh"]
    #endif

    @Test func plainRelativePathsStayInTheirFolder() throws {
        // Names that only start like a Windows device's are files there too.
        for path in ["run.sh", "bin/deploy.py", "./run.sh", "a/./b.sh", "...x.sh", "a b/c.sh", "console.sh", "com10.sh", "lpt0.sh",
                     "CONFIG.sh", "nul-x.sh", "a/conin.sh"] {
            #expect(CorePaths.isPlainRelative(path), "\(path)")
            let file = try #require(CorePaths.file(path, in: folder), "\(path)")
            #expect(file.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/"), "\(path)")
        }
        // The folder itself is no file of it.
        #expect(CorePaths.file(".", in: folder) == nil)
        // A file that isn't there yet is in its folder too, however the folder is spelled (/private/tmp is /tmp).
        #expect(CorePaths.file("missing.sh", in: folder) == folder.appendingPathComponent("missing.sh"))
        #if os(macOS)
        let spelled = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        #expect(CorePaths.file("missing-\(UUID().uuidString).sh", in: spelled) != nil)
        #endif
    }

    @Test func pathsOutOfTheFolderAreRefused() {
        var out = Self.outEverywhere
        #if os(Windows)
        out += Self.outOnWindows
        #endif
        for path in out {
            #expect(!CorePaths.isPlainRelative(path), "\(path.debugDescription)")
            #expect(CorePaths.file(path, in: folder) == nil, "\(path.debugDescription)")
        }
    }

    /// A device's name ("NUL", "con.txt") is one only on Windows; elsewhere it is a file like any other.
    @Test func deviceNamesAreDevicesOnlyOnWindows() {
        #if os(Windows)
        #expect(["CON", "con", "Nul.txt", "COM9", "lpt1.a.b", "CONOUT$", "aux  "].allSatisfy { CorePaths.isDeviceName($0[...]) })
        #expect(!["COM", "COM0", "COM10", "LPT", "CONSOLE", "NULL", "xNUL", ".nul"].contains { CorePaths.isDeviceName($0[...]) })
        #else
        for path in ["CON", "nul.txt", "a/COM1", "lpt9.log", "CONIN$"] { #expect(CorePaths.isPlainRelative(path), "\(path)") }
        #endif
    }

    @Test func backslashesAreSeparatorsOnlyOnWindows() throws {
        #if os(Windows)
        #expect(CorePaths.components("a\\b/c") == ["a", "b", "c"])
        #expect(CorePaths.file("bin\\deploy.py", in: folder) == folder.appendingPathComponent("bin/deploy.py"))
        #expect(CorePaths.isAbsolute("C:\\x") && CorePaths.isAbsolute("C:/x") && CorePaths.isAbsolute("\\\\server\\x"))
        #expect(!CorePaths.isAbsolute("C:x") && !CorePaths.isAbsolute("x\\y"))
        #else
        // A name with a "\" in it is one file of the folder here.
        #expect(CorePaths.components("a\\b/c") == ["a\\b", "c"])
        #expect(try #require(CorePaths.file("..\\x.sh", in: folder)).lastPathComponent == "..\\x.sh")
        #expect(CorePaths.isAbsolute("/x") && !CorePaths.isAbsolute("C:\\x") && !CorePaths.isAbsolute("x/y"))
        #endif
    }

    /// A bundle's `"script"`: refused as a bad value (nothing read) when it leads out of the bundle's folder.
    @Test func aBundlesScriptOutOfItsFolderIsABadValue() throws {
        var out = Self.outEverywhere.filter { !$0.isEmpty && !$0.contains("\0") }
        #if os(Windows)
        out += Self.outOnWindows
        #endif
        let entries = (["ok.sh"] + out).enumerated().map { ["script": $1, "name": "c\($0)"] }
        let manifest = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "name": "tools", "commands": entries])
        var asked: [String] = []
        guard case let .success((_, commands, _, skipped)) = ExtensionStore.loadBundle(manifest, folder: folder, read: {
            asked.append($0.path)
            return nil
        }) else {
            Issue.record("the manifest didn't load")
            return
        }
        #expect(commands.isEmpty)
        #expect(asked == [folder.appendingPathComponent("ok.sh").path])
        #expect(skipped.map(\.problem) == [.notRunnable] + out.map { .badValue(key: "script", value: $0) })
    }

    /// A bundle's other paths name its own files too, from its script's folder: an `icon` image, a `status` program
    /// given as a path, a relative `currentDirectoryPath`. A program the system finds by name, the home folder and an
    /// absolute folder to run in still do; a script of the user's own may point anywhere, as before.
    @Test func aBundlesOtherPathsStayInIt() throws {
        let bin = folder.appendingPathComponent("bin", isDirectory: true), file = bin.appendingPathComponent("tool.sh")
        func make(_ keys: [String: String], _ source: ScriptCommand.Source = .bundle("tools")) -> Result<ScriptCommand, ScriptCommand.Problem> {
            ScriptCommand.make(keys.merging(["schemaVersion": "1"]) { $1 }, source: source, file: file, launch: [file.path],
                               id: "tools/tool", extensionDirectory: folder)
        }
        func inBin(_ name: String) -> URL { bin.appendingPathComponent(name).standardizedFileURL }
        let ok = try make(["icon": "icons/tool.png", "status": "./left.sh --short", "currentDirectoryPath": "data"]).get()
        #expect(ok.icon == .image(inBin("icons/tool.png")))
        #expect(ok.status?.launch == [inBin("left.sh").path, "--short"])
        #expect(ok.directory == inBin("data"))
        #expect(try make(["currentDirectoryPath": "."]).get().directory == bin.standardizedFileURL)
        #expect(try make(["currentDirectoryPath": "~"]).get().directory.path == URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path)
        #expect(try make(["status": "date +%H:%M"]).get().status?.launch == ["date", "+%H:%M"])
        #expect(try make(["icon": "hammer"]).get().icon == .symbol("hammer"))
        var out = [("icon", "../tool.png"), ("icon", "/tmp/tool.png"), ("icon", "a/../../tool.png"), ("status", "/usr/bin/pmset -g batt"),
                   ("status", "../left.sh"), ("status", "\"/bin/sh\" -c x"), ("currentDirectoryPath", ".."), ("currentDirectoryPath", "a/../..")]
        #if os(Windows)
        // A status is a command line, where two backslashes stand for one.
        out += [("icon", "C:\\tool.png"), ("icon", "\\\\server\\share\\tool.png"), ("status", "..\\\\left.cmd"), ("currentDirectoryPath", "..\\x")]
        #endif
        for (key, value) in out {
            #expect(throws: ScriptCommand.Problem.badValue(key: key, value: value)) { try make([key: value]).get() }
        }
        let own = try make(["icon": "../tool.png", "status": "../left.sh", "currentDirectoryPath": ".."], .script).get()
        #expect(own.icon == .image(folder.appendingPathComponent("tool.png").standardizedFileURL))
        #expect(own.status?.launch == [folder.appendingPathComponent("left.sh").standardizedFileURL.path])
        #expect(own.directory == folder.standardizedFileURL)
        #if !os(Windows)
        #expect(try make(["status": "/usr/bin/pmset -g batt"], .script).get().status?.launch == ["/usr/bin/pmset", "-g", "batt"])
        #endif
    }

    /// The review before Enable shows what a command's status line runs, among the programs.
    @Test func theReviewShowsTheStatusLine() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = #"{"schemaVersion": 1, "name": "tools", "commands": [{"script": "tool.sh", "name": "tool", "status": "./left.sh --short"}]}"#
        try Data(manifest.utf8).write(to: folder.appendingPathComponent(ExtensionBundle.manifestName))
        try Data("#!/bin/sh\necho\n".utf8).write(to: folder.appendingPathComponent("tool.sh"))
        var config = Config.default
        config.extensionFolders = []
        config.findRaycastScripts = false
        let review = ExtensionSourceReview.make(bundleFolder: folder, path: "", url: "file:///r.git", commit: nil, commitDate: nil, config: config)
        #expect(review.commands.map(\.status) == ["left.sh --short"])
        #expect(review.programs == ["/bin/sh tool.sh", "left.sh --short"])
        #expect(review.summary.contains("  status:    left.sh --short"))
    }

    /// A plugin's script: a file right in its folder.
    @Test func aPluginsScriptIsAFileOfItsFolder() {
        func problem(_ script: String) -> String? {
            PluginManifest(name: "stock", version: "1.0.0", type: .script, script: script).problem(appVersion: "99.0.0")
        }
        #expect(problem("main.js") == nil)
        var out = ["", "../main.js", "lib/main.js", ".main.js", "/main.js", "C:main.js", "\\\\server\\main.js"]
        #if os(Windows)
        out += ["lib\\main.js", "..\\main.js", "main.js:stream"]
        #endif
        for script in out { #expect(problem(script) == "no script", "\(script)") }
    }

    /// An extension source's bundle path in its clone.
    @Test func aSourcesBundlePathStaysInItsClone() throws {
        var out = ["..", "../x", "a/../../x", "a\0b", "\0", "ext/\0/x"]
        #if os(Windows)
        out += ["..\\x", "a\\..\\..\\x", "C:\\x", "C:x", "CON", "ext\\nul.txt"]
        #endif
        for path in out {
            let source = ExtensionSource(url: "https://example.com/r.git", path: path)
            #expect(ExtensionSources.bundleFolder(for: source, root: folder).lastPathComponent == ".invalid-bundle-path", "\(path)")
            #expect(throws: ExtensionSourceError.noBundle(path)) { try ExtensionSources.resolveBundlePath(path, in: folder) }
        }
    }

    /// A list row's path on another computer ("\\server\share\x" on Windows) is put in as text, never opened or looked
    /// for: reaching the share would hand that computer the user's sign-in. Elsewhere "//x" is this computer's "/x".
    @Test func aShareIsTextNotSomethingToOpen() {
        func open(_ arg: String) -> URL? { ScriptItem(title: "x", arg: arg, action: .open).openURL }
        for share in ["\\\\server\\share\\x.txt", "\\\\server\\share", "\\\\?\\UNC\\server\\share\\x.txt",
                      "file:////server/share/x.txt"] {
            #expect(open(share) == nil, "\(share)")
        }
        #expect(ScriptItem(title: "x", arg: "\\\\server\\share\\x.txt").action == .insert)
        #if os(Windows)
        #expect(ScriptItem.namesShare("\\\\server\\x") && ScriptItem.namesShare("//server/x") && ScriptItem.namesShare("\\/server"))
        for share in ["//server/share/x.txt", "\\\\server\\share\\x.txt", "\\\\.\\pipe\\x"] {
            #expect(ScriptItem(title: "x", arg: share).action == .insert, "\(share)")
            #expect(open(share) == nil, "\(share)")
        }
        #expect(ScriptItem(title: "x", arg: "C:\\Users\\x.txt").action == .open)
        #else
        #expect(!ScriptItem.namesShare("//x") && !ScriptItem.namesShare("\\\\server\\x"))
        #expect(ScriptItem(title: "x", arg: "//tmp").action == .open && open("//tmp") != nil)
        #endif
        #expect(!ScriptItem.namesShare("/x") && !ScriptItem.namesShare("C:/x") && !ScriptItem.namesShare("x"))
    }

    /// A language pack is data on every system: Windows' programs and scripts are code too.
    @Test func windowsProgramsAreCodeInALanguagePack() {
        for kind in ["exe", "dll", "bat", "cmd", "ps1", "vbs", "msi"] { #expect(LanguagePackStore.codeExtensions.contains(kind), "\(kind)") }
    }
}
