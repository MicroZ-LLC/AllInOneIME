import AllInOneIMECore
import AppKit
import InputMethodKit

/// `@reply` and screenshots in a draft, the Mac's side (the logic is the core's: `Composer+Reply.swift`, `ScreenText`,
/// `Reply.swift`, the session's `SessionTasks.recognize`): the clipboard as ⌃V finds it, the text around the caret through
/// IMK, Vision warmed up when a draft starts with an image on the clipboard, and the custom commands a built-in took the
/// name of, renamed once.
extension AllInOneIMEInputController {
    /// The clipboard as a draft takes it (`ClipboardContent`): its text first, else a PNG or TIFF image; nothing for what
    /// password managers mark as concealed or transient (nspasteboard.org, and the older markers), and when pasting from
    /// other apps is denied to this one. (Nothing is read during secure input: `Effect.readClipboard`.) Without
    /// `imageData`, an image is told by the clipboard's types alone, its data never read (`.image` with none: clipboard
    /// history's first row).
    static func clipboardContent(_ pasteboard: NSPasteboard, imageData: Bool = true) -> ClipboardContent {
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny { return .none }
        let types = pasteboard.types ?? []
        let hidden = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword",
                      "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping", "Pasteboard generator type",
                      "net.antelle.keeweb"].map { NSPasteboard.PasteboardType(rawValue: $0) }
        guard hidden.allSatisfy({ !types.contains($0) }) else { return .none }
        if types.contains(.string), let text = pasteboard.string(forType: .string) { return .text(text) }
        for type in [NSPasteboard.PasteboardType.png, .tiff] where types.contains(type) {
            guard imageData else { return .image(Data()) }
            // Larger than a draft takes: the composer says so (`Composer.maxImageBytes`).
            if let image = pasteboard.data(forType: type) { return .image(image) }
        }
        return .none
    }

    /// What the log says of the clipboard read: only how much, never the text or the image.
    static func logged(_ content: ClipboardContent) -> String {
        switch content {
        case let .text(text): return "\(text.count) chars"
        case let .image(image): return image.isEmpty ? "an image (its data not read)" : "an image of \(image.count / 1024) KB"
        case .none: return "nothing usable"
        }
    }

    /// Vision loaded ahead of time, in the languages a screenshot is read in (`ScreenText.languages`), once a command
    /// that takes one is picked (`Composer.draftTakesScreenshot`; not on "@" alone, a mention in a chat app) with an image
    /// on the clipboard (only the clipboard's types are looked at), once per clipboard: the screenshot pasted next is read
    /// quickly.
    @MainActor
    func warmUpScreenshotReading() {
        guard warmsUpVision, composer.draftTakesScreenshot, !services.secureInputActive() else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != Self.warmedFor else { return }
        Self.warmedFor = pasteboard.changeCount
        let types = pasteboard.types ?? []
        guard types.contains(.png) || types.contains(.tiff) else { return }
        let recognizer = services.recognizeText, languages = ScreenText.languages(services.loadSettings())
        Task.detached(priority: .utility) { await recognizer.prepare(languages: languages) }
    }

    /// The clipboard Vision was last warmed up for (`warmUpScreenshotReading`).
    nonisolated(unsafe) static var warmedFor = -1

    /// The text around the caret (`Composer.readFieldText`), without the draft: up to 1,500 characters before it and after
    /// it as the field tells them (IMK), past the selection or the marked text. None during secure input, nor in a
    /// terminal (its text isn't being edited).
    @MainActor
    func readFieldText(from target: IMKTextInput?) -> FieldText? {
        readFieldText(from: target, before: ReplyContext.Limits.fieldBefore, after: ReplyContext.Limits.fieldAfter, purpose: "@reply")
    }

    /// The text around the caret, up to `before` characters before it and `after` after it, for `purpose` (the log's).
    @MainActor
    func readFieldText(from target: IMKTextInput?, before beforeLimit: Int, after afterLimit: Int, purpose: String) -> FieldText? {
        guard !services.secureInputActive(), let target, !Self.isTerminal(target) else { return nil }
        let length = target.length()
        guard length > 0, length != NSNotFound else { return nil }
        let marked = target.markedRange(), selected = target.selectedRange()
        let around: NSRange
        if marked.location != NSNotFound, marked.length > 0 {
            around = marked
        } else if selected.location != NSNotFound, selected.length != NSNotFound {
            around = selected
        } else {
            return nil
        }
        // UTF-16 units, twice the characters kept: an emoji or a rare character takes two.
        let (span, afterSpan) = (beforeLimit * 2, afterLimit * 2)
        let start = min(around.location, length)
        let end = min(NSMaxRange(around), length)
        let beforeRange = NSRange(location: max(0, start - span), length: start - max(0, start - span))
        let afterRange = NSRange(location: end, length: min(afterSpan, length - end))
        let before = beforeRange.length > 0 ? target.attributedSubstring(from: beforeRange)?.string ?? "" : ""
        let after = afterRange.length > 0 ? target.attributedSubstring(from: afterRange)?.string ?? "" : ""
        guard !before.isEmpty || !after.isEmpty else { return nil }
        log.notice("field text read for \(purpose, privacy: .public) (\(before.count) + \(after.count) characters)")
        return FieldText(before: before, after: after)
    }
}

/// The custom commands a built-in took the name of (`Config.freeBuiltinNames`): renamed once when the input method starts,
/// the config written, and the next text field says so once (`SessionServices.takeRenameNotice`).
enum BuiltinRenames {
    static let key = "builtinRenamesToTell"

    /// Renames them in the config at `url` (if any are to be), writes only their names, and keeps their new names to tell. The new
    /// names are free of the plugins' and script extensions' too (`taken`; nil: the installed ones, looked for only when
    /// a custom command has a built-in's name).
    @discardableResult
    static func apply(configURL url: URL = Config.defaultURL, defaults: UserDefaults = .standard,
                      taken: [String]? = nil) -> [(old: String, new: String)] {
        guard var config = try? Config.load(from: url) else { return [] }
        let builtins = Set(Command.builtins.map(\.name))
        guard config.customCommands.contains(where: { builtins.contains($0.name.lowercased()) }) else { return [] }
        let others = taken ?? PluginStore.load().0.map(\.name) + LiveExtensions.load(config).commands.flatMap(\.names)
        let found = config.freeBuiltinNames(taken: others)
        guard !found.isEmpty else { return [] }
        // Only the names change in the file (`Config.writeRenames`): every other key stays as it was.
        let renamed: [(old: String, new: String)]
        do {
            renamed = try Config.writeRenames(found, at: url)
        } catch {
            log.error("could not rename custom commands for the built-in ones: \(String(describing: error), privacy: .public)")
            return []
        }
        guard !renamed.isEmpty else { return [] }
        NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
        log.notice("custom commands renamed for the built-in ones: \(renamed.count)")
        defaults.set((defaults.stringArray(forKey: key) ?? []) + renamed.map { $0.old + "\t" + $0.new }, forKey: key)
        return renamed
    }

    /// The notice for the names kept to tell, once: they're forgotten as it's taken. Nil: none.
    static func takeNotice(_ messages: Composer.ReplyMessages, defaults: UserDefaults = .standard) -> String? {
        guard let pairs = defaults.stringArray(forKey: key), !pairs.isEmpty else { return nil }
        defaults.removeObject(forKey: key)
        return pairs.map { pair in
            let parts = pair.split(separator: "\t", maxSplits: 1).map(String.init)
            let (old, new) = parts.count == 2 ? (parts[0], parts[1]) : ("reply", pair)
            return messages.renamed(old: old, new: new)
        }.joined(separator: "\n")
    }
}
