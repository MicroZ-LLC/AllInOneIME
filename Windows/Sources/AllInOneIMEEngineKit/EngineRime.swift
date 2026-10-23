import AllInOneIMECore
import AllInOneIMERime
import Foundation
#if os(Windows)
import WinSDK
#endif

/// Level one's pinyin in the engine: librime (`AllInOneIMERime`) with rime-ice's data. The data and `rime.dll` are
/// beside the program in an installed copy (Program Files\AllInOneIME\<version>\rime-data, rime.dll), and in any copy
/// that isn't a build of this package; only a build (`isBuild`: Windows/.build/release) finds them in ThirdParty
/// (`$ALLINONEIME_THIRDPARTY`, else a `ThirdParty` above it). Its user folder (the learned words, the deployed schemas)
/// is `%APPDATA%\AllInOneIME\rime`.
///
/// librime is one per process and the engine has a queue per client connection: every call into it goes through one
/// lock (`EngineRime.lock`), so two apps' keys never reach it at once (its sessions' table isn't guarded). A key is a
/// fraction of a millisecond in it, so the lock is never held long.
public final class EngineRime: @unchecked Sendable {
    public struct Location: Equatable, Sendable {
        /// rime-data: the schemas and the prebuilt dictionaries (build/).
        public var sharedData: URL
        /// rime.dll, delay-loaded by the program (Package.swift's `linksRime`).
        public var library: URL
    }

    /// Every call into librime.
    static let lock = NSRecursiveLock()

    public let location: Location
    public let userData: URL
    private let log: @Sendable (String) -> Void
    private var started = false

    public init(location: Location, userData: URL, log: @escaping @Sendable (String) -> Void) {
        self.location = location
        self.userData = userData
        self.log = log
    }

    /// The user folder's default place.
    public static var defaultUserData: URL { CorePaths.configDir.appendingPathComponent("rime", isDirectory: true) }

    /// Where the data and the library are: `sharedData` if given (with `rime.dll` beside the program, or in ThirdParty),
    /// else beside the program, else in ThirdParty. Nil when either is missing.
    ///
    /// Only a build (`build`, nil: `isBuild(executable)`) looks anywhere but beside itself: any other copy, the installed
    /// one first, takes both from beside itself, whatever the environment or the arguments say. A `ThirdParty` above
    /// Program Files\AllInOneIME\<version>, or above D:\Apps\AllInOneIME, is C:\ThirdParty or D:\ThirdParty, which any
    /// user of the PC can make, and rime.dll is code, as rime-ice's Lua scripts in its data are.
    public static func locate(executable: URL, sharedData: URL? = nil,
                              environment: [String: String] = ProcessInfo.processInfo.environment,
                              build: Bool? = nil) -> Location? {
        let fm = FileManager.default
        let folder = executable.deletingLastPathComponent()
        let beside = Location(sharedData: folder.appendingPathComponent("rime-data", isDirectory: true),
                              library: folder.appendingPathComponent("rime.dll"))
        func usable(_ data: URL) -> Bool { fm.fileExists(atPath: data.appendingPathComponent("default.yaml").path) }
        guard build ?? isBuild(executable) else {
            return fm.fileExists(atPath: beside.library.path) && usable(beside.sharedData) ? beside : nil
        }
        var thirdParties: [URL] = []
        if let given = environment["ALLINONEIME_THIRDPARTY"], !given.isEmpty {
            thirdParties.append(URL(fileURLWithPath: given, isDirectory: true))
        }
        var up = folder
        for _ in 0..<5 {
            thirdParties.append(up.appendingPathComponent("ThirdParty", isDirectory: true))
            up = up.deletingLastPathComponent()
        }
        let libraries = [beside.library] + thirdParties.map { $0.appendingPathComponent("librime/dist/lib/rime.dll") }
        let datas = sharedData.map { [$0] } ?? [beside.sharedData] + thirdParties.map { $0.appendingPathComponent("rime-data", isDirectory: true) }
        guard let library = libraries.first(where: { fm.fileExists(atPath: $0.path) }), let data = datas.first(where: usable)
        else { return nil }
        return Location(sharedData: data, library: library)
    }

    /// Whether `executable` is a build of this package, as `swift build` makes one (in a `.build` folder), and not the
    /// installed copy (`isInstalled`), whatever folder that was installed to.
    public static func isBuild(_ executable: URL, installFolder: URL? = registeredInstallFolder) -> Bool {
        let inBuild = windowsPath(executable).split(separator: "\\").dropLast().contains { $0.lowercased() == ".build" }
        return inBuild && !isInstalled(executable, installFolder: installFolder)
    }

    /// Whether `executable` is the installed copy: in the folder the installer wrote down (`registeredInstallFolder`),
    /// which only administrators can change. Compared as folders, not as paths: the same whatever the case, the 8.3
    /// short names or the links it is written with.
    public static func isInstalled(_ executable: URL, installFolder: URL? = registeredInstallFolder) -> Bool {
        guard let installFolder else { return false }
        return isSameFolder(executable.deletingLastPathComponent(), installFolder)
    }

    /// The folder the MSI installed to: `HKLM\Software\AllInOneIME`, value `InstallDir` (its INSTALLFOLDER, wherever that
    /// was: Program Files\AllInOneIME\<version>, or a folder given as `msiexec INSTALLFOLDER=D:\…`). Nil when AllInOneIME
    /// isn't installed.
    public static var registeredInstallFolder: URL? {
        #if os(Windows)
        let flags = DWORD(RRF_RT_REG_SZ) | DWORD(RRF_SUBKEY_WOW6464KEY)
        let found = #"Software\AllInOneIME"#.withCString(encodedAs: UTF16.self) { key in
            "InstallDir".withCString(encodedAs: UTF16.self) { name -> String? in
                var size: DWORD = 0
                guard RegGetValueW(HKEY_LOCAL_MACHINE, key, name, flags, nil, nil, &size) == ERROR_SUCCESS, size > 2 else { return nil }
                var buffer = [WCHAR](repeating: 0, count: Int(size) / 2 + 1)
                guard RegGetValueW(HKEY_LOCAL_MACHINE, key, name, flags, nil, &buffer, &size) == ERROR_SUCCESS else { return nil }
                return String(decodingCString: buffer, as: UTF16.self)
            }
        }
        guard let found, !found.isEmpty else { return nil }
        return URL(fileURLWithPath: found, isDirectory: true)
        #else
        return nil
        #endif
    }

    /// Whether `a` and `b` are the same folder, both there: the same volume and file id.
    static func isSameFolder(_ a: URL, _ b: URL) -> Bool {
        #if os(Windows)
        func identity(_ url: URL) -> [DWORD]? {
            let handle = windowsPath(url).withCString(encodedAs: UTF16.self) {
                CreateFileW($0, DWORD(FILE_READ_ATTRIBUTES), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), nil,
                            DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS), nil)
            }
            guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
            defer { CloseHandle(handle) }
            var info = BY_HANDLE_FILE_INFORMATION()
            guard GetFileInformationByHandle(handle, &info), info.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0 else {
                return nil
            }
            return [info.dwVolumeSerialNumber, info.nFileIndexHigh, info.nFileIndexLow]
        }
        guard let first = identity(a) else { return false }
        return first == identity(b)
        #else
        return a.standardizedFileURL == b.standardizedFileURL
        #endif
    }

    /// `url`'s path as Windows writes it ("C:\Program Files\…"), with no "\" at the end.
    static func windowsPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.withUnsafeFileSystemRepresentation { String(cString: $0!) }.replacingOccurrences(of: "/", with: "\\")
        while path.count > 3, path.hasSuffix("\\") { path.removeLast() }
        return path
    }

    /// Loads rime.dll by its full path and starts librime's deployment, in the background (quick with the prebuilt
    /// dictionaries: a second or so the first time in a user folder). `isReady` says when sessions can be made.
    public func start() throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard !started else { return }
        #if os(Windows)
        // By its full path; what it imports (KERNEL32, USER32, dbghelp) from its own folder or System32 only.
        let path = Self.windowsPath(location.library)
        let module = path.withCString(encodedAs: UTF16.self) {
            LoadLibraryExW($0, nil, DWORD(LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR) | DWORD(LOAD_LIBRARY_SEARCH_SYSTEM32))
        }
        guard module != nil else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "LoadLibraryExW(\(path)): error \(GetLastError())"])
        }
        #endif
        try RimeService.shared.start(sharedDataDir: location.sharedData, userDataDir: userData, logDir: nil)
        started = true
        log("rime: starting (\(RimeService.shared.version)), data \(location.sharedData.path), user folder \(userData.path)")
    }

    /// Deployed: sessions can be made.
    public var isReady: Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return started && RimeService.shared.isReady
    }

    /// Waits for the deployment, up to `timeout` seconds, on the calling thread. Whether it is ready.
    @discardableResult
    public func waitUntilReady(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isReady, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        return isReady
    }

    /// Fuzzy pinyin's pairs (`Config.fuzzyPinyin`) as librime's patch of rime-ice's schema in the user folder, as the
    /// Mac's `RimeFuzzy` writes it: before the deployment at the start, and when the settings change them, then
    /// deployed again (a second or so, with the sessions dropped), once a deployment under way is done; `deployed`
    /// after that, so that the Composers get new sessions. What it did; nil when it couldn't (logged).
    @discardableResult
    public func applyFuzzyPinyin(_ ids: [String], deployed: (@Sendable () -> Void)? = nil) -> FuzzyPinyin.Outcome? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let outcome: FuzzyPinyin.Outcome
        do {
            outcome = try FuzzyPinyin.apply(ids, schema: location.sharedData.appendingPathComponent("rime_ice.schema.yaml"),
                                            userDir: userData)
        } catch {
            log("rime: couldn't write the fuzzy pinyin patch: \(error)")
            return nil
        }
        switch outcome {
        case .userFile:
            log("rime: fuzzy pinyin not applied: the user folder has the user's own \(FuzzyPinyin.fileName)")
        case .written, .removed:
            guard started else { break }
            log("rime: fuzzy pinyin changed (\(ids.count) pairs): deploying again")
            // librime refuses a deployment while one is under way (the one at the start, a second or more): after it.
            Thread.detachNewThread { [self] in
                waitUntilReady(timeout: 300)
                Self.lock.lock()
                RimeService.shared.redeploy()
                Self.lock.unlock()
                if waitUntilReady(timeout: 300) {
                    log("rime: deployed again, fuzzy pinyin as the settings say")
                    deployed?()
                }
            }
        case .unchanged:
            break
        }
        return outcome
    }

    /// rime-ice's English dictionary in the data (`RimeService.englishDictionary`, read on a thread of its own as librime
    /// starts), for the English words put among the candidates (`EnglishWordsEngine`): those librime offers itself. Nil
    /// before `start`, or without one; waited for while it is still being read.
    public var englishDictionary: EnglishDictionary? {
        Self.lock.lock()
        let started = self.started
        Self.lock.unlock()
        return started ? RimeService.shared.englishDictionary : nil
    }

    /// A session for one Composer, through the lock; nil while librime deploys.
    public func makeEngine() -> PinyinEngine? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard started, let session = RimeService.shared.makeSession() else { return nil }
        return LockedRimeEngine(session)
    }
}

/// A librime session whose every call holds `EngineRime.lock`.
final class LockedRimeEngine: PinyinEngine {
    private var session: RimeSession?

    init(_ session: RimeSession) { self.session = session }

    deinit {
        EngineRime.lock.lock()
        session = nil  // destroys it, under the lock
        EngineRime.lock.unlock()
    }

    private func locked<T>(_ body: (RimeSession) -> T) -> T {
        EngineRime.lock.lock()
        defer { EngineRime.lock.unlock() }
        return body(session!)
    }

    /// False after librime dropped the session (a redeploy).
    var isValid: Bool { locked { $0.isValid } }

    /// Whether librime learns what is typed in it (`RimeSession.learns`): not in a field that keeps nothing.
    var learns: Bool {
        get { locked { $0.learns } }
        set { locked { $0.learns = newValue } }
    }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool { locked { $0.processKey(keycode, mask: mask) } }
    func takeCommit() -> String? { locked { $0.takeCommit() } }
    func snapshot() -> EngineSnapshot { locked { $0.snapshot() } }
    func selectCandidate(onPage index: Int) -> Bool { locked { $0.selectCandidate(onPage: index) } }
    func commitComposition() -> String? { locked { $0.commitComposition() } }
    var rawInput: String { locked { $0.rawInput } }
    func clearComposition() { locked { $0.clearComposition() } }
    func setAsciiMode(_ on: Bool) { locked { $0.setAsciiMode(on) } }
}
