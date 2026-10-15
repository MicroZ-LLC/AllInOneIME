import AllInOneIMECore
import AppKit
import ApplicationServices
import InputMethodKit

/// The text selected in the field when an @ command starts on it (`Composer.selection`), and putting it back.
///
/// Read with the text input protocol: the client's `selectedRange()` and the text in it (`attributedSubstring`), which
/// Cocoa (NSTextView), WebKit and most fields answer. Chromium and Electron apps often report no selection there: then
/// the Accessibility API's selected text of the focused element, only if this app may use it already (`AXIsProcessTrusted`;
/// never asked from here). Never during secure input, never a secure text field. Only how it was read and how long it
/// is go to the log, never the text.
enum SelectedText {
    /// The longest selection read, in UTF-16 units: a longer one isn't read (the marked text replaces it, as typing over
    /// a selection does). Up to `Composer.maxSelectionLength` characters a command takes it; longer, it is only put back.
    static let maxRead = 50_000

    enum Source: String { case imk = "IMK", accessibility = "AX" }

    /// The selected text in `client`'s field and how it was read; nil when there is none (or it can't be read).
    /// `accessibility`: whether to ask Accessibility when the field doesn't say (false in the self-test: it would read
    /// the user's own frontmost app).
    @MainActor
    static func read(from client: IMKTextInput?, accessibility: Bool = true) -> (text: String, source: Source)? {
        if let client {
            let range = client.selectedRange()
            // Our own marked text isn't a selection (a draft is never pending here, but a field may still report one).
            let marked = client.markedRange()
            let markedNow = marked.location != NSNotFound && marked.length > 0
            if range.location != NSNotFound, range.length != NSNotFound, range.length > 0, !markedNow {
                guard range.length <= maxRead else {
                    log.notice("selection not read: \(range.length) UTF-16 units, more than \(maxRead)")
                    return nil
                }
                if let text = client.attributedSubstring(from: range)?.string, !text.isEmpty { return (text, .imk) }
            }
        }
        guard accessibility else { return nil }
        return readWithAccessibility().map { ($0, .accessibility) }
    }

    /// The focused element of the frontmost app, if Accessibility may be used (a quarter of a second at most per call).
    private static func focusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement  // checked just above
        AXUIElementSetMessagingTimeout(element, 0.25)
        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
           subrole as? String == kAXSecureTextFieldSubrole as String { return nil }
        return element
    }

    /// The focused element's selected text (`kAXSelectedTextAttribute`), no longer than `maxRead`.
    private static func readWithAccessibility() -> String? {
        guard let element = focusedElement() else { return nil }
        // How long first: a huge selection isn't read at all.
        if let range = selectedRange(of: element), range.length > maxRead {
            log.notice("selection not read (AX): \(range.length) UTF-16 units, more than \(maxRead)")
            return nil
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty, text.utf16.count <= maxRead else { return nil }
        return text
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil  // checked just above
    }

    /// Selects `text` again where it was put back (at UTF-16 `location`), with the Accessibility API: only if this app
    /// may use it, and the focused field holds exactly `text` there. Whether it did.
    @MainActor
    static func reselect(_ text: String, at location: Int) -> Bool {
        guard let element = focusedElement() else { return false }
        var range = CFRange(location: location, length: (text as NSString).length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                         parameter, &value) == .success,
              value as? String == text else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, parameter) == .success
    }
}
