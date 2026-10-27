import Foundation

// Clipboard history (0.6.8, owner 2026-10-26): ⌃V shows the text copied lately in the rows panel the suggestions use and
// puts in the one chosen. The core owns the behaviour (the keys, the rows, the selection, what goes in and in what order,
// a command's text taking it); the shell owns recording, the history's file, the permission and the Settings section,
// and hands the session what it keeps through `ClipboardHistoryServices` (`SessionServices.clipboardHistory`). The
// session's side is InputSession+ClipboardHistory.swift.
//
// THE SEAM, everything a test observes, as today through `InputSession` (keys in, outputs out; FakeHost in
// AllInOneIMETestSupport drives it):
//
// - Types: `ClipboardHistoryItem` (the text, when it was copied), `ClipboardHistoryState` (`.unavailable`, `.recording`,
//   `.notAllowed`), `ClipboardHistoryServices` (below). `Config.clipboardHistory` (Bool?, nil: on) and
//   `Config.clipboardHistoryLimit` (Int?, nil: 20; `Config.clipboardHistoryKept` clamps it to 5…100) are the settings,
//   this device's own (`ICloudSync.neverSynced`).
// - The trigger is the paste-anywhere key: `ModifierRoles.pasteAnywhere` with V, ⌃V on the Mac (`FakeHost.controlV`);
//   none on Windows, where nothing here applies. The panel opens on it when the history is on (`clipboardHistory` not
//   false), the shell keeps one (`state` not `.unavailable`), there's no secure input, and either nothing is composed (Code's
//   word held as marked text goes in as typed first; suggestion rows showing go: a paste ends the token) or a command's
//   text takes ⌃V (`Composer.takesPasteAnywhere`: a draft, not level two, no voice, no "@" alone). In a command with
//   `state` `.notAllowed`, and anywhere with the history off or `.unavailable`, ⌃V is as before 0.6.8 (the composer's);
//   so it is in a field where the shell couldn't keep the panel's keys from the app (`InputSession.clipboardPanelAllowed`
//   false, told before ⌃V: the Mac's Chromium and Electron pages where nothing can be marked).
// - ⌃V is taken (handled) and the clipboard read: `SessionOutput.readClipboard(id:)` with an id below 0, answered with
//   `SessionEvent.clipboard(content, id:)` (FakeHost answers it with its `clipboard` once the key is done, as the Mac
//   does). Outside a command ⌃V also says `rowsTookKey` (a Chromium page keeps none of it). Then the panel
//   (`SessionOutput.panel`, `InputSession.panelModel()`), its rows newest first: an image on the clipboard first
//   ("Image on the clipboard"), else the clipboard's text first unless the history's newest is that text; then the
//   history (`items`, newest first, at most `clipboardHistoryKept`), each text once; with `state` `.notAllowed`, last,
//   a row saying how to keep a history (`openPermission` on ⏎). The first row is chosen (`PanelModel.highlighted`). The
//   clipboard's text counts only when it isn't blank and has no more than `ClipboardHistoryItem.maxLength` characters.
//   Nothing to show (no text, no image, an empty history): no panel, the composer's `Messages.nothingToPaste` notice.
//   Secure input on by the time it's read, a key before it's read, or a command sent meanwhile: no panel.
// - A row: `text` the text's first line that isn't blank, trimmed (80 characters at most, "…" after), `comment` "+N lines"
//   ("+1 line") or its length ("N chars"), then " · " and how long ago it was copied (`RelativeTime`, `.short`, by `now`),
//   or "on the clipboard" for the clipboard's text the history doesn't have ("5 chars · 5 min ago", "+2 lines · 2 hr
//   ago", "5 chars · on the clipboard"); `label` "✓" on the rows selected with ⇧↓ ⇧↑ (else ""); no numbers; `choice` its
//   index among all the rows. The image row: "Image on the clipboard", its comment "" where ⏎ can give ⌃V to the app (in
//   a command, or `canPassPasteKey`, asked as the panel opens) and "⌃V again pastes it" where it can't. The permission
//   row: "To keep a history, allow Paste from Other Apps", "⏎ opens Privacy & Security", `pickable` false. 5 rows show
//   at a time (`InputSession.shownSuggestionRows`), scrolled to keep the chosen one in view; `detail` "Clipboard", with
//   several selected " · 3 selected" after it, with more rows than shown " · 1–5 / 20" last; a notice takes its place
//   while up, as on suggestions' rows. `footer` the keys ("⏎ inserts · ↑↓ to pick · ⇧↓ selects more · → or Esc hides";
//   with several selected "⏎ inserts them, one per line · ⇧↑⇧↓ select · → or Esc hides"); the first time the panel
//   shows on the device (`firstShowing`), "Kept on this Mac only; turn it off in Settings → General → Clipboard history"
//   instead, for that showing. (English texts: the interface language "en".)
// - Keys while it shows (no other modifier; Caps Lock and the sides don't count): ↓ ↑ move the choice around the ends and
//   end a selection; ⇧↓ ⇧↑ extend the selection from the row chosen when it started (stopping at the ends); ⏎, keypad
//   Enter or Tab put in the selection (or the chosen row); → or Esc hide the panel (the composer's panel back in a
//   command); ⌃V again hides it and gives ⌃V as it is: outside a command the key isn't handled (the app's), in one the
//   composer has it (today's ⌃V). Each key the panel takes that puts nothing in says `rowsTookKey` first; one that puts
//   text in, `rowByKey`. Any other key hides the panel and goes on as it would (digits are typed, never pick). The wheel
//   (`SessionEvent.scroll`) moves the choice, stopping at the ends; a click (`SessionEvent.pick(index among those shown)`)
//   puts that row in, alone.
// - What goes in: the rows selected that are text, in the order they were copied (oldest first: the reverse of the
//   rows'), each without the line breaks at its end, joined with "\n"; one row: its text as it was copied. Outside a
//   command a `commit` (the shell's rows' insertion path: in a terminal with line breaks a paste where it can paste,
//   `SessionServices.pastesInTerminal`, else the lines made one, `Composer.oneLine`); the clipboard itself unchanged. In a
//   command the composer takes it as ⌃V takes the clipboard (`Composer.pasteAnywhere(_:)`: lines made one, 2,000
//   characters; `@note` keeps its lines, 20,000; `@reply` takes it as the message). The image row: outside a command,
//   with `canPassPasteKey`, `PlatformAction.passPasteKey` (the shell posts ⌃V marked as its own), else only hides; in a
//   command, today's ⌃V (`readClipboard` with the composer's id, the image read as `@reply` reads it). The permission row:
//   `openPermission`, nothing put in. Leaving the field (`blur`, `close`, a click in it: `commit`) hides the panel.
// - FakeHost (AllInOneIMETestSupport) keeps a history as the Mac does once `keepClipboardHistory()` is called:
//   `clipboardHistory` (items, newest first), `clipboardHistoryState` (`.recording` by default), `passesPasteKey` (true),
//   `firstClipboardPanel` (said once), `clipboardNow`; it counts `permissionOpened` and `pasteKeysPassed`, and its
//   `clipboard` answers the reads. Keys: `controlV`, `down`, `up`, `right`, `shiftDown`, `shiftUp`, `enter`, `tab`,
//   `escape`. Without `keepClipboardHistory()` its sessions have none (`.unavailable`): ⌃V as before.

/// A text copied, as the shell kept it.
public struct ClipboardHistoryItem: Equatable, Hashable, Sendable {
    /// The most text one copy may have to be kept, in characters: a longer one isn't recorded.
    public static let maxLength = 100_000

    public var text: String
    public var copiedAt: Date

    public init(text: String, copiedAt: Date) {
        self.text = text
        self.copiedAt = copiedAt
    }
}

/// Whether the shell keeps a history.
public enum ClipboardHistoryState: Equatable, Sendable {
    /// None on this platform (a shell that keeps none yet: Windows'): ⌃V as before.
    case unavailable
    /// It records what is copied.
    case recording
    /// It may not read the clipboard without asking (the Mac: Privacy & Security → Paste from Other Apps not set to
    /// Allow), so it records nothing: ⌃V shows what's on the clipboard now, and how to keep a history.
    case notAllowed
}

/// What a session asks of the shell for clipboard history (`SessionServices.clipboardHistory`). The defaults keep none.
public struct ClipboardHistoryServices {
    /// Whether it keeps a history now.
    public var state: () -> ClipboardHistoryState
    /// The texts kept, newest first (the session shows `Config.clipboardHistoryKept` of them at most).
    public var items: () -> [ClipboardHistoryItem]
    /// Whether the paste key can be given to the app as it is (`PlatformAction.passPasteKey`; the Mac: Accessibility),
    /// asked without asking the user.
    public var canPassPasteKey: () -> Bool
    /// True the first time the panel shows on this device, then false (the shell keeps that it was said).
    public var firstShowing: () -> Bool
    /// Opens where the user lets the shell keep a history (the Mac: System Settings → Privacy & Security → Paste from
    /// Other Apps).
    public var openPermission: () -> Void
    /// The time now, how long ago each was copied goes by.
    public var now: () -> Date

    public init(state: @escaping () -> ClipboardHistoryState = { .unavailable }, items: @escaping () -> [ClipboardHistoryItem] = { [] },
                canPassPasteKey: @escaping () -> Bool = { false }, firstShowing: @escaping () -> Bool = { false },
                openPermission: @escaping () -> Void = {}, now: @escaping () -> Date = { Platform.current.clock.now }) {
        self.state = state
        self.items = items
        self.canPassPasteKey = canPassPasteKey
        self.firstShowing = firstShowing
        self.openPermission = openPermission
        self.now = now
    }
}

extension Config {
    /// How many texts the history keeps by default, and the range Settings offers.
    public static let defaultClipboardHistoryLimit = 20
    public static let clipboardHistoryLimits = 5...100

    /// Whether clipboard history is on (`clipboardHistory`; nil: on).
    public var clipboardHistoryOn: Bool { clipboardHistory != false }

    /// How many texts it keeps: `clipboardHistoryLimit` within 5…100, 20 unless set.
    public var clipboardHistoryKept: Int {
        let limits = Self.clipboardHistoryLimits
        return min(max(clipboardHistoryLimit ?? Self.defaultClipboardHistoryLimit, limits.lowerBound), limits.upperBound)
    }
}
