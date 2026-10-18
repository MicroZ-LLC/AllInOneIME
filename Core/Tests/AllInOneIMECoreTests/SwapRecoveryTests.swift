import Foundation
import Testing
@testable import AllInOneIMECore

/// Where a folder swap isn't one step (Windows), the old folder is renamed aside for a moment (".<name>.swap-<UUID>"):
/// nothing lists it, leftovers' removal keeps it, and an interrupted swap is put right before the next one and where the
/// folders are read.
struct SwapRecoveryTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("swap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func folderHolding(_ name: String, _ text: String) throws -> URL {
        let url = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url.appendingPathComponent("marker"))
        return url
    }

    func marker(_ url: URL) -> String? { try? String(contentsOf: url.appendingPathComponent("marker"), encoding: .utf8) }
    var names: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }

    @Test func theAsideIsHiddenAndNamesWhereItCameFrom() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let aside = SystemFileOps.swapAside(for: folder.appendingPathComponent("stock", isDirectory: true))
        #expect(aside.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(aside.lastPathComponent.hasPrefix(".stock.swap-"))
        #expect(SystemFileOps.swappedName(aside.lastPathComponent) == "stock")
        #expect(SystemFileOps.swappedName(".a.b.swap-\(UUID().uuidString)") == "a.b")
        for name in ["stock", ".stock", ".stock.tmp", "stock.swap-\(UUID().uuidString)", "..swap-\(UUID().uuidString)", ".stock.swap-x"] {
            #expect(SystemFileOps.swappedName(name) == nil, "\(name)")
        }
        // An old aside on its way to be deleted is no aside: no swap or recovery takes it back.
        let trash = SystemFileOps.trashName(for: folder.appendingPathComponent("stock")).lastPathComponent
        #expect(trash.hasPrefix(".stock.trash-") && SystemFileOps.trashedName(trash) == "stock" && SystemFileOps.swappedName(trash) == nil)
        #expect(SystemFileOps.trashedName(aside.lastPathComponent) == nil)
    }

    @Test func pluginsSkipTheAside() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifest = try JSONEncoder().encode(PluginManifest(name: "stock", version: "1.0.0", type: .prompt, prompt: "Say it"))
        for name in ["stock", SystemFileOps.swapAside(for: folder.appendingPathComponent("stock")).lastPathComponent] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
            try manifest.write(to: folder.appendingPathComponent(name).appendingPathComponent("plugin.json"))
        }
        let (plugins, skipped) = PluginStore.load(from: folder)
        #expect(plugins.map(\.name) == ["stock"] && skipped.isEmpty)
    }

    struct NoGit: GitRunning {
        func run(_ arguments: [String], in directory: URL?) async throws -> GitResult { throw CocoaError(.featureUnsupported) }
    }

    @Test func leftoversKeepTheAside() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let aside = SystemFileOps.swapAside(for: folder.appendingPathComponent("tmp-tools")).lastPathComponent
        for name in [aside, ".tmp-1234", ".old-1234", "tmp-tools"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        ExtensionSourceManager(root: folder, git: NoGit(), now: { Date.distantFuture }).removeLeftovers(olderThan: 0)
        #expect(names == [aside, "tmp-tools"].sorted())
    }

    #if os(Windows)
    @Test func anInterruptedSwapIsPutRight() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        // Stopped between the two renames: the old one goes back.
        _ = try folderHolding(SystemFileOps.swapAside(for: folder.appendingPathComponent("place")).lastPathComponent, "old")
        SystemFileOps().recoverInterruptedSwaps(in: folder)
        #expect(names == ["place"] && marker(folder.appendingPathComponent("place")) == "old")
        // Stopped after them: the new one stays, the old one is deleted.
        _ = try folderHolding(SystemFileOps.swapAside(for: folder.appendingPathComponent("place")).lastPathComponent, "older")
        SystemFileOps().recoverInterruptedSwaps(in: folder)
        #expect(names == ["place"] && marker(folder.appendingPathComponent("place")) == "old")
        // Before the next install, through moveIntoPlace.
        _ = try folderHolding(SystemFileOps.swapAside(for: folder.appendingPathComponent("other")).lastPathComponent, "other")
        let new = try folderHolding("new", "new")
        try PluginLibrary.moveIntoPlace(new, folder.appendingPathComponent("place", isDirectory: true))
        #expect(names == ["other", "place"] && marker(folder.appendingPathComponent("other")) == "other")
        #expect(marker(folder.appendingPathComponent("place")) == "new")
        // What a recovery was deleting when it stopped: deleted.
        _ = try folderHolding(SystemFileOps.trashName(for: folder.appendingPathComponent("place")).lastPathComponent, "older")
        SystemFileOps().recoverInterruptedSwaps(in: folder)
        #expect(names == ["other", "place"])
    }

    @Test func theFoldersReadersPutItRight() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        // The plugins: the old plugin back in place before the listing.
        let manifest = try JSONEncoder().encode(PluginManifest(name: "stock", version: "1.0.0", type: .prompt, prompt: "Say it"))
        let aside = try folderHolding(SystemFileOps.swapAside(for: folder.appendingPathComponent("stock")).lastPathComponent, "old")
        try manifest.write(to: aside.appendingPathComponent("plugin.json"))
        #expect(PluginStore.load(from: folder).plugins.map(\.name) == ["stock"] && names == ["stock"])
        // A language pack's folder.
        let packs = folder.appendingPathComponent("packs", isDirectory: true)
        let store = LanguagePackStore(directory: packs)
        try FileManager.default.createDirectory(at: packs, withIntermediateDirectories: true)
        let packAside = SystemFileOps.swapAside(for: store.folder(.chinesePinyin))
        try FileManager.default.createDirectory(at: packAside, withIntermediateDirectories: true)
        _ = store.installed(.chinesePinyin)
        #expect(FileManager.default.fileExists(atPath: store.folder(.chinesePinyin).path) && !FileManager.default.fileExists(atPath: packAside.path))
        // The extension sources' folder.
        let sources = folder.appendingPathComponent("sources", isDirectory: true)
        let clone = sources.appendingPathComponent("tools-1a2b3c4d", isDirectory: true)
        let cloneAside = SystemFileOps.swapAside(for: clone)
        try FileManager.default.createDirectory(at: cloneAside, withIntermediateDirectories: true)
        _ = ExtensionSources.loadFolders(Config.default, found: [], statuses: [:], root: sources)
        #expect(FileManager.default.fileExists(atPath: clone.path) && !FileManager.default.fileExists(atPath: cloneAside.path))
    }

    @Test func aFolderHeldOpenIsInUse() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let place = try folderHolding("place", "old"), new = try folderHolding("new", "new")
        let held = try FileHandle(forReadingFrom: place.appendingPathComponent("marker"))
        let start = Date()
        let error = #expect(throws: FileInUseError.self) { try SystemFileOps().swap(new, into: place, exists: true) }
        #expect(error?.path == place.path && [5, 32].contains(error?.code))  // ERROR_ACCESS_DENIED, ERROR_SHARING_VIOLATION
        // Tried for about 1.5 s, and nothing changed.
        #expect(Date().timeIntervalSince(start) >= 1.2)
        #expect(names == ["new", "place"] && marker(place) == "old" && marker(new) == "new")
        // Let go while it tries: swapped.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { try? held.close() }
        try SystemFileOps().swap(new, into: place, exists: true)
        #expect(names == ["new", "place"] && marker(place) == "new" && marker(new) == "old")
    }
    #else
    @Test func recoveryIsNothingWhereASwapIsOneStep() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let aside = try folderHolding(SystemFileOps.swapAside(for: folder.appendingPathComponent("place")).lastPathComponent, "old")
        SystemFileOps().recoverInterruptedSwaps(in: folder)
        #expect(names == [aside.lastPathComponent])
    }
    #endif
}
