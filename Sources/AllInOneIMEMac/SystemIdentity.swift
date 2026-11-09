import AllInOneIMECore
import Foundation

/// AllInOneIME's system identity since 0.7.2: the bundle IDs (`Updater.bundleID`, the input source's ID too, and
/// `Updater.settingsBundleID`) and the keychain access group (`KeySync.accessGroup`) macOS knows it by. The versions
/// before it had another one; 0.7.1, the last of them, moves an install to this one, carrying the settings and keys over
/// (by itself when it updates, or asked with its `--migrate-identity`, which the installer and `make install` use).
/// Nothing here names the identity before: an install of it is told by its bundle ID not being this one's.
public enum SystemIdentity {
    /// The first version with this identity.
    public static let since = "0.7.2"
    /// What `--migrate-identity --check` prints in a version that can move itself to this identity.
    public static let moveCheckLine = "migrate-identity: 1"

    /// The input method installed, as the installer finds it before replacing it.
    public enum Installed: Equatable, Sendable {
        case none
        /// This identity's: any version from 0.7.2 on.
        case this
        /// Another identity's that moves itself to this one, carrying the settings and keys over (0.7.1).
        case movable(version: String?)
        /// Another identity's that can't (0.7.0 and earlier): replaced anyway, its keys stay with it.
        case tooOld(version: String?)
    }

    /// `info`: the installed input method's Info.plist (nil: none is installed); `check`: what its `--migrate-identity
    /// --check` printed, asked only of another identity's (nil: it didn't answer, as one that doesn't know the option).
    public static func installed(info: [String: Any]?, check: () -> String?) -> Installed {
        guard let info else { return .none }
        guard info["CFBundleIdentifier"] as? String != Updater.bundleID else { return .this }
        let version = info["CFBundleShortVersionString"] as? String
        let answered = check()?.split(whereSeparator: \.isNewline).contains { $0 == moveCheckLine } == true
        return answered ? .movable(version: version) : .tooOld(version: version)
    }

    /// Whether `result` (what an update, or the installer, left for the input method that starts next) moved this Mac to
    /// this identity: it went in, from a version before it. The input method then says once which permissions macOS asks
    /// for again (`UpdateController`).
    public static func moved(_ result: UpdateResult) -> Bool {
        result.ok && result.from.range(of: #"^[0-9]+(\.[0-9]+)*$"#, options: .regularExpression) != nil
            && SemVer.compare(result.from, since) < 0 && SemVer.compare(result.to, since) >= 0
    }

    /// What the input method shows first, of its own, when it starts.
    public enum FirstShown: Equatable, Sendable {
        case nothing
        /// About from its top, at once (before any other page: the settings window asked for at launch too): the step to
        /// add the input source, which macOS leaves to the user. Nothing of AllInOneIME types until it is done.
        case inputSourceStep
        /// About with Troubleshoot outlined: the permissions to allow again.
        case permissions
    }

    /// After `result` (nil: none was left for it), with its own input source enabled or not: moved to this identity, the
    /// step to add the input source while it isn't, else the permissions; nothing otherwise (an update within this
    /// identity, one that didn't go in, a launch without one).
    public static func firstShown(after result: UpdateResult?, inputSourceEnabled: Bool) -> FirstShown {
        guard let result, moved(result) else { return .nothing }
        return inputSourceEnabled ? .permissions : .inputSourceStep
    }
}
