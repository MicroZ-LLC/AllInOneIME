import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
#endif

/// The file operations that differ by system: swapping two folders in one step, writing a file only the user can read,
/// a file's modification date, the Trash.
public protocol FileOps: Sendable {
    /// Puts `source` at `destination` in one step: when `exists`, swapped with what is there (`source` then holds the
    /// old); else renamed into place, never over something that appeared meanwhile. Throws, changing nothing, when it
    /// can't (`FileInUseError` when another program holds what is there open). Where the system has no swap of two
    /// folders (Windows), the old one is renamed aside first (`SystemFileOps.swapAside`), so for a moment nothing is at
    /// `destination`, and a process stopped then leaves it aside: `recoverInterruptedSwaps` puts it back.
    func swap(_ source: URL, into destination: URL, exists: Bool) throws
    /// What an interrupted `swap` left in `folder` put right: an old folder or file left aside goes back in place when
    /// nothing took it, else is deleted. Nothing to do where a swap is one step (Apple's systems, Linux, Android).
    func recoverInterruptedSwaps(in folder: URL)
    /// Writes `data` to a new file in `url`'s folder that is the user's only from the start, then renames it over `url`
    /// in one step: the data is never in a file others can read, and a file that was readable by others is replaced,
    /// not reused.
    func writePrivate(_ data: Data, to url: URL) throws
    /// When the file at `path` (a link followed) last changed, to the precision the system keeps; nil when there's none.
    func modificationDate(atPath path: String) -> Date?
    /// Moves `url` to the Trash where there is one (the user can put it back); elsewhere removes it.
    func trash(_ url: URL) throws
}

/// What another program holds open, so that it can't be moved (Windows: `ERROR_ACCESS_DENIED` or
/// `ERROR_SHARING_VIOLATION`, the system's `code`), even after a few tries: closing it there and trying again may do.
public struct FileInUseError: Error, Equatable, LocalizedError {
    public var path: String
    public var code: Int

    public init(path: String, code: Int) {
        self.path = path
        self.code = code
    }

    public var errorDescription: String? { "\((path as NSString).lastPathComponent) is in use by another program (error \(code))" }
}

/// The system's own calls: `renamex_np` on Apple platforms, `renameat2` on Linux and Android, `MoveFileExW` on Windows;
/// POSIX `open`/`fchmod`/`fsync`/`rename` for private writes (Windows: `CreateFileW` with an access list of the user
/// alone, `FlushFileBuffers`, `MoveFileExW`); `stat`'s nanosecond times (Windows: `GetFileTime`'s 100 ns ones).
public struct SystemFileOps: FileOps {
    public init() {}

    public func swap(_ source: URL, into destination: URL, exists: Bool) throws {
        #if canImport(Darwin)
        let result = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                renamex_np(from, to, UInt32(exists ? RENAME_SWAP : RENAME_EXCL))
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        #elseif canImport(Glibc) || canImport(Musl) || canImport(Android)
        // renameat2 (Linux 3.15; glibc 2.28, musl, Android's bionic from API 30) found at run time: not every C library's
        // headers declare it to Swift.
        typealias RenameAt2 = @convention(c) (Int32, UnsafePointer<CChar>?, Int32, UnsafePointer<CChar>?, UInt32) -> Int32
        guard let program = dlopen(nil, RTLD_NOW) else { throw POSIXError(.ENOSYS) }
        defer { dlclose(program) }
        guard let symbol = dlsym(program, "renameat2") else { throw POSIXError(.ENOSYS) }
        let renameat2 = unsafeBitCast(symbol, to: RenameAt2.self)
        let (atCurrentDirectory, noReplace, exchange): (Int32, UInt32, UInt32) = (-100, 1, 2)  // AT_FDCWD, RENAME_NOREPLACE, RENAME_EXCHANGE
        let result = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                renameat2(atCurrentDirectory, from, atCurrentDirectory, to, exists ? exchange : noReplace)
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        #elseif os(Windows)
        // A rename (MoveFileExW without MOVEFILE_REPLACE_EXISTING) fails when something is there. Windows has no swap: the
        // old one first gets a second, hidden name beside it, then the new one takes its place. A file's second name is a
        // hard link, so the new file is renamed over the old in one step and `destination` is never missing; a folder
        // (which nothing replaces) is renamed aside, so there is a moment between two renames when it is. Each step that
        // fails undoes those before it.
        // A folder another program has a file open in can't be renamed: a few tries over about 1.5 s (Explorer, an
        // antivirus or the search indexer let go soon), then `FileInUseError`.
        guard exists else { return try Self.move(source, to: destination) }
        let aside = Self.swapAside(for: destination)
        let linked = Self.isPlainFile(source) && Self.isPlainFile(destination)
            && Self.path(aside, { new in Self.path(destination) { CreateHardLinkW(new, $0, nil) } })
        if !linked {
            var wait = 0.1
            while true {
                do {
                    try Self.move(destination, to: aside)
                    break
                } catch let error as CocoaError {
                    guard let code = (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code,
                          code == Int(ERROR_ACCESS_DENIED) || code == Int(ERROR_SHARING_VIOLATION) else { throw error }
                    guard wait < 1 else { throw FileInUseError(path: destination.path, code: code) }
                    Thread.sleep(forTimeInterval: wait)
                    wait *= 2
                }
            }
        }
        do {
            try Self.move(source, to: destination, replacing: linked)
        } catch {
            if linked { _ = Self.path(aside) { DeleteFileW($0) } } else { try? Self.move(aside, to: destination) }
            throw error
        }
        do {
            try Self.move(aside, to: source)
        } catch {
            // The new one is in place. Undone only while the old one is still aside: a recovery may have taken it
            // meanwhile (`recoverInterruptedSwaps`, in another process), and then the new one stays, `source` empty.
            guard Self.path(aside, { GetFileAttributesW($0) }) != INVALID_FILE_ATTRIBUTES else { return }
            try? Self.move(destination, to: source)
            try? Self.move(aside, to: destination)
            throw error
        }
        #else
        // Elsewhere (no system call of its own known here): a folder is moved aside, then the new one in.
        let files = FileManager.default
        guard exists else { return try files.moveItem(at: source, to: destination) }
        let aside = Self.swapAside(for: destination)
        try files.moveItem(at: destination, to: aside)
        do {
            try files.moveItem(at: source, to: destination)
        } catch {
            try? files.moveItem(at: aside, to: destination)
            throw error
        }
        try files.moveItem(at: aside, to: source)
        #endif
    }

    public func recoverInterruptedSwaps(in folder: URL) {
        #if !(canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Android))
        let files = FileManager.default
        for name in (try? files.contentsOfDirectory(atPath: folder.path)) ?? [] {
            guard let original = Self.swappedName(name) else { continue }
            let aside = folder.appendingPathComponent(name), destination = folder.appendingPathComponent(original)
            // Something in place (a link too, even a broken one): the aside is the old one, which the swap would have deleted.
            if (try? files.attributesOfItem(atPath: destination.path)) != nil {
                try? files.removeItem(at: aside)
            } else {
                try? files.moveItem(at: aside, to: destination)
            }
        }
        #endif
    }

    /// Where `swap` puts what is at `destination` while the new one takes its place, beside it and hidden:
    /// ".<name>.swap-<UUID>", which the plugins' listing skips (`PluginStore.load`) and leftovers' removal keeps
    /// (`ExtensionSourceManager.removeLeftovers`).
    public static func swapAside(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).swap-\(UUID().uuidString)")
    }

    /// The name the aside `name` (`swapAside`) was moved from: "stock" for ".stock.swap-<UUID>"; nil for any other.
    public static func swappedName(_ name: String) -> String? {
        guard name.hasPrefix("."), let marker = name.range(of: ".swap-", options: .backwards),
              marker.lowerBound > name.index(after: name.startIndex), UUID(uuidString: String(name[marker.upperBound...])) != nil
        else { return nil }
        return String(name[name.index(after: name.startIndex)..<marker.lowerBound])
    }

    public func writePrivate(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        #if os(Windows)
        // Its access list, set as it is made, has one entry, the user's, and inherits none from the folder: Windows' 0600.
        let handle = try Self.userOnly { security in
            Self.path(temporary) {
                CreateFileW($0, DWORD(GENERIC_WRITE), 0, &security, DWORD(CREATE_NEW), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
            }
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { throw Self.lastError(temporary) }
        var written = data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                var n: DWORD = 0
                guard WriteFile(handle, bytes.baseAddress! + offset, DWORD(min(bytes.count - offset, 1 << 30)), &n, nil), n > 0 else { return false }
                offset += Int(n)
            }
            return true
        }
        written = FlushFileBuffers(handle) && written
        CloseHandle(handle)
        do {
            guard written else { throw Self.lastError(temporary) }
            try Self.move(temporary, to: url, replacing: true)
        } catch {
            _ = Self.path(temporary) { DeleteFileW($0) }
            throw error
        }
        #else
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: temporary.path]) }
        var written = fchmod(fd, 0o600) == 0  // whatever the umask
        data.withUnsafeBytes { bytes in
            var offset = 0
            while written, offset < bytes.count {
                let n = write(fd, bytes.baseAddress! + offset, bytes.count - offset)
                if n <= 0 { written = false } else { offset += n }
            }
        }
        written = fsync(fd) == 0 && written
        close(fd)
        guard written, rename(temporary.path, url.path) == 0 else {
            unlink(temporary.path)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        #endif
    }

    public func modificationDate(atPath path: String) -> Date? {
        #if os(Windows)
        // CreateFileW follows links; backup semantics opens a folder too. Reading attributes alone takes no share mode.
        let handle = path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(FILE_READ_ATTRIBUTES), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), nil,
                        DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        defer { CloseHandle(handle) }
        var time = FILETIME()
        guard GetFileTime(handle, nil, nil, &time) else { return nil }
        // 100 ns steps since 1601.
        let ticks = Int64(UInt64(time.dwHighDateTime) << 32 | UInt64(time.dwLowDateTime)) - 116_444_736_000_000_000
        return Date(timeIntervalSince1970: TimeInterval(ticks / 10_000_000) + TimeInterval(ticks % 10_000_000) / 1e7)
        #else
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        #if canImport(Darwin)
        let time = info.st_mtimespec
        #else
        let time = info.st_mtim
        #endif
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1e9)
        #endif
    }

    public func trash(_ url: URL) throws {
        #if canImport(Darwin)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        #else
        try FileManager.default.removeItem(at: url)
        #endif
    }
}

#if os(Windows)
extension SystemFileOps {
    /// `url`'s path as Windows' wide-character calls take it ("C:\…").
    private static func path<T>(_ url: URL, _ body: (UnsafePointer<WCHAR>) throws -> T) rethrows -> T {
        try url.withUnsafeFileSystemRepresentation { String(cString: $0!) }.withCString(encodedAs: UTF16.self, body)
    }

    /// Renames `from` to `to` on one volume (nothing is copied); over what is at `to` only when `replacing`.
    private static func move(_ from: URL, to: URL, replacing: Bool = false) throws {
        let moved = path(from) { old in path(to) { MoveFileExW(old, $0, replacing ? DWORD(MOVEFILE_REPLACE_EXISTING) : 0) } }
        guard moved else { throw lastError(to) }
    }

    /// A file, not a folder or a link.
    private static func isPlainFile(_ url: URL) -> Bool {
        let attributes = path(url) { GetFileAttributesW($0) }
        return attributes != INVALID_FILE_ATTRIBUTES && attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) == 0
    }

    /// `body` given the security attributes of a file only the user running this may open: one entry, for their account,
    /// with the folder's entries not inherited ("D:P(A;;FA;;;<their SID>)").
    private static func userOnly<T>(_ body: (inout SECURITY_ATTRIBUTES) throws -> T) throws -> T {
        var token: HANDLE?
        guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token), let token else { throw lastError(nil) }
        defer { CloseHandle(token) }
        var size: DWORD = 0
        _ = GetTokenInformation(token, TokenUser, nil, 0, &size)
        let user = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<TOKEN_USER>.alignment)
        defer { user.deallocate() }
        var sid: LPWSTR?
        guard GetTokenInformation(token, TokenUser, user, size, &size),
              ConvertSidToStringSidW(user.assumingMemoryBound(to: TOKEN_USER.self).pointee.User.Sid, &sid), let sid else { throw lastError(nil) }
        defer { LocalFree(sid) }
        var descriptor: PSECURITY_DESCRIPTOR?
        let rules = "D:P(A;;FA;;;\(String(decodingCString: sid, as: UTF16.self)))"
        guard rules.withCString(encodedAs: UTF16.self, {
            ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &descriptor, nil)
        }) else { throw lastError(nil) }
        defer { LocalFree(descriptor) }
        var security = SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size), lpSecurityDescriptor: descriptor,
                                           bInheritHandle: false)
        return try body(&security)
    }

    /// The last Windows call's error as Foundation's file errors say it (its code underneath).
    private static func lastError(_ url: URL?) -> CocoaError {
        let code = GetLastError()
        let kind: CocoaError.Code
        switch Int32(bitPattern: code) {
        case ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND: kind = .fileNoSuchFile
        case ERROR_FILE_EXISTS, ERROR_ALREADY_EXISTS: kind = .fileWriteFileExists
        case ERROR_ACCESS_DENIED, ERROR_SHARING_VIOLATION: kind = .fileWriteNoPermission
        case ERROR_DISK_FULL, ERROR_HANDLE_DISK_FULL: kind = .fileWriteOutOfSpace
        default: kind = .fileWriteUnknown
        }
        var info: [String: Any] = [NSUnderlyingErrorKey: NSError(domain: "Win32", code: Int(code))]
        if let url { info[NSFilePathErrorKey] = url.path }
        return CocoaError(kind, userInfo: info)
    }
}
#endif
