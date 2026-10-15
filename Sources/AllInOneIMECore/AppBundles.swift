import Foundation
import Security

/// The apps' code signatures, as the installer (「安装 AllInOneIME」) and the in-app updater check them.
public enum CodeSignature {
    public struct Failure: Error, Equatable {
        public var app: String
        public var status: OSStatus
    }

    /// The team that signed this process; nil when it's ad-hoc signed.
    public static let ownTeamID: String? = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }()

    /// The app is intact (every architecture, nested code included) and is the expected one: its bundle ID,
    /// and when `team` is given, signed by that team with an Apple-issued certificate. Who made an ad-hoc
    /// signed app can't be checked this way; that's what notarization, or the updater's signed manifest, is for.
    public static func check(_ app: URL, identifier: String, team: String?) throws {
        var text = "identifier \"\(identifier)\""
        if let team {
            text += " and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        }
        var requirement: SecRequirement?
        var code: SecStaticCode?
        var status = SecRequirementCreateWithString(text as CFString, [], &requirement)
        if status == errSecSuccess { status = SecStaticCodeCreateWithPath(app as CFURL, [], &code) }
        if status == errSecSuccess, let code {
            let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate))
            status = SecStaticCodeCheckValidity(code, flags, requirement)
        }
        guard status == errSecSuccess else { throw Failure(app: app.lastPathComponent, status: status) }
    }

    /// Takes the download's quarantine off the app and everything in it. macOS starts input methods by
    /// itself, with no way to confirm a quarantined one; the user's click (the installer opened, Update
    /// pressed) was that confirmation.
    public static func removeQuarantine(_ app: URL) {
        removexattr(app.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        let items = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)
        while let item = items?.nextObject() as? URL {
            removexattr(item.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }
}

/// Replaces installed apps with new ones the way the installer and the updater both do: each installed app is
/// moved aside first (into `aside`, on the same volume, so each move is a rename), then each new one is
/// moved into place. A failure on the way removes what was placed and puts the old apps back, so the user
/// is never left without an input method; `rollBack` does the same later (the new app didn't start), and
/// `commit` deletes the old apps once the new ones work.
public struct BundleSwap: Sendable {
    public struct Move: Equatable, Sendable {
        /// Where the app was installed, and where it waits now.
        public var from: URL
        public var to: URL
    }

    public enum Failure: Error, LocalizedError, Equatable {
        /// Something went wrong (`reason`), and an old app couldn't be moved back either; it's kept in `folder`.
        case notRestored(String, folder: String)

        public var errorDescription: String? {
            switch self {
            case let .notRestored(reason, folder):
                return "\(reason); the previous apps couldn't be put back and are in \(folder)"
            }
        }
    }

    public let aside: URL
    public private(set) var movedAside: [Move] = []
    public private(set) var placed: [URL] = []

    /// Doesn't follow a symbolic link at the end, so a dangling one counts as well.
    public static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Moves those of `replacing` that exist into `aside` (made if missing), then each new app to its
    /// destination. Throws what went wrong once everything is back as it was, or `Failure.notRestored`.
    public static func perform(placing items: [(new: URL, destination: URL)], replacing: [URL], aside: URL) throws -> BundleSwap {
        let manager = FileManager.default
        try manager.createDirectory(at: aside, withIntermediateDirectories: true)
        var swap = BundleSwap(aside: aside)
        do {
            for (index, app) in replacing.enumerated() where exists(app) {
                let parked = aside.appendingPathComponent("\(index)-\(app.lastPathComponent)")
                try manager.moveItem(at: app, to: parked)
                swap.movedAside.append(Move(from: app, to: parked))
            }
            for item in items {
                try manager.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.moveItem(at: item.new, to: item.destination)
                swap.placed.append(item.destination)
            }
        } catch {
            try swap.rollBack(reason: error.localizedDescription)
            throw error
        }
        return swap
    }

    private init(aside: URL) { self.aside = aside }

    /// Removes the apps placed and moves the previous ones back to where they were.
    public func rollBack(reason: String) throws {
        let manager = FileManager.default
        for app in placed { try? manager.removeItem(at: app) }
        var restored = true
        for item in movedAside.reversed() where (try? manager.moveItem(at: item.to, to: item.from)) == nil {
            restored = false
        }
        guard restored else { throw Failure.notRestored(reason, folder: aside.path) }
    }

    /// The new apps stay: the previous ones are deleted.
    public func commit() {
        try? FileManager.default.removeItem(at: aside)
    }
}
