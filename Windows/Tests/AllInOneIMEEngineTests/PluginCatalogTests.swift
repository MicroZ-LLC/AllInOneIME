#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import AllInOneIMEWire
import Foundation
import Testing

/// The plugins as the sessions take them at each focus (`PluginCatalog`): read once, again when their folder changes,
/// and in the background after a while, never on every focus.
struct PluginCatalogTests {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        func add() { lock.lock(); _count += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    }

    @Test func readAgainOnlyWhenTheFolderChangesOrInTheBackground() throws {
        let folder = try temporaryFolder("plugins")
        defer { try? FileManager.default.removeItem(at: folder) }
        let loads = Counter()
        let catalog = PluginCatalog(directory: folder, maxAge: 1, settleTime: 0.2) {
            loads.add()
            return []
        }
        // Just made: read each time until its date has settled.
        _ = catalog.current
        _ = catalog.current
        #expect(loads.count == 2)
        Thread.sleep(forTimeInterval: 0.25)
        _ = catalog.current
        _ = catalog.current
        _ = catalog.current
        #expect(loads.count == 3)
        // A plugin installed (a folder of its own in the plugins folder): read again, even in the same tick of the
        // clock as the last read.
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("stock"), withIntermediateDirectories: false)
        _ = catalog.current
        #expect(loads.count == 4)
        Thread.sleep(forTimeInterval: 0.25)
        _ = catalog.current
        _ = catalog.current
        #expect(loads.count == 5)
        // Older than maxAge: what was read is used at once, and read again in the background.
        Thread.sleep(forTimeInterval: 1.1)
        _ = catalog.current
        #expect(loads.count == 5)
        let deadline = Date().addingTimeInterval(5)
        while loads.count < 6, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        #expect(loads.count == 6)
        _ = catalog.current
        #expect(loads.count == 6)
    }

    /// A field taking the focus again and again (Windows moves the focus often) doesn't read the plugins each time.
    @Test func focusDoesntReadThePluginsEachTime() throws {
        let folder = try temporaryFolder("plugins-focus")
        defer { try? FileManager.default.removeItem(at: folder) }
        let loads = Counter()
        let catalog = PluginCatalog(directory: folder.appendingPathComponent("plugins")) {
            loads.add()
            return []
        }
        let client = EngineClient(settings: try settingsFile(#"{"inputLanguages": ["en"]}"#, in: folder), rime: nil,
                                  configure: { $0.plugins = catalog })
        for serial in UInt32(2)...UInt32(6) {
            client.send(.blur(sid: 1))
            client.send(.focus(sid: 1, focus: serial, field: nil))
        }
        #expect(loads.count == 1)
    }

    /// The real store behind it: a plugin installed by hand shows up at the next focus.
    @Test func aPluginInstalledShowsUp() throws {
        let folder = try temporaryFolder("plugins-real")
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalog = PluginCatalog(directory: folder)
        #expect(catalog.current.isEmpty)
        let plugin = folder.appendingPathComponent("shout")
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        try Data(#"{"name": "shout", "version": "1.0.0", "description": "Shouts", "type": "prompt", "prompt": "Shout: {input}"}"#.utf8)
            .write(to: plugin.appendingPathComponent("plugin.json"))
        let found = catalog.current.map(\.name)
        #expect(found == ["shout"], "\(PluginStore.load(from: folder).skipped)")
    }
}
#endif
