import AppKit
import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMEMac

/// The own icons of what the panel's rows open (`ItemIcons`), with a stand-in for Finder's icons: what is kept is drawn
/// from memory, a row that asks before its icon is in is told once it is, nothing is read twice, a path with none keeps
/// the symbol, and past the limit the least recently used go. What `InstantFiles` keeps is told for its icons as it is
/// kept. Finder's own, on a folder of this test's.
struct ItemIconsTests {
    /// A stand-in loader: an empty image of the rows' size for each path but those in `none`, every read counted; with a
    /// `gate`, each read waits for it to open.
    final class Loader: @unchecked Sendable {
        let reads = Locked<[String]>(initialState: [])
        let none: Set<String>
        let gate: DispatchSemaphore?

        init(none: Set<String> = [], gated: Bool = false) {
            self.none = none
            gate = gated ? DispatchSemaphore(value: 0) : nil
        }

        func load(_ path: String) -> NSImage? {
            gate?.wait()
            reads.withLock { $0.append(path) }
            return none.contains(path) ? nil : NSImage(size: NSSize(width: ItemIcons.size, height: ItemIcons.size))
        }

        func count(_ path: String) -> Int { reads.withLock { $0.filter { $0 == path }.count } }
    }

    /// Icons from `loader`, kept up to `limit`; the paths told collected in `told` (on a queue of the test's: not the main
    /// thread's, which no test runs).
    func icons(_ loader: Loader, limit: Int = 512, told: Locked<[Set<String>]>) -> ItemIcons {
        let icons = ItemIcons(limit: limit, loader: { loader.load($0) }, tells: DispatchQueue(label: "ItemIconsTests.told"))
        icons.onLoaded = { paths in told.withLock { $0.append(paths) } }
        return icons
    }

    func waitFor(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
        return condition()
    }

    /// A row drawn before its icon is in: nothing at once (the symbol is drawn), the icon read once off the caller's
    /// thread, the row told, and from then on the icon at once, never read again, never gone back.
    @Test func aRowThatAsksIsToldOnceItsIconIsIn() {
        let loader = Loader(gated: true), told = Locked<[Set<String>]>(initialState: [])
        let icons = icons(loader, told: told)
        let path = "/Applications/WeChat.app"
        #expect(icons.icon(path) == nil, "nothing kept, nothing read on the caller's thread")
        #expect(icons.icon(requesting: path) == nil && icons.icon(requesting: path) == nil, "asked twice, read once")
        #expect(loader.reads.withLock { $0 }.isEmpty && told.withLock { $0 }.isEmpty, "read off the caller's thread, not yet")
        loader.gate?.signal()
        #expect(waitFor { told.withLock { $0 } == [[path]] }, "\(told.withLock { $0 })")
        #expect(icons.icon(path) != nil && icons.icon(requesting: path) != nil)
        #expect(loader.count(path) == 1 && told.withLock { $0 }.count == 1, "\(loader.reads.withLock { $0 })")
    }

    /// A path with no icon (on a server, gone) is kept as none: asked again, it isn't read again, and its row keeps the
    /// symbol rather than blink.
    @Test func aPathWithNoIconIsNotAskedAgain() {
        let server = "/Volumes/share/Report.pdf"
        let loader = Loader(none: [server]), told = Locked<[Set<String>]>(initialState: [])
        let icons = icons(loader, told: told)
        #expect(icons.icon(requesting: server) == nil)
        #expect(waitFor { !told.withLock { $0 }.isEmpty })
        for _ in 0..<3 { #expect(icons.icon(requesting: server) == nil) }
        #expect(loader.count(server) == 1 && told.withLock { $0 }.count == 1)
    }

    /// Icons loaded with the results, before they are shown (`load`, `preload`) or soon after they are kept
    /// (`prefetch`): there at once when the rows ask, none read twice; `prefetch` takes at most half the limit.
    @Test func iconsLoadedWithTheResultsAreThereAtOnce() async {
        let loader = Loader(), told = Locked<[Set<String>]>(initialState: [])
        let icons = icons(loader, limit: 8, told: told)
        await icons.load(["/a", "/b"])
        #expect(icons.icon(requesting: "/a") != nil && icons.icon(requesting: "/b") != nil)
        await icons.load(["/a", "/c"])
        #expect(loader.count("/a") == 1 && icons.icon("/c") != nil)
        icons.prefetch((1...10).map { "/kept\($0)" })
        #expect(waitFor { icons.icon("/kept4") != nil })
        #expect(icons.icon("/kept5") == nil && loader.count("/kept5") == 0, "at most half of the limit: \(loader.reads.withLock { $0 })")
        #expect(told.withLock { $0 }.isEmpty, "nothing asked: nothing told")
    }

    /// Past the limit, the least recently used icon goes; one drawn lately stays.
    @Test func theLeastRecentlyUsedGo() {
        let loader = Loader(), told = Locked<[Set<String>]>(initialState: [])
        let icons = icons(loader, limit: 2, told: told)
        icons.preload(["/a", "/b"])
        _ = icons.icon("/a")
        icons.preload(["/c"])
        #expect(icons.icon("/a") != nil && icons.icon("/c") != nil && icons.icon("/b") == nil)
    }

    /// Finder's icon for a folder here, drawn at the rows' size, two pixels a point; none for what isn't there.
    @Test func finderIconsAreDrawnAtTheRowsSize() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ItemIconsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try #require(ItemIcons.finderIcon(folder.path))
        #expect(image.size == NSSize(width: ItemIcons.size, height: ItemIcons.size))
        let pixels = image.representations.first.map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
        #expect(pixels == NSSize(width: ItemIcons.size * 2, height: ItemIcons.size * 2), "\(String(describing: pixels))")
        #expect(ItemIcons.finderIcon(folder.appendingPathComponent("gone.txt").path) == nil)
    }

    /// What `InstantFiles` keeps is told for its icons, on the thread that keeps it: the index's apps (what was opened
    /// before first) as they are made, a folder's entries as they are listed.
    @Test func whatInstantFilesKeepsIsToldForItsIcons() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ItemIconsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Calendar", "WeChat"] {
            let contents = root.appendingPathComponent("\(name).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": name], format: .binary, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        let wechat = root.appendingPathComponent("WeChat.app").path
        let told = Locked<[[String]]>(initialState: [])
        let files = InstantFiles(index: AppIndex(folders: [root.path], apps: [], home: nil, recheckInterval: 0))
        files.onKept = { paths in told.withLock { $0.append(paths) } }
        var history = OpenHistory()
        history.record(wechat)
        files.make(history: history)
        let made = told.withLock { $0.first } ?? []
        #expect(made.first == wechat && Set(made) == Set(["Calendar", "WeChat"].map { root.appendingPathComponent("\($0).app").path }),
                "\(made)")
        _ = files.list(root.path + "/", limit: 8)
        #expect(told.withLock { $0.count } == 2 && Set(told.withLock { $0.last } ?? []) == Set(made), "\(told.withLock { $0 })")
    }
}
