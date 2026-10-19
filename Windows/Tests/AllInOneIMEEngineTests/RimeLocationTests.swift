#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing
import WinSDK

/// Where the engine takes librime (rime.dll, code) and rime-ice's data (with its Lua scripts, code too) from: a build
/// of this package anywhere it finds them, every other copy (the installed one first, wherever it was installed) from
/// beside itself only, never a ThirdParty folder another user of the PC could have made.
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

    /// `url` as Windows' 8.3 short names write it (`GetShortPathNameW`), if the volume makes them.
    static func shortPath(_ url: URL) -> String? {
        let long = EngineRime.windowsPath(url)
        var buffer = [WCHAR](repeating: 0, count: 1024)
        let count = long.withCString(encodedAs: UTF16.self) { GetShortPathNameW($0, &buffer, DWORD(buffer.count)) }
        guard count > 0, Int(count) < buffer.count else { return nil }
        let short = String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
        return short.lowercased() == long.lowercased() ? nil : short
    }

    /// D:\ as a folder of the test's own: the engine installed in "Custom Install\AllInOneIME" there
    /// (`msiexec INSTALLFOLDER=D:\…`), with librime planted in a ThirdParty at the root, as any user can make
    /// D:\ThirdParty, and in another named by ALLINONEIME_THIRDPARTY. The installed engine finds none of them, written
    /// any way: with its folder in another case, in 8.3 short names.
    @Test func anEngineInstalledAnywhereTakesLibrimeFromBesideItselfOnly() throws {
        let root = try temporaryFolder("rime-location")
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("Custom Install/AllInOneIME", isDirectory: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let engine = installed.appendingPathComponent("AllInOneIMEEngine.exe")
        try plant(root.appendingPathComponent("ThirdParty", isDirectory: true))
        let elsewhere = root.appendingPathComponent("elsewhere", isDirectory: true)
        try plant(elsewhere)
        let environment = ["ALLINONEIME_THIRDPARTY": elsewhere.path]

        // However it is written, it is the installed copy, and not a build.
        var spellings = [engine, URL(fileURLWithPath: EngineRime.windowsPath(engine).uppercased())]
        if let short = Self.shortPath(installed) {
            spellings.append(URL(fileURLWithPath: short).appendingPathComponent("AllInOneIMEEngine.exe"))
        }
        for spelling in spellings {
            #expect(EngineRime.isInstalled(spelling, installFolder: installed), "\(spelling.path)")
            #expect(!EngineRime.isBuild(spelling, installFolder: installed), "\(spelling.path)")
        }
        #expect(!EngineRime.isInstalled(root.appendingPathComponent("Custom Install/AllInOneIMEEngine.exe"), installFolder: installed))
        // Nothing beside it: no librime at all (Latin letters), not the planted ones.
        #expect(EngineRime.locate(executable: engine, environment: environment, build: false) == nil)
        #expect(EngineRime.locate(executable: engine, sharedData: elsewhere.appendingPathComponent("rime-data"),
                                  environment: environment, build: false) == nil)
        // Beside it: those.
        try plant(installed, besideProgram: true)
        let location = try #require(EngineRime.locate(executable: engine, sharedData: elsewhere.appendingPathComponent("rime-data"),
                                                      environment: environment, build: false))
        #expect(location.library.standardizedFileURL == installed.appendingPathComponent("rime.dll").standardizedFileURL)
        #expect(location.sharedData.standardizedFileURL == installed.appendingPathComponent("rime-data").standardizedFileURL)
    }

    /// A copy that is neither the installed one nor a build (a folder copied anywhere, an installed copy whose
    /// registration is gone) takes librime from beside itself only too; a build in a .build folder still finds
    /// ThirdParty's, ALLINONEIME_THIRDPARTY's first.
    @Test func onlyABuildLooksInThirdParty() throws {
        let root = try temporaryFolder("rime-build")
        defer { try? FileManager.default.removeItem(at: root) }
        try plant(root.appendingPathComponent("ThirdParty", isDirectory: true))
        let elsewhere = root.appendingPathComponent("elsewhere", isDirectory: true)
        try plant(elsewhere)
        let environment = ["ALLINONEIME_THIRDPARTY": elsewhere.path]

        let copied = root.appendingPathComponent("Apps/AllInOneIME/AllInOneIMEEngine.exe")
        try FileManager.default.createDirectory(at: copied.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(!EngineRime.isBuild(copied, installFolder: nil))
        #expect(EngineRime.locate(executable: copied, environment: environment) == nil)

        let build = root.appendingPathComponent("Windows/.build/debug/AllInOneIMEEngine.exe")
        try FileManager.default.createDirectory(at: build.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(EngineRime.isBuild(build, installFolder: nil))
        // Not when that build's folder is where the installer put it.
        #expect(!EngineRime.isBuild(build, installFolder: build.deletingLastPathComponent()))
        let found = try #require(EngineRime.locate(executable: build, environment: environment))
        #expect(found.library.standardizedFileURL == elsewhere.appendingPathComponent("librime/dist/lib/rime.dll").standardizedFileURL)
        let near = try #require(EngineRime.locate(executable: build, environment: [:]))
        #expect(near.library.standardizedFileURL == root.appendingPathComponent("ThirdParty/librime/dist/lib/rime.dll").standardizedFileURL)
    }

    /// The folder the MSI wrote down, read from HKLM as the engine reads it (when AllInOneIME is installed on this PC).
    @Test func theInstallFolderIsTheInstallersRecord() throws {
        #expect(EngineRime.isBuild(packageRoot.appendingPathComponent(".build/debug/AllInOneIMEEngine.exe")))
        guard let folder = EngineRime.registeredInstallFolder else { return }
        let engine = folder.appendingPathComponent("AllInOneIMEEngine.exe")
        #expect(EngineRime.isInstalled(engine))
        #expect(!EngineRime.isBuild(engine))
        #expect(!EngineRime.isInstalled(packageRoot.appendingPathComponent(".build/debug/AllInOneIMEEngine.exe")))
    }
}
#endif
