import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import ApplicationServices
import InputMethodKit

/// The text selected in the field when an @ command starts on it (`Composer.selection`), and where it is.
///
/// Read with the text input protocol (`FieldReading.selection`, the Mac library's): the client's `selectedRange()` and the
/// text in it (`attributedSubstring`), which Cocoa (NSTextView), WebKit and most fields answer. Chromium and Electron apps
/// often report no selection there: then the Accessibility API's selected text of the focused element, after the key,
/// only if this app may use it already (`AXIsProcessTrusted`; never asked from here). Never during secure input, never a
/// secure text field. Only how it was read and how long it is go to the log, never the text.
enum SelectedText {
    /// The longest selection read, in UTF-16 units (`FieldReading.maxSelection`): a longer one isn't read.
    static let maxRead = FieldReading.maxSelection

    /// Whether a selection the text input protocol didn't tell may be there all the same, for Accessibility to read
    /// (`readWithAccessibility`, after the key: `FieldContext.selectionFollows`): this app may use Accessibility, and the
    /// field told no range, or is a Chromium or Electron app's (`chromium`), which often reports none with one. A field
    /// that told its caret is believed: nothing is selected there.
    @MainActor
    static func mayBeUntold(in client: IMKTextInput?, chromium: Bool) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let client, !chromium else { return true }
        let range = client.selectedRange()
        return range.location == NSNotFound || range.length == NSNotFound
    }

    /// The focused element of the frontmost app, if Accessibility may be used (`FocusedField.element`: a quarter of a
    /// second at most per call), unless it is a password field.
    private static func focusedElement() -> AXUIElement? {
        guard let element = FocusedField.element() else { return nil }
        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
           subrole as? String == kAXSecureTextFieldSubrole as String { return nil }
        return element
    }

    /// The focused element's selected text (`kAXSelectedTextAttribute`), no longer than `maxRead`. Any thread: after the
    /// "@" key it's read off the main one (up to four calls of a quarter of a second each).
    static func readWithAccessibility() -> String? {
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
}
