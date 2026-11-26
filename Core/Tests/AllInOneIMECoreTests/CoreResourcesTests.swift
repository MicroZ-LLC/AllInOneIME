import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// Where the core looks for the bundle of its resources (`CoreResources`).
struct CoreResourcesTests {
    /// A core loaded as a library into another program (a DLL or .so: its bundle is the folder it's in) finds the
    /// bundle beside it, even where that bundle's resources are a folder of their own (the library's bundle here has
    /// Contents/Resources, as a framework does); the program's own resources come first, and a place without the
    /// bundle finds nothing.
    @Test func theLibrarysFolderIsLookedIn() throws {
        let root = TestScratch.temporary("core-resources-\(UUID().uuidString)", isDirectory: true)
        let host = root.appendingPathComponent("host", isDirectory: true)
        let library = root.appendingPathComponent("library", isDirectory: true)
        let contents = library.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"),
                                                withIntermediateDirectories: true)
        try Data(Self.infoPlist.utf8).write(to: contents.appendingPathComponent("Info.plist"))
        let besideLibrary = try Self.bundle(in: library, kind: "resources", word: "library")
        try FileManager.default.createDirectory(at: host, withIntermediateDirectories: true)
        let main = try #require(Bundle(url: host))
        let loaded = try #require(Bundle(url: library))

        let places = CoreResources.places(main: main, loaded: loaded)
        #expect(places.contains(loaded.bundleURL))
        #expect(places.contains(loaded.bundleURL.deletingLastPathComponent()))
        let found = try #require(CoreResources.url(forResource: "Words", withExtension: "txt", in: places))
        #expect(try String(contentsOf: found, encoding: .utf8) == "library\n", "\(found.path), not \(besideLibrary.path)")
        #expect(CoreResources.url(forResource: "Words", withExtension: "txt", in: [host]) == nil)
        #expect(CoreResources.url(forResource: "Other", withExtension: "txt", in: places) == nil)

        // The program's resources (a .bundle there) before the library's folder.
        _ = try Self.bundle(in: host, kind: "bundle", word: "host")
        let first = try #require(CoreResources.url(forResource: "Words", withExtension: "txt", in: places))
        #expect(try String(contentsOf: first, encoding: .utf8) == "host\n")
    }

    static let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.example.library</string></dict></plist>
        """

    /// The core's bundle (flat, as SwiftPM makes a .resources folder) in `folder`, with Words.txt holding `word`.
    static func bundle(in folder: URL, kind: String, word: String) throws -> URL {
        let bundle = folder.appendingPathComponent("\(CoreResources.bundleName).\(kind)", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("\(word)\n".utf8).write(to: bundle.appendingPathComponent("Words.txt"))
        return bundle
    }
}
