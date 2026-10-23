import AllInOneIMECore
import CRime
import Foundation
#if os(Windows)
import WinSDK
#endif

/// Process-wide librime instance (level one). Main thread only.
public final class RimeService {
    public enum DeploymentStatus: Sendable {
        case idle, deploying, succeeded, failed
    }

    public static let shared = RimeService()

    let api: UnsafeMutablePointer<RimeApi>
    public private(set) var isStarted = false
    public private(set) var sharedDataDir: URL?
    public private(set) var userDataDir: URL?

    private init() {
        api = rime_get_api()
    }

    public var version: String {
        api.pointee.get_version().map { String(cString: $0) } ?? "?"
    }

    /// False while librime is deploying (compiling schemas), or syncing the learned words (`syncUserData`); sessions
    /// cannot be created then.
    public var isReady: Bool {
        isStarted && api.pointee.is_maintenance_mode() == 0 && !isSyncing && !redeployWanted
    }

    /// librime's deploy notification, including compilation failure. Notifications can arrive on
    /// its deployment thread; consumers read this after `isReady`, which also waits for a queued deploy.
    public var deploymentStatus: DeploymentStatus {
        deploymentLock.lock(); defer { deploymentLock.unlock() }
        return lastDeploymentStatus
    }
    /// A local preparation error, if the requested deployment could not safely start.
    public var deploymentError: String? {
        deploymentLock.lock(); defer { deploymentLock.unlock() }
        return lastDeploymentError
    }
    private let deploymentLock = NSLock()
    private var lastDeploymentStatus: DeploymentStatus = .idle
    private var lastDeploymentError: String?
    private func setDeploymentStatus(_ value: DeploymentStatus, error: String? = nil) {
        deploymentLock.lock()
        lastDeploymentStatus = value
        lastDeploymentError = error
        deploymentLock.unlock()
    }

    private let syncLock = NSLock()
    private var syncing = false
    /// A redeploy asked for while the learned words were syncing.
    private var redeployWanted = false
    private var invalidateSchemaWanted = false
    private var redeployPoll: DispatchWorkItem?
    /// The learned words' sync is running (on a thread of its own).
    public var isSyncing: Bool { syncLock.lock(); defer { syncLock.unlock() }; return syncing }
    private func setSyncing(_ on: Bool) { syncLock.lock(); syncing = on; syncLock.unlock() }

    /// Sets up librime and starts deployment in the background. Deployment is quick when the
    /// prebuilt dictionaries in `sharedDataDir/build` are current.
    public func start(sharedDataDir: URL, userDataDir: URL, logDir: URL?, fullCheck: Bool = false) throws {
        guard !isStarted else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: userDataDir, withIntermediateDirectories: true)
        try Self.prepareLunarDatabase(sharedDataDir: sharedDataDir, userDataDir: userDataDir)
        if let logDir { try fm.createDirectory(at: logDir, withIntermediateDirectories: true) }
        // Our schema-list patch goes into the user directory so it applies (and can be edited there).
        let patch = "default.custom.yaml"
        let userPatch = userDataDir.appendingPathComponent(patch)
        let sharedPatch = sharedDataDir.appendingPathComponent(patch)
        if !fm.fileExists(atPath: userPatch.path), fm.fileExists(atPath: sharedPatch.path) {
            try fm.copyItem(at: sharedPatch, to: userPatch)
        }

        func c(_ s: String) -> UnsafePointer<CChar> { UnsafePointer(strdup(s)!) }  // lives for the process
        var traits = RimeTraits()
        traits.data_size = Int32(MemoryLayout<RimeTraits>.size - MemoryLayout<Int32>.size)
        traits.shared_data_dir = c(sharedDataDir.path)
        traits.user_data_dir = c(userDataDir.path)
        traits.distribution_name = c("AllInOneIME")
        traits.distribution_code_name = c("AllInOneIME")
        traits.distribution_version = c(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
        traits.app_name = c("rime.allinoneime")
        traits.min_log_level = 1  // warnings and errors only
        traits.log_dir = c(logDir?.path ?? "")
        api.pointee.setup(&traits)
        api.pointee.set_notification_handler({ context, _, type, value in
            guard let context, let type, let value, String(cString: type) == "deploy" else { return }
            let service = Unmanaged<RimeService>.fromOpaque(context).takeUnretainedValue()
            switch String(cString: value) {
            case "start": service.setDeploymentStatus(.deploying)
            case "success": service.setDeploymentStatus(.succeeded)
            case "failure": service.setDeploymentStatus(.failed)
            default: break
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        api.pointee.initialize(nil)
        _ = api.pointee.start_maintenance(fullCheck ? 1 : 0)
        self.sharedDataDir = sharedDataDir
        self.userDataDir = userDataDir
        englishLoad = EnglishLoad(sharedDataDir)
        isStarted = true
    }

    /// rime-ice's lunar translator opens `lua/lunar.db` relative to the user folder, unlike its scripts,
    /// which librime also finds in the shared folder. Supply the data there without replacing the user's own.
    static func prepareLunarDatabase(sharedDataDir: URL, userDataDir: URL) throws {
        let fm = FileManager.default
        let source = sharedDataDir.appendingPathComponent("lua/lunar.db")
        let destination = userDataDir.appendingPathComponent("lua/lunar.db")
        guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: destination.path) else { return }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: destination)
    }

    /// rime-ice's English dictionary in the shared data (`EnglishDictionary`), for the English words put among the
    /// candidates (`EnglishWordsEngine`): read on a thread of its own once librime starts (it deploys meanwhile), waited
    /// for if it isn't read yet. Nil before `start`, or without one.
    public var englishDictionary: EnglishDictionary? { englishLoad?.dictionary }
    private var englishLoad: EnglishLoad?

    /// The dictionary being read.
    private final class EnglishLoad: @unchecked Sendable {
        private let group = DispatchGroup()
        private var loaded: EnglishDictionary?

        init(_ folder: URL) {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                self.loaded = EnglishDictionary.load(rimeData: folder)
                self.group.leave()
            }
        }

        var dictionary: EnglishDictionary? {
            group.wait()
            return loaded
        }
    }

    /// Re-deploys everything (e.g. after editing files in the user directory). Existing sessions are
    /// dropped first so none is used while data is rebuilt; controllers create new ones when ready.
    /// Session ids are reused by librime, so the generation marks every older session as dead.
    public func redeploy(invalidateGeneratedSchema: Bool = false) {
        guard isStarted else { return }
        redeployWanted = true
        invalidateSchemaWanted = invalidateSchemaWanted || invalidateGeneratedSchema
        startRequestedRedeploy()
    }

    private func startRequestedRedeploy() {
        guard redeployWanted, !isSyncing else { return }
        // start_maintenance refuses a second request while deploying. Keep it until the current
        // deployment is over, so a newly imported file cannot be mistaken for an older success.
        guard api.pointee.is_maintenance_mode() == 0 else {
            if redeployPoll == nil {
                let poll = DispatchWorkItem { [weak self] in
                    self?.redeployPoll = nil
                    self?.startRequestedRedeploy()
                }
                redeployPoll = poll
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
            }
            return
        }
        redeployWanted = false
        redeployPoll?.cancel()
        redeployPoll = nil
        if invalidateSchemaWanted {
            invalidateSchemaWanted = false
            do { try invalidateGeneratedSchema() }
            catch {
                setDeploymentStatus(.failed, error: "build/rime_ice.schema.yaml: " + error.localizedDescription)
                return
            }
        }
        generation += 1
        api.pointee.cleanup_all_sessions()
        setDeploymentStatus(.deploying)
        if api.pointee.start_maintenance(1) == 0, deploymentStatus == .deploying {
            setDeploymentStatus(.failed)
        }
    }

    /// A previous maintenance job may have recreated the cache after Settings invalidated it.
    /// Do this only for a requested settings activation, after that job has actually finished.
    private func invalidateGeneratedSchema() throws {
        guard let userDataDir else { return }
        let fm = FileManager.default
        let build = userDataDir.appendingPathComponent("build", isDirectory: true)
        let compiled = build.appendingPathComponent("rime_ice.schema.yaml")
        do {
            let directory = try fm.attributesOfItem(atPath: build.path)
            guard directory[.type] as? FileAttributeType == .typeDirectory else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: build.path])
            }
            let file = try fm.attributesOfItem(atPath: compiled.path)
            guard file[.type] as? FileAttributeType == .typeRegular else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: compiled.path])
            }
            try fm.removeItem(at: compiled)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            // A first deployment, or the store already removed this generated cache.
        }
    }

    /// The learned words on every Mac (`RimeSync`): librime's user-dictionary sync alone, on a thread of its own. It
    /// reads `sync_dir` from the user folder's `installation.yaml` (`installation_update`), merges into this installation's
    /// user dictionaries the snapshots the other installations left there, and writes this one's own in its folder there,
    /// named by its `installation_id` (`user_dict_sync`). Not librime's whole `sync_user_data`, whose
    /// `backup_config_files` task also copies the user's own `.yaml` and `.txt` files (custom phrases, settings) into
    /// that folder: that task is never run here. Sessions are dropped first, as for a redeploy; `isReady` is false until
    /// it is done, and a redeploy asked for meanwhile waits for it. False when Rime isn't ready (deploying, or syncing
    /// already).
    @discardableResult
    public func syncUserData(done: ((Bool) -> Void)? = nil) -> Bool {
        guard isReady else { return false }
        setSyncing(true)
        generation += 1
        api.pointee.cleanup_all_sessions()
        let api = self.api
        DispatchQueue.global(qos: .utility).async {
            let ok = api.pointee.run_task("installation_update") != 0 && api.pointee.run_task("user_dict_sync") != 0
            self.setSyncing(false)
            DispatchQueue.main.async {
                if self.redeployWanted {
                    self.redeployWanted = false
                    self.redeploy()
                }
                done?(ok)
            }
        }
        return true
    }

    /// The sync folder of this installation (`sync_dir`/`installation_id`), as librime last read it.
    public var userDataSyncDir: URL? {
        guard isStarted else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096)
        api.pointee.get_user_data_sync_dir(&buffer, buffer.count)
        let path = Self.string(ofPath: buffer)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    /// A folder's path as librime gives it back: UTF-8, but on Windows in the code page of the system's file APIs (the
    /// ANSI one: std::filesystem's `string()`), though it takes paths in UTF-8 there too. It shows under a Chinese user
    /// name (C:\Users\张三).
    static func string(ofPath buffer: [CChar]) -> String {
        #if os(Windows)
        let codePage = UINT(AreFileApisANSI() ? CP_ACP : CP_OEMCP)
        return buffer.withUnsafeBufferPointer { bytes -> String in
            let count = MultiByteToWideChar(codePage, 0, bytes.baseAddress, -1, nil, 0)
            guard count > 0 else { return "" }
            var wide = [WCHAR](repeating: 0, count: Int(count))
            _ = MultiByteToWideChar(codePage, 0, bytes.baseAddress, -1, &wide, count)
            return String(decodingCString: wide, as: UTF16.self)
        }
        #else
        return String(cString: buffer)
        #endif
    }

    /// Bumped by `redeploy()`; sessions from an older generation are invalid.
    public private(set) var generation = 0

    /// Blocks until deployment finishes or the timeout passes. Returns `isReady`.
    @discardableResult
    public func waitUntilReady(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isReady && Date() < deadline {
            // This developer helper may block the main thread: service a queued redeploy here too.
            if redeployWanted { startRequestedRedeploy() }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return isReady
    }

    public func makeSession() -> RimeSession? {
        guard isReady else { return nil }
        return RimeSession(api: api, generation: generation)
    }

    /// Schema in use for new sessions (for status output).
    public func currentSchemaName() -> String? {
        guard let session = makeSession() else { return nil }
        var buffer = [CChar](repeating: 0, count: 256)
        guard api.pointee.get_current_schema(session.id, &buffer, buffer.count) != 0 else { return nil }
        return String(cString: buffer)
    }
}

/// One librime session per input controller.
public final class RimeSession: PinyinEngine {
    let api: UnsafeMutablePointer<RimeApi>
    public let id: RimeSessionId
    let generation: Int

    init?(api: UnsafeMutablePointer<RimeApi>, generation: Int) {
        self.api = api
        self.generation = generation
        id = api.pointee.create_session()
        guard id != 0 else { return nil }
    }

    private var isCurrentGeneration: Bool { generation == RimeService.shared.generation }

    deinit {
        // After a redeploy librime already destroyed this session and may have reused its id.
        if isCurrentGeneration { _ = api.pointee.destroy_session(id) }
    }

    /// False after librime dropped the session (e.g. during a re-deploy).
    public var isValid: Bool { isCurrentGeneration && api.pointee.find_session(id) != 0 }

    /// Whether what is typed is learned into librime's user dictionary, as librime has it (true). Off (a field an input
    /// method is to keep nothing of: a private window's), nothing of it reaches the dictionary. librime learns a
    /// composition as it commits it, so it never commits one with a word picked or converted: a pick that ends the
    /// composition leaves it confirmed (its `_auto_commit` off, as its fluid editor has it), and its text is taken from
    /// there and the composition cleared; so are `commitComposition`'s, Space's on a composition all confirmed and
    /// Return's on one with a part picked (what librime would commit). What it commits without learning comes as before:
    /// the letters as typed with nothing picked (Return), punctuation on its own.
    public var learns = true {
        didSet {
            guard learns != oldValue, isCurrentGeneration else { return }
            api.pointee.set_option(id, "_auto_commit", learns ? 1 : 0)
        }
    }

    /// Text put in while `learns` is off, not taken yet (`takeCommit`).
    private var unlearned = ""
    /// Shift is down, and nothing else was pressed since: its release is a tap.
    private var shiftTap = false

    public func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        guard isCurrentGeneration else { return false }
        guard !learns else { return api.pointee.process_key(id, keycode, mask) != 0 }
        let shift = keycode == RimeKey.shiftL || keycode == RimeKey.shiftR
        if mask & RimeKey.releaseMask != 0 {
            // A tap of Shift (rime-ice: `Shift_L: commit_code`): librime commits the part picked and the letters after
            // it, and learns the part. Put in here; librime then only switches to Latin.
            if shift, shiftTap, let before = composition(), before.picked {
                put(before.converted + before.lettersAfterThePick(input: rawInput))
            }
            shiftTap = false
            return api.pointee.process_key(id, keycode, mask) != 0
        }
        shiftTap = shift
        // Set again if librime set it back (a schema loaded again sets its editor's).
        if api.pointee.get_option(id, "_auto_commit") != 0 { api.pointee.set_option(id, "_auto_commit", 0) }
        let editing = Self.editingKeys.contains(keycode) || mask & RimeKey.controlMask != 0
        if let before = composition() {
            if keycode == RimeKey.returnKey, mask & RimeKey.controlMask == 0, before.picked {
                // Return: librime commits the part picked and the letters after it, and learns the part.
                put(before.converted + before.lettersAfterThePick(input: rawInput))
                return true
            }
            if before.isConfirmed, !editing {
                // All confirmed (after Esc on a part picked): what librime commits on Space, or before what comes next.
                put(before.preview)
                if keycode == RimeKey.space && mask == 0 { return true }
            }
        }
        let handled = api.pointee.process_key(id, keycode, mask) != 0
        if !editing, let after = composition(), after.isConfirmed { put(after.preview) }
        return handled
    }

    /// Keys that edit the composition, and never commit it.
    static let editingKeys: Set<Int32> = [RimeKey.backSpace, RimeKey.delete, RimeKey.escape, RimeKey.left, RimeKey.right,
                                          RimeKey.up, RimeKey.down, RimeKey.home, RimeKey.end, RimeKey.pageUp,
                                          RimeKey.pageDown, RimeKey.tab, RimeKey.shiftL, RimeKey.shiftR]

    /// `text` put in without librime's commit (`learns` off), the composition cleared.
    private func put(_ text: String) {
        unlearned += text
        api.pointee.clear_composition(id)
    }

    /// The composition as `learns` off needs it: nil when there is none.
    struct Composition {
        var preedit: [UInt8]
        /// The highlighted part of `preedit`, in its UTF-8 bytes (librime's): what comes before it is converted.
        var selection: Range<Int>
        var hasMenu: Bool
        /// What librime would commit now (the candidates picked and highlighted, the letters left).
        var preview: String

        /// Something is picked already: the text before the highlighted part.
        var picked: Bool { selection.lowerBound > 0 }
        /// Everything is confirmed: picked to the end, with nothing to pick (`_auto_commit` off leaves it so).
        var isConfirmed: Bool { !preedit.isEmpty && !hasMenu && selection.isEmpty && selection.lowerBound >= preedit.count }
        var converted: String { String(decoding: preedit[..<min(selection.lowerBound, preedit.count)], as: UTF8.self) }

        /// The letters typed after what is picked (`input`'s end), as many as the preedit shows after it, without
        /// librime's delimiters (" '"): what its Return commits after the part picked.
        func lettersAfterThePick(input: String) -> String {
            let delimiters: Set<Character> = [" ", "'"]
            let shown = String(decoding: preedit[min(selection.lowerBound, preedit.count)...], as: UTF8.self)
            var count = shown.filter { !delimiters.contains($0) }.count
            var letters: [Character] = []
            for character in input.reversed() where count > 0 {
                letters.insert(character, at: 0)
                if !delimiters.contains(character) { count -= 1 }
            }
            return count == 0 ? String(letters).filter { !delimiters.contains($0) } : shown.filter { !delimiters.contains($0) }
        }
    }

    func composition() -> Composition? {
        var context = RimeContext()
        context.data_size = Int32(MemoryLayout<RimeContext>.size - MemoryLayout<Int32>.size)
        guard api.pointee.get_context(id, &context) != 0 else { return nil }
        defer { _ = api.pointee.free_context(&context) }
        guard let preedit = context.composition.preedit else { return nil }
        let bytes = Array(String(cString: preedit).utf8)
        let start = max(0, min(Int(context.composition.sel_start), bytes.count))
        let end = max(start, min(Int(context.composition.sel_end), bytes.count))
        let preview = context.commit_text_preview.map { String(cString: $0) } ?? String(decoding: bytes, as: UTF8.self)
        return Composition(preedit: bytes, selection: start..<end, hasMenu: context.menu.num_candidates > 0, preview: preview)
    }

    public func takeCommit() -> String? {
        guard isCurrentGeneration else { return nil }
        let unlearned = self.unlearned
        self.unlearned = ""
        var commit = RimeCommit()
        commit.data_size = Int32(MemoryLayout<RimeCommit>.size - MemoryLayout<Int32>.size)
        guard api.pointee.get_commit(id, &commit) != 0 else { return unlearned.isEmpty ? nil : unlearned }
        defer { _ = api.pointee.free_commit(&commit) }
        let text = commit.text.map { String(cString: $0) }
        return unlearned.isEmpty ? text : unlearned + (text ?? "")
    }

    public func snapshot() -> EngineSnapshot {
        var snap = EngineSnapshot()
        guard isCurrentGeneration else { return snap }
        var status = RimeStatus()
        status.data_size = Int32(MemoryLayout<RimeStatus>.size - MemoryLayout<Int32>.size)
        if api.pointee.get_status(id, &status) != 0 {
            snap.isComposing = status.is_composing != 0
            snap.isAsciiMode = status.is_ascii_mode != 0
            _ = api.pointee.free_status(&status)
        }
        var context = RimeContext()
        context.data_size = Int32(MemoryLayout<RimeContext>.size - MemoryLayout<Int32>.size)
        guard api.pointee.get_context(id, &context) != 0 else { return snap }
        defer { _ = api.pointee.free_context(&context) }

        if let preedit = context.composition.preedit {
            let text = String(cString: preedit)
            snap.preedit = text
            snap.cursor = Self.characterOffset(utf8: Int(context.composition.cursor_pos), in: text)
        }
        let menu = context.menu
        snap.highlighted = Int(menu.highlighted_candidate_index)
        snap.pageNumber = Int(menu.page_no)
        snap.isLastPage = menu.is_last_page != 0
        let selectKeys = menu.select_keys.map { Array(String(cString: $0)) } ?? []
        if let candidates = menu.candidates {
            for i in 0..<Int(max(menu.num_candidates, 0)) {
                let candidate = candidates[i]
                let label: String
                if let labels = context.select_labels, let l = labels[i] {
                    label = String(cString: l)
                } else if i < selectKeys.count {
                    label = String(selectKeys[i])
                } else {
                    label = String((i + 1) % 10)
                }
                snap.candidates.append(EngineCandidate(
                    label: label,
                    text: candidate.text.map { String(cString: $0) } ?? "",
                    comment: candidate.comment.map { String(cString: $0) } ?? ""))
            }
        }
        if !snap.preedit.isEmpty { snap.isComposing = true }
        return snap
    }

    public func selectCandidate(onPage index: Int) -> Bool {
        guard isCurrentGeneration else { return false }
        let selected = api.pointee.select_candidate_on_current_page(id, index) != 0
        if !learns, let after = composition(), after.isConfirmed { put(after.preview) }
        return selected
    }

    public func commitComposition() -> String? {
        guard isCurrentGeneration else { return nil }
        if !learns {
            // What librime would commit, without its commit.
            guard let composition = composition() else { return takeCommit() }
            put(composition.preview)
            return takeCommit()
        }
        guard api.pointee.commit_composition(id) != 0 else { return nil }
        return takeCommit()
    }

    public var rawInput: String {
        guard isCurrentGeneration else { return "" }
        return api.pointee.get_input(id).map { String(cString: $0) } ?? ""
    }

    public func clearComposition() {
        guard isCurrentGeneration else { return }
        api.pointee.clear_composition(id)
    }

    public func setAsciiMode(_ on: Bool) {
        guard isCurrentGeneration else { return }
        api.pointee.set_option(id, "ascii_mode", on ? 1 : 0)
    }

    /// librime reports positions as UTF-8 byte offsets.
    static func characterOffset(utf8 offset: Int, in text: String) -> Int {
        let bytes = Array(text.utf8)
        let clamped = max(0, min(offset, bytes.count))
        return String(decoding: bytes[..<clamped], as: UTF8.self).count
    }
}
