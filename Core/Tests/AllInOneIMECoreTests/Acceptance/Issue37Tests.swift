import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Issue #37: a bundle whose extension.json is over 64 KB (some 200 multi-line snippets) fails to load: every command
// and snippet of the valid bundle disappears and the user is told the file "isn't a JSON object". A source with such a
// bundle can't be enabled, and an added folder that is itself the bundle has its scripts read as loose scripts with no
// bundle settings. Expected: the bundle loads; docs/extensions.md names no size limit for the manifest. Loaded as the
// input method loads extensions (`ExtensionStore.load`), and reviewed as Enable does (`ExtensionSourceReview.make`).

/// A snippet name of letters only: "noteaa", "noteab", … (no digits, so nothing else about names is in play).
private func issue37Name(_ i: Int) -> String {
    let letters = Array("abcdefghijklmnopqrstuvwxyz")
    return "note" + String(letters[i / 26 % 26]) + String(letters[i % 26])
}

/// A multi-line snippet text of some 400 bytes, its name in its first and last lines.
private func issue37Text(_ name: String) -> String {
    (["Hello from \(name),"]
        + (1...6).map { "Line \($0): thanks for writing in. We have looked into your request and will follow up shortly." }
        + ["Regards, \(name)"]).joined(separator: "\n")
}

/// A valid bundle `name` with the command `hello` (hello.sh) and `count` multi-line snippets, as JSON.
private func issue37Manifest(_ name: String, snippets count: Int) -> String {
    let snippets: [[String: Any]] = (0..<count).map { i in
        let name = issue37Name(i)
        return ["name": name, "summary": "Reply template \(i + 1)", "text": issue37Text(name)]
    }
    let json: [String: Any] = ["schemaVersion": 1, "name": name,
                               "commands": [["script": "hello.sh", "name": "hello", "title": "Hello"]],
                               "snippets": snippets]
    let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private let issue37Script = "#!/bin/bash\necho hello\n"

@Suite struct Issue37Tests {
    let big = issue37Manifest("b", snippets: 200)

    @Test func theManifestIsOver64KB() {
        #expect(big.utf8.count > 64 * 1024, "\(big.utf8.count) bytes")
        #expect((try? JSONSerialization.jsonObject(with: Data(big.utf8))) is [String: Any])
    }

    @Test func aSmallBundleLoads() {
        // The control: the same bundle with a few snippets loads today.
        let folder = ScriptFolder()
        folder.add("b/extension.json", issue37Manifest("b", snippets: 3))
        folder.add("b/hello.sh", issue37Script)
        let index = folder.load()
        #expect(index.bundles.map(\.name) == ["b"])
        #expect(index.snippets.map(\.name) == (0..<3).map(issue37Name))
        #expect(index.commands.map(\.name) == ["hello"])
        #expect(index.skipped.isEmpty, "\(index.skipped)")
    }

    @Test func aBundleOver64KBInAnAddedFolderLoads() {
        let folder = ScriptFolder()
        folder.add("b/extension.json", big)
        folder.add("b/hello.sh", issue37Script)
        let index = folder.load()
        #expect(index.bundles.map(\.name) == ["b"])
        #expect(index.skipped.isEmpty, "\(index.skipped.map(\.problem))")
        #expect(index.snippets.count == 200)
        // Every snippet, in order and whole (all its lines), the last one too.
        let wrong = index.snippets.enumerated().filter { $1.name != issue37Name($0) || $1.text != issue37Text(issue37Name($0)) }
        #expect(wrong.isEmpty, "\(wrong.map(\.element.name))")
        #expect(index.snippets.last?.name == "notehr")
        #expect(index.snippets.last?.text == issue37Text("notehr"))
        #expect(index.commands.map(\.name) == ["hello"])
        #expect(index.commands.map(\.source) == [.bundle("b")])
        // And they are offered as @ commands.
        let catalog = Command.catalog([], scripts: index.commands, snippets: index.snippets)
        #expect(catalog.contains { $0.name == "notehr" && $0.kind == .snippet })
        #expect(catalog.contains { $0.name == "hello" })
    }

    @Test func anAddedFolderThatIsABundleOver64KBLoadsAsTheBundle() {
        // The folder added is the bundle itself: its script is the bundle's command, not a loose script.
        let folder = ScriptFolder()
        folder.add("extension.json", big)
        folder.add("hello.sh", issue37Script)
        let index = folder.load()
        #expect(index.bundles.map(\.name) == ["b"])
        #expect(index.skipped.isEmpty, "\(index.skipped.map(\.problem))")
        #expect(index.snippets.count == 200)
        #expect(index.commands.map(\.name) == ["hello"])
        #expect(index.commands.map(\.source) == [.bundle("b")])
    }

    @Test func aSourceWithABundleOver64KBCanBeEnabled() {
        let folder = ScriptFolder()
        folder.add("extension.json", big)
        folder.add("hello.sh", issue37Script)
        // As an extension source's folder is loaded: only ever the bundle it is.
        let index = ExtensionStore.load([ExtensionStore.Folder(path: folder.url.path, found: false, bundleOnly: true)])
        #expect(index.bundles.map(\.name) == ["b"])
        #expect(index.skipped.isEmpty, "\(index.skipped.map(\.problem))")
        #expect(index.snippets.count == 200)
        #expect(index.commands.map(\.name) == ["hello"])
        // The review before Enable finds nothing wrong with it.
        var config = Config.default
        config.extensionFolders = []
        config.findRaycastScripts = false
        let review = ExtensionSourceReview.make(bundleFolder: folder.url, path: "", url: "file:///r.git", commit: nil,
                                                commitDate: nil, config: config)
        #expect(review.problem == nil, "\(String(describing: review.problem))")
        #expect(review.bundle?.name == "b")
        #expect(review.snippets.count == 200)
        #expect(review.commands.map(\.name) == ["hello"])
    }
}
