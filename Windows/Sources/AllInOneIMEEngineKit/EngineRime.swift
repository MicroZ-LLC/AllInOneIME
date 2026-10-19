import AllInOneIMECore
import AllInOneIMERime
import Foundation
#if os(Windows)
import WinSDK
#endif

/// Level one's pinyin in the engine: librime (`AllInOneIMERime`) with rime-ice's data. The data and `rime.dll` are
/// beside the program in an installed copy (Program Files\AllInOneIME\<version>\rime-data, rime.dll); a build finds
/// them in ThirdParty (`$ALLINONEIME_THIRDPARTY`, else a `ThirdParty` above the program, as Windows/.build/release is).
/// Its user folder (the learned words, the deployed schemas) is `%APPDATA%\AllInOneIME\rime`.
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
    public static func locate(executable: URL, sharedData: URL? = nil,
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> Location? {
        let fm = FileManager.default
        let folder = executable.deletingLastPathComponent()
        var thirdParties: [URL] = []
        if let given = environment["ALLINONEIME_THIRDPARTY"], !given.isEmpty {
            thirdParties.append(URL(fileURLWithPath: given, isDirectory: true))
        }
        var up = folder
        for _ in 0..<5 {
            thirdParties.append(up.appendingPathComponent("ThirdParty", isDirectory: true))
            up = up.deletingLastPathComponent()
        }
        let libraries = [folder.appendingPathComponent("rime.dll")]
            + thirdParties.map { $0.appendingPathComponent("librime/dist/lib/rime.dll") }
        let datas = (sharedData.map { [$0] } ?? [folder.appendingPathComponent("rime-data", isDirectory: true)]
            + thirdParties.map { $0.appendingPathComponent("rime-data", isDirectory: true) })
        guard let library = libraries.first(where: { fm.fileExists(atPath: $0.path) }),
              let data = datas.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("default.yaml").path) })
        else { return nil }
        return Location(sharedData: data, library: library)
    }

    /// Loads rime.dll by its full path and starts librime's deployment, in the background (quick with the prebuilt
    /// dictionaries: a second or so the first time in a user folder). `isReady` says when sessions can be made.
    public func start() throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard !started else { return }
        #if os(Windows)
        let path = location.library.path.replacingOccurrences(of: "/", with: "\\")
        let module = path.withCString(encodedAs: UTF16.self) { LoadLibraryExW($0, nil, DWORD(LOAD_WITH_ALTERED_SEARCH_PATH)) }
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

    func processKey(_ keycode: Int32, mask: Int32) -> Bool { locked { $0.processKey(keycode, mask: mask) } }
    func takeCommit() -> String? { locked { $0.takeCommit() } }
    func snapshot() -> EngineSnapshot { locked { $0.snapshot() } }
    func selectCandidate(onPage index: Int) -> Bool { locked { $0.selectCandidate(onPage: index) } }
    func commitComposition() -> String? { locked { $0.commitComposition() } }
    var rawInput: String { locked { $0.rawInput } }
    func clearComposition() { locked { $0.clearComposition() } }
    func setAsciiMode(_ on: Bool) { locked { $0.setAsciiMode(on) } }
}
