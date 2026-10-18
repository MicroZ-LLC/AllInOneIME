import Foundation
@testable import AllInOneIMECore

// The script extensions' fixtures, for the tests of extensions here and in AllInOneIMEMacTests (linked there).

/// A folder of scripts made for one test, removed after it.
final class ScriptFolder {
    let url: URL

    init() {
        let made = FileManager.default.temporaryDirectory.appendingPathComponent("extensions-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        // /private/var/…, as the folder's listing names its files (`resolvingSymlinksInPath` gives /var/… back).
        url = URL(fileURLWithPath: realpath(made.path, nil).map { defer { free($0) }; return String(cString: $0) } ?? made.path,
                  isDirectory: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Writes `name` (folders made as needed) with `text`, executable unless `executable` is false.
    @discardableResult
    func add(_ name: String, _ text: String, executable: Bool = true) -> URL {
        let file = url.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: file)
        try? FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: file.path)
        return file
    }

    var folder: ExtensionStore.Folder { ExtensionStore.Folder(path: url.path, found: false) }

    func load(cache: ExtensionCache = ExtensionCache()) -> ExtensionIndex { ExtensionStore.load([folder], cache: cache) }
}

/// A bash script with `@allinoneime.` keys (`prefix` "raycast" for Raycast's): `extra` metadata lines, then `body`.
func script(_ extra: [String] = [], prefix: String = "allinoneime", _ body: String = "echo hi") -> String {
    (["#!/bin/bash", "# @\(prefix).schemaVersion 1"] + extra.map { "# @\(prefix).\($0)" } + [body]).joined(separator: "\n") + "\n"
}

/// A Raycast script: its title and mode, then `extra`.
func raycast(title: String = "Test", mode: String = "compact", _ extra: [String] = [], _ body: String = "echo hi") -> String {
    script(["title \(title)", "mode \(mode)"] + extra, prefix: "raycast", body)
}
