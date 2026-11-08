import Darwin
import Foundation

/// The volumes mounted on this Mac, as the system's list of what is mounted has them (`getmntinfo`, which asks no volume
/// anything): which paths are on one of this Mac's own (`isLocal`), so that what is on a server is never read where
/// waiting matters (a server that doesn't answer would hold the key, or a search, until the system gives up on it).
public struct Mounts: Sendable {
    /// Each volume's mount point, lowercased (APFS and HFS+ compare names case aside), and whether it is this Mac's.
    let points: [(path: String, isLocal: Bool)]

    /// What is mounted now.
    public init() {
        var mounts: UnsafeMutablePointer<statfs>?
        let count = getmntinfo_r_np(&mounts, MNT_NOWAIT)
        defer { free(mounts) }
        let list = UnsafeBufferPointer(start: mounts, count: mounts == nil ? 0 : Int(max(count, 0)))
        self.init(points: list.map { mount in
            (withUnsafeBytes(of: mount.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) },
             mount.f_flags & UInt32(MNT_LOCAL) != 0)
        })
    }

    /// `points` as given (the tests' stand-ins).
    init(points: [(path: String, isLocal: Bool)]) {
        self.points = points.map { ($0.path.lowercased(), $0.isLocal) }
    }

    /// Whether the volume `path` is on is this Mac's, as the list has it: the one mounted deepest above it (none:
    /// this Mac's). `path` as written, its links not followed (`isLocal` follows them).
    func isLocalVolume(_ path: String) -> Bool {
        let path = path.lowercased()
        var best = (length: -1, isLocal: true)
        for point in points where point.path.utf8.count > best.length
            && (point.path == "/" || path == point.path || path.hasPrefix(point.path + "/")) {
            best = (point.path.utf8.count, point.isLocal)
        }
        return best.isLocal
    }

    /// Whether what `path` leads to is on a volume of this Mac and can be read at once. Each folder on the way is looked
    /// at only once the list says it is on one of this Mac's, so a server is never asked; the links on the way are
    /// followed (`~/NAS` → `/Volumes/share` is the server's, as `/volumes/share` is); and a folder a File Provider keeps in
    /// the cloud until it is opened (dataless) isn't: reading it would wait for the download. A path that isn't there is
    /// this Mac's as far as it goes.
    public func isLocal(_ path: String) -> Bool {
        var resolved = ""  // what the parts so far lead to, links followed ("": the root)
        var rest = path.split(separator: "/").reversed().map(String.init)  // what is left, the next part last
        var links = 0
        while let part = rest.popLast() {
            if part == "." { continue }
            if part == ".." {
                resolved = resolved.lastIndex(of: "/").map { String(resolved[..<$0]) } ?? ""
                continue
            }
            let next = resolved + "/" + part
            guard isLocalVolume(next) else { return false }
            var info = stat()
            guard lstat(next, &info) == 0 else { return true }
            guard info.st_flags & UInt32(SF_DATALESS) == 0 else { return false }
            guard info.st_mode & S_IFMT == S_IFLNK else {
                resolved = next
                continue
            }
            // As many links as the system follows in one path.
            links += 1
            guard links <= MAXSYMLINKS, let target = try? FileManager.default.destinationOfSymbolicLink(atPath: next) else { return false }
            if target.hasPrefix("/") { resolved = "" }
            rest += target.split(separator: "/").reversed().map(String.init)
        }
        return isLocalVolume(resolved.isEmpty ? "/" : resolved)
    }
}
