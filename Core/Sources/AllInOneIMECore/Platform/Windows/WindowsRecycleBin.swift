#if os(Windows)
import Foundation
import WinSDK

/// Windows' Recycle Bin, where `SystemFileOps.trash` puts what the core moves to the Trash (`ExtensionSources.trash`,
/// `ICloudSyncFolder.remove`): `SHFileOperationW` with undo (`FOF_ALLOWUNDO`: the user can restore it from the Recycle
/// Bin), without asking or showing progress, errors thrown instead of shown. Only from a fixed drive (`GetDriveTypeW`:
/// `DRIVE_FIXED`): on another (a network share, a removable drive) the Recycle Bin doesn't keep what it is given but
/// deletes it for good, so that is refused (`CocoaError.featureUnsupported`, as the Mac's `trashItem` where a volume
/// has no Trash), the item left there; a caller that means to delete it removes it (`FileManager.removeItem`).
enum WindowsRecycleBin {
    static func trash(_ url: URL) throws {
        // Like the Mac's `trashItem`: nothing there is an error.
        let path = url.withUnsafeFileSystemRepresentation { String(cString: $0!) }
        guard FileManager.default.fileExists(atPath: path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        guard driveType(of: path) == UINT(DRIVE_FIXED) else {
            throw CocoaError(.featureUnsupported, userInfo: [
                NSFilePathErrorKey: url.path,
                NSLocalizedDescriptionKey: "\(url.lastPathComponent) is on a drive without a Recycle Bin (a network share or a removable drive)",
            ])
        }
        // A list of paths, each ended by a NUL, a NUL after the last; a full path (the shell's relative ones are the
        // current folder's, and a relative one loses the undo).
        var from = Array(path.utf16) + [0, 0]
        let flags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT | FOF_NOCONFIRMMKDIR
        var operation = SHFILEOPSTRUCTW()
        operation.wFunc = UINT(FO_DELETE)
        operation.fFlags = FILEOP_FLAGS(flags)
        let result = from.withUnsafeMutableBufferPointer { from -> Int32 in
            operation.pFrom = UnsafePointer(from.baseAddress)
            return SHFileOperationW(&operation)
        }
        guard result == 0, !operation.fAnyOperationsAborted.boolValue else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path,
                                                           NSUnderlyingErrorKey: NSError(domain: "SHFileOperation", code: Int(result))])
        }
    }

    /// The kind of drive `path` is on (`GetDriveTypeW` of its volume's root, "C:\" or "\\server\share\"):
    /// `DRIVE_UNKNOWN` when that can't be told.
    private static func driveType(of path: String) -> UINT {
        var root = [WCHAR](repeating: 0, count: max(path.utf16.count, Int(MAX_PATH)) + 1)
        let found = path.withCString(encodedAs: UTF16.self) { GetVolumePathNameW($0, &root, DWORD(root.count)) }
        guard found else { return UINT(DRIVE_UNKNOWN) }
        return GetDriveTypeW(root)
    }
}
#endif
