import AllInOneIMECore
import Foundation

// Clipboard history's recording on this Mac: what it reads of the clipboard and when it records a copy into the store
// (`ClipboardHistoryStore`, beside it).

/// Whether this app may read the clipboard now without the system asking the user (macOS 15.4:
/// `NSPasteboard.accessBehavior`, Privacy & Security → Paste from Other Apps), as told without asking.
public enum ClipboardAccess: String, Equatable, Sendable {
    /// Allow (or a macOS before 15.4, which never asks).
    case allowed
    /// Ask: each read asks first.
    case asks
    /// Never asked yet: the app isn't in Paste from Other Apps' list until a read has asked once.
    case notListed
    /// Deny.
    case denied
}

/// What clipboard history reads of a pasteboard (the general one, `SystemClipboard`; a test's fake): the change count
/// and `access`, which never ask the user; the types on it and its text, read only once `access` is `.allowed`.
public protocol ClipboardSource: AnyObject {
    var changeCount: Int { get }
    var access: ClipboardAccess { get }
    var types: [String] { get }
    /// Its plain text (rich text's too); nil: no text (an image, a colour), or none read (`SystemClipboard`: a copy made
    /// on an iPhone or another Mac).
    func text() -> String?
    /// The image on it, as PNG, where an image is what was copied (its first type an image's: a screenshot, Copy Image);
    /// nil otherwise (0.6.8.2).
    func image() -> ClipboardImage?
}

/// An image being made ready off the main thread (`ClipboardRecorder.imageWork`): what that came to, told from any thread,
/// and its adding to the store, on the main thread once: at its turn there, or earlier, as ⌃V's look waits for it.
// Unchecked: `result` is behind the lock; `add` and `outcome` are used on the main thread only.
private final class PreparingImage: @unchecked Sendable {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var value: ClipboardHistoryStore.Prepared?
    /// Adds it to the store; nil once it has.
    var add: ((ClipboardHistoryStore.Prepared) -> ClipboardRecorder.Outcome)?
    /// What adding it came to (`imageQueued` until it has).
    private(set) var outcome = ClipboardRecorder.Outcome.imageQueued

    /// What making it ready came to; nil: not yet.
    var result: ClipboardHistoryStore.Prepared? { lock.withLock { value } }

    /// Made ready (on any thread): `prepared` kept, and handed on.
    func prepared(_ prepared: ClipboardHistoryStore.Prepared) -> ClipboardHistoryStore.Prepared {
        lock.withLock { value = prepared }
        ready.signal()
        return prepared
    }

    /// Whether it is ready, waiting `seconds` at most for it.
    func wait(_ seconds: TimeInterval) -> Bool {
        result != nil || ready.wait(timeout: .now() + seconds) == .success
    }

    /// Added to the store, once (main thread).
    func added(_ prepared: ClipboardHistoryStore.Prepared) {
        guard let add else { return }
        self.add = nil
        outcome = add(prepared)
    }
}

/// A value handed back to the main thread it came from (unchecked: it is only ever used there).
private struct MainThreadOnly<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Records each copy into `store` (`poll`, on a timer): an image where one was copied (`ClipboardSource.image`; one over
/// `ClipboardHistoryImage.maxBytes` isn't), else the text copied, as `ClipboardSource.text` reads it, unless
/// reading it would ask the user (`access` not `.allowed`: nothing is read then, only the change count and the access,
/// which never ask), it was copied during secure input (a password field had the keys when it changed, or at the look
/// before), it was copied in a password manager (`PasswordManagers`: its app frontmost when it changed, or at the look
/// before: Keychain Access's Copy Password marks nothing), it is marked never to be kept (`neverRecorded`: password managers and clipboard tools mark theirs, as
/// TerminalPaste marks its own writes), it is neither an image nor text (a file, a colour) or was copied on an iPhone or
/// another Mac (Universal Clipboard: never read, `SystemClipboard.remoteType`), it is blank, or it is longer than
/// `ClipboardHistoryItem.maxLength`; nor the clipboard TerminalPaste puts back after its paste (`putBack`). Used on one
/// thread (the input method's main one).
public final class ClipboardRecorder {
    /// Why a change wasn't recorded.
    public enum Outcome: Equatable, Sendable {
        case unchanged, recorded
        case notAllowed, secureInput, marked, notText, blank, tooLong
        /// Copied in a password manager (`PasswordManagers`): its app was the frontmost when it changed, or at the look before.
        case passwordManager
        /// An image being made ready off the main thread (`imageWork`): recorded once it is.
        case imageQueued
        /// It couldn't be written (a full disk): nothing kept.
        case notSaved
        /// The newest kept already (a copy of it again).
        case same
    }

    /// Never recorded (nspasteboard.org's markers, which password managers and clipboard tools set, and the older ones of
    /// 1Password, KeeWeb and others, as `@reply`'s ⌃V leaves them alone too), nor a file (Finder's copy has its name as
    /// text).
    public static let neverRecorded: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping", "Pasteboard generator type",
        "net.antelle.keeweb", "public.file-url",
    ]

    public let store: ClipboardHistoryStore
    let source: ClipboardSource
    /// Where images are made ready, one at a time (a later copy never overtakes an earlier one); as soon as the system can,
    /// as ⌃V's look may be waiting for one (`quickImageWait`: a wait on the main thread lends the queue no priority).
    static let imageQueue = DispatchQueue(label: "com.allinoneime.inputmethod.clipboard-images", qos: .userInitiated)
    /// Runs an image's preparation (its PNG, id, thumbnail and files: `ClipboardHistoryStore.prepare`) and hands its result
    /// to the second closure on the main thread: off the main thread by default, so a large copy never holds typing up;
    /// a test's runs it at once.
    public var imageWork: (@escaping @Sendable () -> ClipboardHistoryStore.Prepared, @escaping (ClipboardHistoryStore.Prepared) -> Void) -> Void = { prepare, done in
        // `done` runs on the main thread only, where the recorder is used; one image after another, in the order copied.
        let main = MainThreadOnly(done)
        ClipboardRecorder.imageQueue.async {
            let prepared = prepare()
            DispatchQueue.main.async { main.value(prepared) }
        }
    }
    /// The longest ⌃V's look waits for an image to be made ready (`poll(limit:quick:)`): a screenshot's takes 15–35 ms on
    /// an M4 (2560 × 1664 pixels; a 6K one's 120 ms); one taking longer is kept as it is ready, after the panel.
    public static let quickImageWait: TimeInterval = 0.15
    /// The images being made ready, in the order copied, until each is added on the main thread.
    private var preparing: [PreparingImage] = []
    let secureInput: () -> Bool
    /// The frontmost app's bundle id (nil: none known).
    let frontmostApp: () -> String?
    let now: () -> Date
    /// The change count last looked at (nil: none yet: what's on the clipboard is recorded at the first look, at launch),
    /// and whether secure input was on then.
    private var seen: Int?
    private var wasSecure = false
    /// Whether a password manager was the frontmost app at the last look.
    private var wasInPasswordManager = false
    /// The access as told at the last change.
    public private(set) var access: ClipboardAccess
    /// The change count of the copy the store has as its newest (recorded, or the newest already); nil: none since launch.
    private var newestSeen: Int?

    /// Whether what's on the clipboard now is the store's newest copy, unchanged since (the change count only: never asks).
    public var clipboardIsNewest: Bool { newestSeen != nil && newestSeen == source.changeCount }

    public init(source: ClipboardSource, store: ClipboardHistoryStore, secureInput: @escaping () -> Bool,
                frontmostApp: @escaping () -> String?, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.store = store
        self.secureInput = secureInput
        self.frontmostApp = frontmostApp
        self.now = now
        access = source.access
    }

    /// A look at the clipboard: a change since the last recorded (`limit`: how many are kept). `quick`: the look of a
    /// panel about to show (⌃V), which waits for it: a text copied is kept in memory at once and its file written off the
    /// main thread (`ClipboardHistoryStore.record(_:at:limit:savingLater:)`); an image copied just before, made ready off
    /// the main thread as any is, is waited for (`quickImageWait` at most) and kept at once, as is one a look before
    /// found, still being made ready: the panel has its kept row (its thumbnail, its preview), not the image on the
    /// clipboard. ⌃V is the user asking for the history, the clipboard's image with it.
    @discardableResult
    public func poll(limit: Int, quick: Bool = false) -> Outcome {
        let secure = secureInput()
        let inPasswordManager = PasswordManagers.contains(frontmostApp())
        defer { (wasSecure, wasInPasswordManager) = (secure, inPasswordManager) }
        let count = source.changeCount
        guard count != seen else {
            if quick { waitForImages() }
            return .unchanged
        }
        seen = count
        access = source.access
        guard access == .allowed else { return .notAllowed }
        guard !secure, !wasSecure else { return .secureInput }
        guard !inPasswordManager, !wasInPasswordManager else { return .passwordManager }
        guard Set(source.types).isDisjoint(with: Self.neverRecorded) else { return .marked }
        if let image = source.image() {
            let (store, date, generation) = (store, now(), store.generation)
            let preparing = PreparingImage()
            preparing.add = { [weak self] prepared in
                guard let self else { return .imageQueued }
                self.preparing.removeAll { $0 === preparing }
                // Cleared or turned off meanwhile: not kept.
                if case let .ready(ready) = prepared, store.generation != generation {
                    store.discard(ready)
                    return .imageQueued
                }
                switch prepared {
                case let .ready(ready):
                    // The newest still on the clipboard only if nothing was copied since.
                    if source.changeCount == count { newestSeen = count }
                    return store.add(ready, at: date, limit: limit) ? .recorded : .same
                case .tooLarge:
                    return .tooLong
                case .notSaved:
                    return .notSaved
                }
            }
            self.preparing.append(preparing)
            imageWork({ preparing.prepared(store.prepare(image)) }) { preparing.added($0) }
            if quick { waitForImages() }
            return preparing.outcome
        }
        guard let text = source.text() else { return .notText }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .blank }
        guard text.utf16.count <= ClipboardHistoryItem.maxLength * 4, text.count <= ClipboardHistoryItem.maxLength else { return .tooLong }
        newestSeen = count
        return store.record(text, at: now(), limit: limit, savingLater: quick) ? .recorded : .same
    }

    /// The images being made ready waited for, `quickImageWait` at most (the last of them: they are made ready one after
    /// another), and those ready by then added now, in the order copied, not at their turn on the main thread.
    private func waitForImages() {
        guard let last = preparing.last, last.wait(Self.quickImageWait) else { return }
        for image in preparing {
            if let prepared = image.result { image.added(prepared) }
        }
    }

    /// What's on the clipboard now is never recorded, only a copy made after it (Clear History, the history turned off
    /// and on again): its change count is remembered as looked at, which never asks.
    public func forget() {
        seen = source.changeCount
        newestSeen = nil
    }

    /// The clipboard put back at change count `count` as it was at `was`, after a paste of ours (`TerminalPaste`): never
    /// recorded as a new copy, where `was` was looked at already (recorded, or skipped: copied during secure input, before
    /// Clear History); the store's newest still, if it was. Not looked at yet: the next look takes it as it would have.
    public func putBack(at count: Int, asAt was: Int) {
        guard let seen, seen >= was else { return }
        self.seen = count
        if newestSeen == was { newestSeen = count }
    }
}
