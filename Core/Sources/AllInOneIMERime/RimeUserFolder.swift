import AllInOneIMECore
import Foundation

/// What `RimeService.start` puts in librime's user folder before librime starts (and a redeploy before each deployment):
/// the lunar date database and the OpenCC data, copied there unless the copy is current; the schema list's patch.
extension RimeService {
    /// librime's user folder (and logs folder) made, with what the app supplies there: the lunar database, the OpenCC data
    /// (`openCCDir`), and the schema list's patch, `default.custom.yaml`, copied from the shared folder unless the user
    /// folder has one (it applies from there, and can be edited there).
    static func prepareUserFolder(sharedDataDir: URL, userDataDir: URL, logDir: URL?, openCCDir: URL?) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: userDataDir, withIntermediateDirectories: true)
        supplyLunarDatabase(sharedDataDir: sharedDataDir, userDataDir: userDataDir)
        if let openCCDir { supplyOpenCC(from: openCCDir, userDataDir: userDataDir) }
        if let logDir { try fm.createDirectory(at: logDir, withIntermediateDirectories: true) }
        let patch = "default.custom.yaml"
        let userPatch = userDataDir.appendingPathComponent(patch)
        let sharedPatch = sharedDataDir.appendingPathComponent(patch)
        guard !fm.fileExists(atPath: userPatch.path), fm.fileExists(atPath: sharedPatch.path) else { return }
        do {
            try fm.copyItem(at: sharedPatch, to: userPatch)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            // Copied meanwhile by another process starting librime on this new folder at the same moment (as `--register`
            // may, while macOS starts the input method it registered): the same file. This start used to fail on it.
            log.notice("default.custom.yaml was copied into the Rime user folder meanwhile")
        }
    }

    /// rime-ice's lunar translator opens `lua/lunar.db` relative to the user folder, unlike its scripts,
    /// which librime also finds in the shared folder: a copy goes there (`prepareLunarDatabase`), before librime starts
    /// and before each deployment (a language pack or app update changes the shared one). Never what stops pinyin: a
    /// copy that fails (a full disk, `lua` not a folder) is logged, and only the lunar dates are missing.
    static func supplyLunarDatabase(sharedDataDir: URL, userDataDir: URL) {
        do {
            try prepareLunarDatabase(sharedDataDir: sharedDataDir, userDataDir: userDataDir)
        } catch {
            log.error("lunar date database not copied into the Rime user folder: \(error.localizedDescription)")
        }
    }

    /// The shared `lua/lunar.db` copied into the user folder, unless the copy there is current; copied again once the
    /// shared one changed, as long as the copy is still the one made here (`LunarCopy`, beside it). One the user put
    /// there instead (or a link) is left as it is. Throws when the copy can't be made.
    static func prepareLunarDatabase(sharedDataDir: URL, userDataDir: URL) throws {
        let source = sharedDataDir.appendingPathComponent("lua/lunar.db").resolvingSymlinksInPath()
        let destination = userDataDir.appendingPathComponent("lua/lunar.db")
        let record = userDataDir.appendingPathComponent("lua/" + LunarCopy.fileName)
        let copied = (try? Data(contentsOf: record)).flatMap { try? JSONDecoder().decode(LunarCopy.self, from: $0) }
        let now = try prepareCopy(of: source, to: destination, recorded: copied)
        if let now, now != copied { try JSONEncoder().encode(now).write(to: record, options: .atomic) }
    }

    /// `source` copied to `destination`, unless the copy there is current (`copied`, its record, says it was made from
    /// the source as it is); copied again once the source changed, as long as the copy is still the one made here. One
    /// put there otherwise (or a link) is left as it is; one with the source's bytes and no record (copied before there
    /// was one: 0.6.7's first builds' lunar database) is taken for one made here. No source (another pack's schemas have
    /// no lunar database): nothing. The record of the copy now, to keep; nil: none. Throws when the copy can't be made.
    static func prepareCopy(of source: URL, to destination: URL, recorded copied: LunarCopy?) throws -> LunarCopy? {
        let fm = FileManager.default
        guard let shared = LunarCopy.Stamp(source, type: .typeRegular) else { return copied }
        // Anything there, a dangling link too.
        if (try? fm.attributesOfItem(atPath: destination.path)) != nil {
            let present = LunarCopy.Stamp(destination, type: .typeRegular)
            if let copied, present == copied.copy {
                guard copied.source != shared else { return copied }  // made here, from the source as it is
            } else if copied == nil, let present, try Data(contentsOf: destination) == Data(contentsOf: source) {
                return LunarCopy(source: shared, copy: present)  // the source's bytes: made here
            } else {
                return copied  // the user's own
            }
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: source).write(to: destination, options: .atomic)
        guard let copy = LunarCopy.Stamp(destination, type: .typeRegular) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
        }
        return LunarCopy(source: shared, copy: copy)
    }

    /// The app's OpenCC data for Traditional characters (`ChineseCharacters.openCCFiles`) in the user folder's
    /// `opencc`, where librime looks first (then in the shared folder, the pack, which has none): copied as the lunar
    /// database is (`prepareOpenCC`), before librime starts and before each deployment (an app update brings new ones).
    /// Never what stops pinyin: a copy that fails is logged, and only Traditional characters are missing (the Doctor says
    /// so, from librime's log).
    static func supplyOpenCC(from bundled: URL, userDataDir: URL) {
        do {
            try prepareOpenCC(from: bundled, userDataDir: userDataDir)
        } catch {
            log.error("OpenCC data not copied into the Rime user folder: \(error.localizedDescription)")
        }
    }

    /// Each of the app's OpenCC files (`bundled`) copied into the user folder's `opencc`, unless the copy there is current
    /// (`prepareCopy`), the records of the copies in one file beside them (`openCCRecord`). A file the user put
    /// there is left as it is. Throws when a copy can't be made (the others are made all the same).
    static func prepareOpenCC(from bundled: URL, userDataDir: URL) throws {
        let folder = userDataDir.appendingPathComponent("opencc", isDirectory: true)
        let record = folder.appendingPathComponent(openCCRecord)
        let copied = (try? Data(contentsOf: record)).flatMap { try? JSONDecoder().decode(OpenCCCopies.self, from: $0) } ?? [:]
        var copies = copied, failure: Error?
        for name in ChineseCharacters.openCCFiles {
            do {
                copies[name] = try prepareCopy(of: bundled.appendingPathComponent(name).resolvingSymlinksInPath(),
                                               to: folder.appendingPathComponent(name), recorded: copied[name])
            } catch {
                failure = failure ?? error
            }
        }
        if copies != copied { try JSONEncoder().encode(copies).write(to: record, options: .atomic) }
        if let failure { throw failure }
    }

    /// The records of the OpenCC files copied into the user folder (`prepareOpenCC`), by name, and their file there.
    typealias OpenCCCopies = [String: LunarCopy]
    static let openCCRecord = "opencc.allinoneime.json"

    /// When the user folder's `opencc` got the app's copy of the files `characters` convert with (`openCCData`: the newest
    /// copy's modification time), while each is still as `prepareOpenCC` copied it (its record lists it, and the file is
    /// that copy, not one of the user's own); nil otherwise, and for Simplified. The Doctor then takes librime's errors
    /// about the data logged before it for resolved (`Doctor.OpenCCNow.provided`); a run since couldn't read the copy.
    public static func providedOpenCC(userDataDir: URL, for characters: ChineseCharacters) -> Date? {
        let folder = userDataDir.appendingPathComponent("opencc", isDirectory: true)
        guard !characters.openCCData.isEmpty, let data = try? Data(contentsOf: folder.appendingPathComponent(openCCRecord)),
              let copied = try? JSONDecoder().decode(OpenCCCopies.self, from: data) else { return nil }
        var newest = -Double.infinity
        for name in characters.openCCData {
            guard let copy = copied[name]?.copy, LunarCopy.Stamp(folder.appendingPathComponent(name), type: .typeRegular) == copy
            else { return nil }
            newest = max(newest, copy.modified)
        }
        return Date(timeIntervalSince1970: newest)
    }
}
