import AllInOneIMECore
import AppKit
import InputMethodKit

/// `@reply` and screenshots in a draft, the Mac's side (the logic is the core's: `Composer+Reply.swift`, `ScreenText`,
/// `Reply.swift`): the clipboard as ⌃V finds it, the screenshot read with Vision on this Mac, the text around the caret
/// through IMK, Vision warmed up when a draft starts with an image on the clipboard, and the custom commands a built-in
/// took the name of, renamed once.
extension AllInOneIMEInputController {
    /// The clipboard as a draft takes it (`ClipboardContent`): its text first, else a PNG or TIFF image; nothing for what
    /// password managers mark as concealed or transient (nspasteboard.org, and the older markers), and when pasting from
    /// other apps is denied to this one. (Nothing is read during secure input: `Effect.readClipboard`.)
    static func clipboardContent(_ pasteboard: NSPasteboard) -> ClipboardContent {
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny { return .none }
        let types = pasteboard.types ?? []
        let hidden = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword",
                      "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping", "Pasteboard generator type",
                      "net.antelle.keeweb"].map { NSPasteboard.PasteboardType(rawValue: $0) }
        guard hidden.allSatisfy({ !types.contains($0) }) else { return .none }
        if types.contains(.string), let text = pasteboard.string(forType: .string) { return .text(text) }
        for type in [NSPasteboard.PasteboardType.png, .tiff] where types.contains(type) {
            // Larger than a draft takes: the composer says so (`Composer.maxImageBytes`).
            if let image = pasteboard.data(forType: type) { return .image(image) }
        }
        return .none
    }

    /// What the log says of the clipboard read: only how much, never the text or the image.
    static func logged(_ content: ClipboardContent) -> String {
        switch content {
        case let .text(text): return "\(text.count) chars"
        case let .image(image): return "an image of \(image.count / 1024) KB"
        case .none: return "nothing usable"
        }
    }

    /// The screenshot pasted into the draft, read on this Mac (`Platform.current.text`: Vision) in the settings'
    /// languages (`ScreenText.languages`), for at most `ScreenText.timeout`; the text, or why not, goes to the composer.
    /// The image goes nowhere and isn't kept; the log has only how many lines were read.
    @MainActor
    func recognizeScreenshot(_ image: Data, id: Int) {
        let languages = ScreenText.languages(loadSettings())
        let recognizer = recognizeText
        let started = Date()
        Task { @MainActor [weak self] in
            do {
                let text = try await ScreenText.recognize(image, with: recognizer, languages: languages)
                log.notice("screenshot \(id): \(text.lineCount) lines read in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
                guard let self else { return }
                self.perform(self.composer.recognized(text, id: id), client: nil)
            } catch {
                log.notice("screenshot \(id): not read (\(String(describing: type(of: error)), privacy: .public))")
                guard let self else { return }
                let message = (error as? ScreenText.Problem).map(self.composer.messages.reply.describe) ?? UIText.describe(error)
                self.perform(self.composer.recognitionFailed(message, id: id), client: nil)
            }
        }
    }

    /// Vision loaded ahead of time when a draft starts with an image on the clipboard (only the clipboard's types are
    /// looked at), once per clipboard: the screenshot pasted next is read quickly.
    @MainActor
    func warmUpScreenshotReading() {
        guard warmsUpVision, composer.draft == "@", !secureInputActive() else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != Self.warmedFor else { return }
        Self.warmedFor = pasteboard.changeCount
        let types = pasteboard.types ?? []
        guard types.contains(.png) || types.contains(.tiff) else { return }
        let recognizer = recognizeText
        Task.detached(priority: .utility) { await recognizer.prepare() }
    }

    /// The clipboard Vision was last warmed up for (`warmUpScreenshotReading`).
    nonisolated(unsafe) static var warmedFor = -1

    /// The text around the caret (`Composer.readFieldText`), without the draft: up to 1,500 characters before it and after
    /// it as the field tells them (IMK), past the selection or the marked text. None during secure input, nor in a
    /// terminal (its text isn't being edited).
    @MainActor
    func readFieldText(from target: IMKTextInput?) -> FieldText? {
        guard !secureInputActive(), let target, !Self.isTerminal(target) else { return nil }
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
        let span = ReplyContext.Limits.fieldBefore * 2
        let start = min(around.location, length)
        let end = min(NSMaxRange(around), length)
        let beforeRange = NSRange(location: max(0, start - span), length: start - max(0, start - span))
        let afterRange = NSRange(location: end, length: min(span, length - end))
        let before = beforeRange.length > 0 ? target.attributedSubstring(from: beforeRange)?.string ?? "" : ""
        let after = afterRange.length > 0 ? target.attributedSubstring(from: afterRange)?.string ?? "" : ""
        guard !before.isEmpty || !after.isEmpty else { return nil }
        log.notice("field text read for @reply (\(before.count) + \(after.count) characters)")
        return FieldText(before: before, after: after)
    }

    /// The notice of the custom commands renamed for the built-in ones (`BuiltinRenames`), once.
    @MainActor
    func tellBuiltinRenames(client: IMKTextInput?) {
        guard let notice = takeRenameNotice(composer.messages.reply) else { return }
        showNotice(notice, client: client, long: true)
    }
}

/// The custom commands a built-in took the name of (`Config.freeBuiltinNames`): renamed once when the input method starts,
/// the config written, and the next text field says so once (`AllInOneIMEInputController.tellBuiltinRenames`).
enum BuiltinRenames {
    static let key = "builtinRenamesToTell"

    /// Renames them in the config at `url` (if any are to be), writes it, and keeps their new names to tell. The new
    /// names are free of the plugins' and script extensions' too (`taken`; nil: the installed ones, looked for only when
    /// a custom command has a built-in's name).
    @discardableResult
    static func apply(configURL url: URL = Config.defaultURL, defaults: UserDefaults = .standard,
                      taken: [String]? = nil) -> [(old: String, new: String)] {
        guard var config = try? Config.load(from: url) else { return [] }
        let builtins = Set(Command.builtins.map(\.name))
        guard config.customCommands.contains(where: { builtins.contains($0.name.lowercased()) }) else { return [] }
        let others = taken ?? PluginStore.load().0.map(\.name) + LiveExtensions.load(config).commands.flatMap(\.names)
        let renamed = config.freeBuiltinNames(taken: others)
        guard !renamed.isEmpty else { return [] }
        do {
            try config.write(to: url)
        } catch {
            log.error("could not rename custom commands for the built-in ones: \(String(describing: error), privacy: .public)")
            return []
        }
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
