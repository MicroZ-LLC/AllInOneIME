import Foundation

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
enum HostProfile: String, CaseIterable, Sendable, Comparable {
    case nstextview, chromium, electron, tellsnothing

    static func < (a: HostProfile, b: HostProfile) -> Bool {
        allCases.firstIndex(of: a) ?? 0 < allCases.firstIndex(of: b) ?? 0
    }

    /// The field's app, as the session is told it: one of no real app's, so that nothing the core knows of real apps
    /// (terminals, password managers, code editors) applies: the profile alone makes the difference.
    var app: String { "com.example.host.\(rawValue)" }

    var chromiumLike: Bool { self == .chromium || self == .electron }

    /// `length()` tells the text's length (else 0).
    var tellsLength: Bool { self == .nstextview }
    /// `selectedRange()` and `markedRange()` tell where they are (else NSNotFound).
    var tellsRanges: Bool { self != .tellsnothing }
    /// How far from the caret `substring` reads (nil: anywhere; 0: nowhere).
    var substringReach: Int? {
        switch self {
        case .nstextview: nil
        case .chromium, .electron: 100
        case .tellsnothing: 0
        }
    }

    /// During a key the ranges are the ones from before it (`HostField.beginTurn`).
    var staleRanges: Bool { chromiumLike }
    /// How long after a modifier change or a key it didn't take its copy comes (nil: none comes).
    var copyDelay: TimeInterval? {
        switch self {
        case .chromium: 0.012
        case .electron: 0.130
        case .nstextview, .tellsnothing: nil
        }
    }

    /// A click commits the marked text itself, the input method not told (else the input method is asked to,
    /// `commitComposition`, for a click outside it).
    var clickCommitsMarkedText: Bool { chromiumLike }
    /// Losing the focus commits the marked text as shown, then drops what the input method puts in.
    var blurDropsComposition: Bool { chromiumLike }
    /// Accessibility tells whether the field is a password field.
    var tellsPasswordField: Bool { self != .tellsnothing }
}
