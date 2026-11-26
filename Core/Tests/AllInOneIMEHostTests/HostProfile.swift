import Foundation
import AllInOneIMECore

/// The hosts a scenario runs against (the host scenario contract's profiles): what each tells the input method of its
/// field through the text-input API (`HostField`), and what each does on its own (`HostRun`).
///
/// - nstextview: tells the real length, document-wide offsets and the caret; a click outside the marked text has the input
///   method commit it (`commitComposition`).
/// - chromium: `length()` is 0 whatever the text; the selection is real; a substring only within 100 UTF-16 units of the
///   caret, nil past the end; during a key the ranges are the ones from before it (stale until the next turn); every
///   modifier change and every key it doesn't take comes to the input method twice, the copy 12 ms later with the same
///   time; a click commits the marked text itself (`finishComposingText`); losing the focus (or the window losing key)
///   cancels the marked text after the page commits it, so what the input method puts in then is dropped.
/// - electron: chromium's, the copies coming 130 ms late (after the next change).
/// - tellsnothing (a terminal, WeChat): no selection (NSNotFound), length 0, no substring, no marked range, nothing told
///   by Accessibility either (whether it is a password field is unknown).
/// - webkit (Safari, a WKWebView's contenteditable: Mail, Notes' web views): WebKit's `WebViewImpl` (UIProcess/mac)
///   answers the text-input calls asynchronously from the web process (`selectedRangeWithCompletionHandler`,
///   `attributedSubstringForProposedRange:completionHandler:`), with what a key being handled inserted already counted in
///   (the queued `insertText:` commands): the ranges are current during a key, not stale. It implements no
///   `attributedString`, so no length is told (0; not measured on a real Mac: the conservative case, as Chromium's and
///   Qt's). A substring reads the editable element's text, anywhere in it, nil past its end. Keys and modifier changes
///   come once (`keyDown`, `flagsChanged`: an unhandled key is resent through `NSApp sendEvent`, but past the input method,
///   `m_keyDownEventBeingResent`), and a key the input method took is never acted on (`ChromiumApps`: "other fields
///   (AppKit's, WebKit's) never act on a key the input method took"). A mouse down goes to the input context first
///   (`nativeMouseEventHandler`), so a click outside the marked text has the input method commit it, as NSTextView.
///   Losing first responder, the page confirms the composition itself (`confirmCompositionAsync`) and the input context
///   is told it was discarded (`notifyInputContextAboutDiscardedComposition`): what the input method puts in after that
///   is taken as dropped (unverified on a real Mac: the harsher case, as Chromium's).
/// - qt (a Qt Widgets app's QLineEdit / QTextEdit, through `QNSView` and `QCocoaInputContext`): no `attributedString`, so
///   length 0 (`FieldTextReading`: "Chromium (Brave, Slack) and Qt tell length 0", seen on a real Mac 2026-11-14); the
///   selection is real and document-wide (`ImAbsolutePosition`) and current during a key (Qt answers synchronously); a
///   substring only within what `ImTextBeforeCursor` / `ImTextAfterCursor` give, 1024 characters each way by default
///   (`QWidgetTextControl`; QLineEdit gives its whole line), cut to it: Qt 6's `attributedSubstringForProposedRange:
///   actualRange:` answers the part of the range it has (`NSIntersectionRange`, `actualRange` set), nil only where none of
///   it is (`substringClips`; from qnsview_complextext.mm as recalled, not run on a real Mac; Qt 5 differed). Its
///   `firstRectForCharacterRange:` is the cursor's rectangle whatever the range (the Mac's replayer has it), and a
///   replacement range goes where Qt can place it relative to the cursor, else at the cursor. A key the input context
///   consumed is never sent as a QKeyEvent (`QNSView::handleKeyEvent`: `m_sendKeyEvent` false unless the input context
///   didn't consume it), and nothing comes twice. A click commits the marked text itself (`QWidgetTextControl::mousePressEvent` →
///   `commitPreedit` → `QCocoaInputContext::commit` → `[QNSView unmarkText]`). Losing the focus to another widget of the
///   window cancels the marked text (`QCocoaInputContext::setFocusObject`: `cancelComposingText`), and to another window
///   does nothing; neither is modelled (the input method marks nothing since contract v1.3, so only an app's own marked
///   text would differ).
/// - terminal (Terminal, Ghostty, iTerm2): reads as tellsnothing (no selection, no length, no substring, no
///   Accessibility), but its app is a real terminal's bundle id (Ghostty's, in the Mac's `SecureInput.terminals`) and the
///   field is told as a terminal (`FieldInfo.terminal`), so the core's terminal rules apply: ⌘V is the terminal's
///   (`Composer.pastesIntoDraft`), text goes in after the key (`appTakesKeysAfterInsert`, `commitAfterKey`), a command
///   reads nothing of the field (`FieldInfo.textStaysHere`). It sends a key the input method took to the shell as well
///   unless text went in during the key or marked text is in the field after it (`AllInOneIMEInputController
///   .keepFromTerminal`: "A terminal (Ghostty, Terminal, iTerm2) sends a key the input method took itself unless text
///   went in during it or marked text is there after it"); the Mac's shell keeps such a key from it by marking a space
///   during the key when the key composed or the rows took it (`keepFromTerminal`, `KeyGuard`'s tap), and the runner
///   does as the shell does (`HostRun.terminalSends`). No copies of events are known in terminals.
enum HostProfile: String, CaseIterable, Sendable, Comparable {
    case nstextview, chromium, electron, tellsnothing, webkit, qt, terminal

    static func < (a: HostProfile, b: HostProfile) -> Bool {
        allCases.firstIndex(of: a) ?? 0 < allCases.firstIndex(of: b) ?? 0
    }

    /// The field's app, as the session is told it: one of no real app's, so that nothing the core knows of real apps
    /// (terminals, password managers, code editors) applies: the profile alone makes the difference. A terminal's is a
    /// real terminal's, Ghostty's (the Mac's `SecureInput.terminals`), with its field told as a terminal's (`terminal`).
    var app: String { self == .terminal ? "com.mitchellh.ghostty" : "com.example.host.\(rawValue)" }

    /// The field is a terminal's: what the shell tells the session of it (`FieldInfo.terminal`).
    var terminal: Bool { self == .terminal }

    /// The field as the shell tells it (`FieldInfo`).
    var field: FieldInfo { FieldInfo(app: app, terminal: terminal) }

    var chromiumLike: Bool { self == .chromium || self == .electron }

    /// Like WeChat's and a terminal's field: tells nothing of its text.
    var tellsNothing: Bool { self == .tellsnothing || self == .terminal }

    /// `length()` tells the text's length (else 0).
    var tellsLength: Bool { self == .nstextview }
    /// `selectedRange()` and `markedRange()` tell where they are (else NSNotFound).
    var tellsRanges: Bool { !tellsNothing }
    /// How far from the caret `substring` reads (nil: anywhere; 0: nowhere).
    var substringReach: Int? {
        switch self {
        case .nstextview, .webkit: nil
        case .chromium, .electron: 100
        case .qt: 1024
        case .tellsnothing, .terminal: 0
        }
    }

    /// A substring partly beyond its reach (or the text's end) reads the part within it, nil only where none of it is
    /// (Qt's); else a range not wholly within reads nil.
    var substringClips: Bool { self == .qt }

    /// During a key the ranges are the ones from before it (`HostField.beginTurn`).
    var staleRanges: Bool { chromiumLike }
    /// How long after a modifier change or a key it didn't take its copy comes (nil: none comes).
    var copyDelay: TimeInterval? {
        switch self {
        case .chromium: 0.012
        case .electron: 0.130
        case .nstextview, .tellsnothing, .webkit, .qt, .terminal: nil
        }
    }

    /// A click commits the marked text itself, the input method not told (else the input method is asked to,
    /// `commitComposition`, for a click outside it).
    var clickCommitsMarkedText: Bool { chromiumLike || self == .qt }
    /// Losing the focus commits the marked text as shown, then drops what the input method puts in.
    var blurDropsComposition: Bool { chromiumLike || self == .webkit }
    /// A key the input method took goes to the app as well, unless text went in during it or marked text is in the field
    /// after it (a terminal's shell gets it).
    var actsOnTakenKeys: Bool { self == .terminal }
    /// Accessibility tells whether the field is a password field.
    var tellsPasswordField: Bool { !tellsNothing }
}
