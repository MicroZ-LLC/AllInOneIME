import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The file operations that differ by system: swapping two folders in one step, writing a file only the user can read,
/// a file's modification date, the Trash.
public protocol FileOps: Sendable {
    /// Puts `source` at `destination` in one step: when `exists`, swapped with what is there (`source` then holds the
    /// old); else renamed into place, never over something that appeared meanwhile. Throws, changing nothing, when it
    /// can't.
    func swap(_ source: URL, into destination: URL, exists: Bool) throws
    /// Writes `data` to a new file in `url`'s folder that is the user's only from the start, then renames it over `url`
    /// in one step: the data is never in a file others can read, and a file that was readable by others is replaced,
    /// not reused.
    func writePrivate(_ data: Data, to url: URL) throws
    /// When the file at `path` (a link followed) last changed, to the precision the system keeps; nil when there's none.
    func modificationDate(atPath path: String) -> Date?
    /// Moves `url` to the Trash where there is one (the user can put it back); elsewhere removes it.
    func trash(_ url: URL) throws
}

/// The system's own calls: `renamex_np` on Apple platforms, `renameat2` on Linux; POSIX `open`/`fchmod`/`fsync`/`rename`
/// for private writes (Windows: an atomic write in the user's own folder); `stat`'s nanosecond times.
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
        #elseif canImport(Glibc)
        // renameat2 (Linux 3.15, glibc 2.28) found at run time: not every glibc header declares it to Swift.
        typealias RenameAt2 = @convention(c) (Int32, UnsafePointer<CChar>?, Int32, UnsafePointer<CChar>?, UInt32) -> Int32
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "renameat2") else { throw POSIXError(.ENOSYS) }
        let renameat2 = unsafeBitCast(symbol, to: RenameAt2.self)
        let (atCurrentDirectory, noReplace, exchange): (Int32, UInt32, UInt32) = (-100, 1, 2)  // AT_FDCWD, RENAME_NOREPLACE, RENAME_EXCHANGE
        let result = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                renameat2(atCurrentDirectory, from, atCurrentDirectory, to, exists ? exchange : noReplace)
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        #else
        // Windows: ReplaceFileW swaps files, not folders; a folder is moved aside, then the new one in.
        let files = FileManager.default
        guard exists else { return try files.moveItem(at: source, to: destination) }
        let aside = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString)")
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

    public func writePrivate(_ data: Data, to url: URL) throws {
        #if os(Windows)
        // A new file in the user's profile is theirs alone (its ACL); written whole, then moved over the old.
        try data.write(to: url, options: .atomic)
        #else
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
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
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
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
