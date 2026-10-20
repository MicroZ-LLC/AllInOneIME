#if os(Windows)
import Foundation
import WinSDK

/// Writing denied to everyone in `folder` and what is in it, until the returned closure is called: an ACL's deny entry
/// (write, delete, delete a child), inherited by its files, which an administrator's token heeds too. What makes a save
/// fail on Windows, where a folder's read-only attribute keeps nothing from being written in it. Through the security
/// API in this process (a child process, `icacls`, would inherit the open files of the tests running beside this one).
/// Nil if it couldn't.
func denyWrites(in folder: URL) -> (() -> Void)? {
    let path = folder.withUnsafeFileSystemRepresentation { String(cString: $0!) }
    var old: PACL?
    var descriptor: PSECURITY_DESCRIPTOR?
    let read = path.withCString(encodedAs: UTF16.self) {
        GetNamedSecurityInfoW($0, SE_FILE_OBJECT, SECURITY_INFORMATION(DACL_SECURITY_INFORMATION), nil, nil, &old, nil, &descriptor)
    }
    guard read == ERROR_SUCCESS else { return nil }
    var everyone = [UInt8](repeating: 0, count: 68)  // SECURITY_MAX_SID_SIZE
    var size = DWORD(everyone.count)
    guard everyone.withUnsafeMutableBytes({ CreateWellKnownSid(WinWorldSid, nil, $0.baseAddress, &size) }) else {
        LocalFree(descriptor)
        return nil
    }
    let denied = everyone.withUnsafeMutableBytes { sid -> PACL? in
        var access = EXPLICIT_ACCESS_W()
        // Writing a file's data, appending, its attributes; adding a file or a folder; deleting (not reading: no
        // SYNCHRONIZE nor READ_CONTROL, which FILE_GENERIC_WRITE has).
        access.grfAccessPermissions = 0x0002 | 0x0004 | 0x0010 | 0x0100 | 0x0040 | 0x1_0000
        access.grfAccessMode = DENY_ACCESS
        access.grfInheritance = DWORD(SUB_CONTAINERS_AND_OBJECTS_INHERIT)
        access.Trustee.TrusteeForm = TRUSTEE_IS_SID
        access.Trustee.TrusteeType = TRUSTEE_IS_WELL_KNOWN_GROUP
        access.Trustee.ptstrName = sid.baseAddress!.assumingMemoryBound(to: WCHAR.self)
        var acl: PACL?
        return SetEntriesInAclW(1, &access, old, &acl) == ERROR_SUCCESS ? acl : nil
    }
    func set(_ acl: PACL?) -> Bool {
        path.withCString(encodedAs: UTF16.self) { name in
            SetNamedSecurityInfoW(UnsafeMutablePointer(mutating: name), SE_FILE_OBJECT, SECURITY_INFORMATION(DACL_SECURITY_INFORMATION),
                                  nil, nil, acl, nil) == ERROR_SUCCESS
        }
    }
    guard let denied, set(denied) else {
        LocalFree(descriptor)
        return nil
    }
    LocalFree(UnsafeMutableRawPointer(denied))
    // Back as it was (the folder's own entries; what its files inherited goes with the deny entry).
    return {
        _ = set(old)
        LocalFree(descriptor)
    }
}
#endif
