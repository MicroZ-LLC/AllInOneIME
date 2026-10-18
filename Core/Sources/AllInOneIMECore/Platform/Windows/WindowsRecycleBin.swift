#if os(Windows)
import Foundation
import WinSDK

/// Windows' Recycle Bin, where `SystemFileOps.trash` puts what the core moves to the Trash (`ExtensionSources.trash`,
/// `ICloudSyncFolder.remove`): `SHFileOperationW` with undo (`FOF_ALLOWUNDO`: the user can restore it from the Recycle
/// Bin), without asking or showing progress, errors thrown instead of shown. A file or folder on a drive without a
/// Recycle Bin (a network share, a removable drive), or too big for it, is deleted, as Explorer does after asking:
/// the core only trashes what the user chose to remove.
enum WindowsRecycleBin {
    static func trash(_ url: URL) throws {
        // Like the Mac's `trashItem`: nothing there is an error.
        let path = url.withUnsafeFileSystemRepresentation { String(cString: $0!) }
        guard FileManager.default.fileExists(atPath: path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
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
}
#endif
