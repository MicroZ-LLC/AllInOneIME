#if os(Windows)
import Foundation
import WinSDK

extension APIKeys.Keychain {
    /// The user's Windows Credential Manager (Control Panel → Credential Manager → Windows Credentials): a generic
    /// credential "AllInOneIME/<service>/<account>" for each account, kept on this computer for this user
    /// (`CRED_PERSIST_LOCAL_MACHINE`). The key is its secret; the host it is for its comment; its label, when it was made,
    /// the key's ending (`APIKeys.ending(of:)`) and when it was saved (`APIKeys.ItemAttributes.saved`) its attributes.
    /// It is this computer's own, as the Mac's login keychain is (`Kind.legacy`): nothing syncs it. A key longer than a credential holds (2,560 bytes)
    /// goes to a file in %LOCALAPPDATA%\AllInOneIME\Secrets (`CorePaths.dataDir`: this computer's, as the credential
    /// is, never a roaming profile's) that only this user on this computer can decrypt (DPAPI, `CryptProtectData`),
    /// which the credential names. A file no credential names any more is removed (`removeOrphans`).
    public static let credentialManager = credentialManager(service: APIKeys.service, folder: CorePaths.dataDir.appendingPathComponent("Secrets", isDirectory: true))

    /// The Credential Manager's items of `service`, the long keys' files in `folder` (tests use their own of both).
    static func credentialManager(service: String, folder: URL) -> APIKeys.Keychain {
        let store = CredentialStore(service: service, folder: folder)
        return APIKeys.Keychain(
            kind: .legacy,
            accounts: { (try? store.accounts()) ?? [] },
            attributes: { account in store.item(account).map(\.attributes) },
            read: { account in store.item(account).flatMap(store.key) },
            write: { account, key, label, comment, ending, saved in
                store.write(account, key: key, label: label, comment: comment, ending: ending, saved: saved)
            },
            setComment: { account, comment in store.setComment(account, comment) },
            delete: { account in store.delete(account) },
            message: { code in CredentialStore.message(code) },
            listing: { try store.accounts() })
    }
}

/// The calls on the Credential Manager behind `APIKeys.Keychain.credentialManager`. A write and a delete are one at a
/// time in this process (a long key's file is replaced along with its credential).
private final class CredentialStore: @unchecked Sendable {
    let service: String
    let folder: URL
    private let lock = NSLock()

    init(service: String, folder: URL) {
        self.service = service
        self.folder = folder
    }

    /// One credential as read, its secret still as kept (in it, or the name of its file).
    struct Item {
        var secret: Data
        var comment: String
        var modified: Date?
        var label: String?
        var created: Date?
        var ending: String?
        /// When the key was saved (`APIKeys.save`; nil: the credential doesn't say).
        var saved: Date?
        /// The file that holds the key, when it is too long for the credential.
        var file: String?

        var attributes: APIKeys.ItemAttributes {
            APIKeys.ItemAttributes(created: created ?? modified, modified: modified, comment: comment, ending: ending,
                                   label: label, saved: saved)
        }
    }

    // The attributes' keywords.
    private static let labelKeyword = "AllInOneIME.label"
    private static let createdKeyword = "AllInOneIME.created"
    private static let endingKeyword = "AllInOneIME.ending"
    private static let savedKeyword = "AllInOneIME.saved"
    private static let fileKeyword = "AllInOneIME.file"
    /// CRED_MAX_CREDENTIAL_BLOB_SIZE: 5 × 512 bytes.
    static let maxSecret = 5 * 512
    /// CRED_MAX_VALUE_SIZE: an attribute's value.
    private static let maxValue = 256

    /// Every credential's target starts so, whatever its service.
    private static let targetPrefix = "AllInOneIME/"

    func target(_ account: String) -> String { "\(Self.targetPrefix)\(service)/\(account)" }

    // MARK: Reading

    /// The credential for `account`; nil when there is none (or it can't be read).
    func item(_ account: String) -> Item? {
        read(account).item
    }

    /// The credential for `account`, or the error `CredReadW` gave (`ERROR_NOT_FOUND`: none).
    private func read(_ account: String) -> (item: Item?, error: DWORD) {
        var found: PCREDENTIALW?
        let ok = target(account).withCString(encodedAs: UTF16.self) { CredReadW($0, DWORD(CRED_TYPE_GENERIC), 0, &found) }
        guard ok, let found else { return (nil, GetLastError()) }
        defer { CredFree(found) }
        return (Self.item(found.pointee), 0)
    }

    /// What `credential` holds.
    private static func item(_ credential: CREDENTIALW) -> Item {
        var item = Item(secret: Data(), comment: credential.Comment.map { String(decodingCString: $0, as: UTF16.self) } ?? "")
        if let blob = credential.CredentialBlob, credential.CredentialBlobSize > 0 {
            item.secret = Data(bytes: blob, count: Int(credential.CredentialBlobSize))
        }
        item.modified = date(credential.LastWritten)
        let values = attributes(credential)
        item.label = values[labelKeyword]
        item.created = values[createdKeyword].flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        item.ending = APIKeys.ending(fromAttribute: values[endingKeyword].map { Data($0.utf8) })
        item.saved = APIKeys.saved(fromAttribute: values[savedKeyword])
        item.file = values[fileKeyword]
        return item
    }

    /// `credential`'s attributes that have a value, by keyword, their values read as UTF-8.
    private static func attributes(_ credential: CREDENTIALW) -> [String: String] {
        var values: [String: String] = [:]
        for index in 0..<Int(credential.AttributeCount) {
            guard let attribute = credential.Attributes?[index] else { break }
            guard let keyword = attribute.Keyword.map({ String(decodingCString: $0, as: UTF16.self) }),
                  let value = attribute.Value else { continue }
            values[keyword] = String(decoding: UnsafeBufferPointer(start: value, count: Int(attribute.ValueSize)), as: UTF8.self)
        }
        return values
    }

    /// The accounts of this service's credentials (none found: none); throws when they can't be listed (no Credential
    /// Manager in this logon session).
    func accounts() throws -> [String] {
        let prefix = target("")
        var count: DWORD = 0
        var found: UnsafeMutablePointer<PCREDENTIALW?>?
        let ok = (prefix + "*").withCString(encodedAs: UTF16.self) { CredEnumerateW($0, 0, &count, &found) }
        guard ok, let found else {
            let code = GetLastError()
            if code == DWORD(ERROR_NOT_FOUND) { return [] }
            throw APIKeys.KeychainError(status: Int32(bitPattern: code), message: Self.message(Int32(bitPattern: code)))
        }
        defer { CredFree(found) }
        var accounts = Set<String>()
        for index in 0..<Int(count) {
            guard let credential = found[index]?.pointee, credential.`Type` == DWORD(CRED_TYPE_GENERIC),
                  let name = credential.TargetName.map({ String(decodingCString: $0, as: UTF16.self) }),
                  name.hasPrefix(prefix), name.count > prefix.count else { continue }
            accounts.insert(String(name.dropFirst(prefix.count)))
        }
        return accounts.sorted()
    }

    /// The files AllInOneIME's credentials name (`CredEnumerateW`: of every service, which may share a folder); nil
    /// when they can't be listed (no Credential Manager in this logon session).
    private static func namedFiles() -> Set<String>? {
        var count: DWORD = 0
        var found: UnsafeMutablePointer<PCREDENTIALW?>?
        let ok = (targetPrefix + "*").withCString(encodedAs: UTF16.self) { CredEnumerateW($0, 0, &count, &found) }
        guard ok, let found else { return GetLastError() == DWORD(ERROR_NOT_FOUND) ? [] : nil }
        defer { CredFree(found) }
        var names = Set<String>()
        for index in 0..<Int(count) {
            guard let credential = found[index]?.pointee, credential.`Type` == DWORD(CRED_TYPE_GENERIC) else { continue }
            if let file = attributes(credential)[fileKeyword] { names.insert(file) }
        }
        return names
    }

    /// The key `item` holds: its secret, or its file's, decrypted.
    func key(_ item: Item) -> String? {
        guard let name = item.file else { return String(data: item.secret, encoding: .utf8) }
        guard Self.isFileName(name), let sealed = try? Data(contentsOf: folder.appendingPathComponent(name)),
              let data = Self.unprotect(sealed, entropy: Data(name.utf8)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Changing

    /// Sets the key, its label, comment, ending and save time (nil: the one there is kept).
    func write(_ account: String, key: String, label: String, comment: String, ending: String?,
               saved: Date?) -> APIKeys.KeychainStatus {
        lock.withLock {
            let old = item(account)
            var item = Item(secret: Data(key.utf8), comment: comment, label: label, created: old?.created ?? old?.modified ?? Date(),
                            ending: APIKeys.ending(fromAttribute: APIKeys.endingAttribute(ending)), saved: saved ?? old?.saved)
            var written: URL?
            if item.secret.count > Self.maxSecret {
                // Too long for the credential: in a file of its own, which the credential names.
                let name = "\(UUID().uuidString).secret"
                guard let sealed = Self.protect(item.secret, entropy: Data(name.utf8)) else { return .failed(Int32(bitPattern: GetLastError())) }
                let url = folder.appendingPathComponent(name)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try SystemFileOps().writePrivate(sealed, to: url)
                } catch {
                    return .failed(Int32(ERROR_WRITE_FAULT))
                }
                (item.secret, item.file, written) = (Data(), name, url)
            }
            let status = store(account, item)
            if status == .ok {
                if let file = old?.file, file != item.file { removeFile(file) }
                removeOrphans()
            } else if let written {
                try? FileManager.default.removeItem(at: written)
            }
            return status
        }
    }

    func setComment(_ account: String, _ comment: String) -> APIKeys.KeychainStatus {
        lock.withLock {
            let (found, code) = read(account)
            guard var item = found else { return code == DWORD(ERROR_NOT_FOUND) ? .notFound : .failed(Int32(bitPattern: code)) }
            item.comment = comment
            return store(account, item)
        }
    }

    func delete(_ account: String) -> APIKeys.KeychainStatus {
        lock.withLock {
            let file = item(account)?.file
            let deleted = target(account).withCString(encodedAs: UTF16.self) { CredDeleteW($0, DWORD(CRED_TYPE_GENERIC), 0) }
            guard deleted else {
                let code = GetLastError()
                return code == DWORD(ERROR_NOT_FOUND) ? .notFound : .failed(Int32(bitPattern: code))
            }
            if let file { removeFile(file) }
            removeOrphans()
            return .ok
        }
    }

    /// Writes `item` as the credential for `account` (`CredWriteW`: made, or replaced whole).
    private func store(_ account: String, _ item: Item) -> APIKeys.KeychainStatus {
        var values: [(String, String)] = [(Self.labelKeyword, item.label ?? ""),
                                          (Self.createdKeyword, String(item.created?.timeIntervalSince1970 ?? 0))]
        if let ending = item.ending { values.append((Self.endingKeyword, String(decoding: APIKeys.endingAttribute(ending), as: UTF8.self))) }
        if let saved = item.saved { values.append((Self.savedKeyword, APIKeys.savedAttribute(saved))) }
        if let file = item.file { values.append((Self.fileKeyword, file)) }
        // What the calls read must last through `CredWriteW`: kept in these buffers until it returns. What is too long
        // (a label) is cut between two characters.
        let keywords = values.map { Array($0.0.utf16) + [0] }
        let bytes = values.map { [UInt8](CredentialText.prefix($0.1, utf8: Self.maxValue).utf8) }
        let target = Array(target(account).utf16) + [0]
        let user = Array(account.utf16) + [0]
        let comment = Array(CredentialText.prefix(item.comment, utf16: 255).utf16) + [0]  // CRED_MAX_STRING_LENGTH: 256 with the NUL
        var secret = [UInt8](item.secret)
        let ok = withWideBuffers(keywords) { keywords in
            withByteBuffers(bytes) { values in
                var attributes = (0..<keywords.count).map { index in
                    CREDENTIAL_ATTRIBUTEW(Keyword: UnsafeMutablePointer(mutating: keywords[index]), Flags: 0,
                                          ValueSize: DWORD(bytes[index].count), Value: UnsafeMutablePointer(mutating: values[index]))
                }
                return target.withUnsafeBufferPointer { target in
                    user.withUnsafeBufferPointer { user in
                        comment.withUnsafeBufferPointer { comment in
                            secret.withUnsafeMutableBufferPointer { secret in
                                attributes.withUnsafeMutableBufferPointer { attributes in
                                    var credential = CREDENTIALW()
                                    credential.`Type` = DWORD(CRED_TYPE_GENERIC)
                                    credential.TargetName = UnsafeMutablePointer(mutating: target.baseAddress)
                                    credential.Comment = UnsafeMutablePointer(mutating: comment.baseAddress)
                                    credential.CredentialBlobSize = DWORD(secret.count)
                                    credential.CredentialBlob = secret.count > 0 ? secret.baseAddress : nil
                                    credential.Persist = DWORD(CRED_PERSIST_LOCAL_MACHINE)
                                    credential.AttributeCount = DWORD(attributes.count)
                                    credential.Attributes = attributes.baseAddress
                                    credential.UserName = UnsafeMutablePointer(mutating: user.baseAddress)
                                    return CredWriteW(&credential, 0)
                                }
                            }
                        }
                    }
                }
            }
        }
        // The secret's copy is wiped once written (the caller's `String` is the caller's).
        for index in secret.indices { secret[index] = 0 }
        return ok ? .ok : .failed(Int32(bitPattern: GetLastError()))
    }

    private func removeFile(_ name: String) {
        guard Self.isFileName(name) else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }

    /// How old a file no credential names must be to be removed: one younger may be another process's write, between
    /// its file and its credential.
    static let orphanAge: TimeInterval = 60

    /// Removes the long keys' files (`isFileName`) that no credential names any more: one whose credential was deleted
    /// elsewhere (Control Panel's Credential Manager), or whose write stopped between the file and the credential.
    /// Nothing when the credentials can't be listed. After each change (`write`, `delete`).
    private func removeOrphans() {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter(Self.isFileName)
        guard !files.isEmpty, let named = Self.namedFiles() else { return }
        let before = Date().addingTimeInterval(-Self.orphanAge)
        for name in files where !named.contains(name) {
            let url = folder.appendingPathComponent(name)
            guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                  modified < before else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// A long key's file is named "<UUID>.secret" (`write`): no other name in an attribute is taken for one.
    private static func isFileName(_ name: String) -> Bool {
        name.hasSuffix(".secret") && UUID(uuidString: String(name.dropLast(".secret".count))) != nil
    }

    // MARK: DPAPI

    /// `data` encrypted for this user on this computer (`CryptProtectData`, never asking), `entropy` mixed in: the file
    /// can't stand for another's.
    static func protect(_ data: Data, entropy: Data) -> Data? {
        crypt(data, entropy: entropy) { input, entropy, output in
            CryptProtectData(input, nil, entropy, nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), output)
        }
    }

    static func unprotect(_ data: Data, entropy: Data) -> Data? {
        crypt(data, entropy: entropy) { input, entropy, output in
            CryptUnprotectData(input, nil, entropy, nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), output)
        }
    }

    private static func crypt(_ data: Data, entropy: Data,
                              _ call: (UnsafeMutablePointer<DATA_BLOB>, UnsafeMutablePointer<DATA_BLOB>, UnsafeMutablePointer<DATA_BLOB>) -> Bool) -> Data? {
        var input = [UInt8](data), salt = [UInt8](entropy)
        return input.withUnsafeMutableBufferPointer { input in
            salt.withUnsafeMutableBufferPointer { salt in
                var inBlob = DATA_BLOB(cbData: DWORD(input.count), pbData: input.baseAddress)
                var saltBlob = DATA_BLOB(cbData: DWORD(salt.count), pbData: salt.baseAddress)
                var outBlob = DATA_BLOB()
                guard call(&inBlob, &saltBlob, &outBlob), let bytes = outBlob.pbData else { return nil }
                defer { LocalFree(bytes) }
                return Data(bytes: bytes, count: Int(outBlob.cbData))
            }
        }
    }

    // MARK: Messages and times

    /// What error `code` means: what Windows says (`FormatMessageW`), on one line; for 1312 (`ERROR_NO_SUCH_LOGON_SESSION`,
    /// "A specified logon session does not exist"), what that means here.
    static func message(_ code: Int32) -> String? {
        if code == Int32(ERROR_NO_SUCH_LOGON_SESSION) {
            return "The Credential Manager isn't available in this Windows sign-in (one over SSH with a key, or a service's): "
                + "keys can be saved and read only when signed in to Windows with a password, PIN or Windows Hello"
        }
        var buffer = [WCHAR](repeating: 0, count: 512)
        let count = FormatMessageW(DWORD(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS), nil, DWORD(bitPattern: code), 0,
                                   &buffer, DWORD(buffer.count), nil)
        guard count > 0 else { return nil }
        let text = String(decoding: buffer[..<Int(count)], as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// A `FILETIME` (100 ns steps since 1601) as a date.
    private static func date(_ time: FILETIME) -> Date? {
        let ticks = Int64(UInt64(time.dwHighDateTime) << 32 | UInt64(time.dwLowDateTime))
        guard ticks > 0 else { return nil }
        let unix = ticks - 116_444_736_000_000_000
        return Date(timeIntervalSince1970: TimeInterval(unix / 10_000_000) + TimeInterval(unix % 10_000_000) / 1e7)
    }
}

/// A credential's texts cut to what it holds, between two characters: a cut inside one would leave a broken one at the
/// end (half a UTF-8 sequence, half a surrogate pair, an accent without its letter).
enum CredentialText {
    /// The most of `text`'s characters that are at most `bytes` long in UTF-8 (an attribute's value).
    static func prefix(_ text: String, utf8 bytes: Int) -> String { prefix(text, bytes) { $0.utf8.count } }

    /// The most of `text`'s characters that are at most `units` UTF-16 code units long (a comment).
    static func prefix(_ text: String, utf16 units: Int) -> String { prefix(text, units) { $0.utf16.count } }

    private static func prefix(_ text: String, _ limit: Int, _ size: (String) -> Int) -> String {
        guard size(text) > limit else { return text }
        var kept = "", used = 0
        for character in text {
            let length = size(String(character))
            guard used + length <= limit else { break }
            kept.append(character)
            used += length
        }
        return kept
    }
}

/// `buffers` as pointers for the length of `body`.
private func withWideBuffers<T>(_ buffers: [[WCHAR]], _ body: ([UnsafePointer<WCHAR>]) -> T) -> T {
    var pointers: [UnsafePointer<WCHAR>] = []
    func next(_ index: Int) -> T {
        guard index < buffers.count else { return body(pointers) }
        return buffers[index].withUnsafeBufferPointer { buffer in
            pointers.append(buffer.baseAddress!)
            return next(index + 1)
        }
    }
    return next(0)
}

/// `buffers` as pointers for the length of `body` (an empty one as a pointer to nothing).
private func withByteBuffers<T>(_ buffers: [[UInt8]], _ body: ([UnsafePointer<UInt8>?]) -> T) -> T {
    var pointers: [UnsafePointer<UInt8>?] = []
    func next(_ index: Int) -> T {
        guard index < buffers.count else { return body(pointers) }
        return buffers[index].withUnsafeBufferPointer { buffer in
            pointers.append(buffer.count > 0 ? buffer.baseAddress : nil)
            return next(index + 1)
        }
    }
    return next(0)
}
#endif
