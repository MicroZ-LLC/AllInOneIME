#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing

/// Where the engine takes librime (rime.dll, code) and rime-ice's data (with its Lua scripts, code too) from: an
/// installed copy from beside itself only, never a ThirdParty folder another user of the PC could have made.
struct RimeLocationTests {
    /// A copy of librime and its data in `folder` (as ThirdParty has them, or beside the program).
    func plant(_ folder: URL, besideProgram: Bool = false) throws {
        let fm = FileManager.default
        let library = besideProgram ? folder.appendingPathComponent("rime.dll") : folder.appendingPathComponent("librime/dist/lib/rime.dll")
        let data = folder.appendingPathComponent("rime-data", isDirectory: true)
        try fm.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: library)
        try Data("config_version: test\n".utf8).write(to: data.appendingPathComponent("default.yaml"))
    }

    @Test func anInstalledEngineTakesLibrimeFromBesideItselfOnly() throws {
        // C:\ as a folder of the test's own: Program Files\AllInOneIME\0.6.4\AllInOneIMEEngine.exe in it, and a
        // ThirdParty at its root, as any user can make C:\ThirdParty; another named by ALLINONEIME_THIRDPARTY.
        let root = try temporaryFolder("rime-location")
        defer { try? FileManager.default.removeItem(at: root) }
        let programFiles = root.appendingPathComponent("Program Files", isDirectory: true)
        let installed = programFiles.appendingPathComponent("AllInOneIME/0.6.4", isDirectory: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let engine = installed.appendingPathComponent("AllInOneIMEEngine.exe")
        try plant(root.appendingPathComponent("ThirdParty", isDirectory: true))
        let elsewhere = root.appendingPathComponent("elsewhere", isDirectory: true)
        try plant(elsewhere)
        let environment = ["ALLINONEIME_THIRDPARTY": elsewhere.path]

        #expect(EngineRime.isInstalled(engine, programFiles: [programFiles]))
        // Nothing beside it: no librime at all (Latin letters), not the planted ones.
        #expect(EngineRime.locate(executable: engine, environment: environment, installed: true) == nil)
        #expect(EngineRime.locate(executable: engine, sharedData: elsewhere.appendingPathComponent("rime-data"),
                                  environment: environment, installed: true) == nil)
        // Beside it: those.
        try plant(installed, besideProgram: true)
        let location = try #require(EngineRime.locate(executable: engine, sharedData: elsewhere.appendingPathComponent("rime-data"),
                                                      environment: environment, installed: true))
        #expect(location.library.standardizedFileURL == installed.appendingPathComponent("rime.dll").standardizedFileURL)
        #expect(location.sharedData.standardizedFileURL == installed.appendingPathComponent("rime-data").standardizedFileURL)

        // A build (not installed) still finds ThirdParty, ALLINONEIME_THIRDPARTY's first.
        let build = root.appendingPathComponent("Windows/.build/debug/AllInOneIMEEngine.exe")
        #expect(!EngineRime.isInstalled(build, programFiles: [programFiles]))
        let found = try #require(EngineRime.locate(executable: build, environment: environment, installed: false))
        #expect(found.library.standardizedFileURL == elsewhere.appendingPathComponent("librime/dist/lib/rime.dll").standardizedFileURL)
    }

    @Test func programFilesIsWindowsOwn() {
        let folders = EngineRime.programFilesFolders.map { EngineRime.windowsPath($0).lowercased() }
        #expect(folders.contains { $0.hasSuffix(#":\program files"#) })
        #expect(EngineRime.isInstalled(URL(fileURLWithPath: #"C:\Program Files\AllInOneIME\0.6.4\AllInOneIMEEngine.exe"#)))
        #expect(EngineRime.isInstalled(URL(fileURLWithPath: #"c:\program files\allinoneime\0.6.4\AllInOneIMEEngine.exe"#)))
        #expect(!EngineRime.isInstalled(URL(fileURLWithPath: #"C:\Program Files Evil\AllInOneIMEEngine.exe"#)))
        #expect(!EngineRime.isInstalled(packageRoot.appendingPathComponent(".build/debug/AllInOneIMEEngine.exe")))
    }
}
#endif
