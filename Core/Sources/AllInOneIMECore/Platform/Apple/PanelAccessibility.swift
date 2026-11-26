#if canImport(AppKit)
import AppKit

/// The candidate panel for VoiceOver (the input method's `CandidateView`, which draws every row itself): a list, named,
/// with an element for each row shown ("1 你好", the highlighted one selected), the status and the footer; and what
/// changes said aloud: the highlighted row as ↑↓ move it or results stream in, once a burst of changes settles
/// (`delay`), not at each.
@MainActor
public final class PanelAccessibility {
    /// How long the model stays as it is before what changed is said.
    public static let delay: TimeInterval = 0.2

    private weak var view: NSView?
    private var elements: [NSAccessibilityElement]?
    /// Where the elements were made for (the rows' frames, the status's, the footer's, the view's bounds): laid out again
    /// (scrolled, wider, on the other side of the caret), they are made again.
    private var madeFor: [NSRect] = []
    private var pending: DispatchWorkItem?

    public init(view: NSView) {
        self.view = view
    }

    /// The list's name.
    public static var listLabel: String { tr("候选", "Candidates") }

    /// A row as said: its number (a key), its text and its comment.
    public static func label(_ row: PanelModel.Row) -> String {
        [row.label, row.text, row.comment].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The model changed: the elements are made again when next asked for, and what it shows now said once the changes
    /// settle (`say`), where the highlighted row (or the status) is another than before.
    public func changed(from old: PanelModel, to model: PanelModel, say: @escaping (String) -> Void) {
        elements = nil
        guard Self.spoken(model) != Self.spoken(old) || model.highlighted != old.highlighted else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            if let text = Self.spoken(model), !text.isEmpty { say(text) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: work)
    }

    /// The panel hid: nothing it showed is said.
    public func cancel() {
        pending?.cancel()
        pending = nil
    }

    /// What is said of `model`: its highlighted row, else its status.
    static func spoken(_ model: PanelModel) -> String? {
        if let index = model.highlighted, model.rows.indices.contains(index) { return label(model.rows[index]) }
        return model.statusText ?? model.rows.first.map(label)
    }

    /// The panel's children: a row element per row shown (`rowFrame`: its place in the view, nil where it isn't laid out),
    /// then the status and the footer as text.
    public func children(_ model: PanelModel, rowFrame: (Int) -> NSRect?, statusFrame: NSRect?, footerFrame: NSRect?) -> [Any] {
        guard let view else { return [] }
        let rows = model.rows.indices.compactMap { index in rowFrame(index).map { (index, $0) } }
        let key = rows.map(\.1) + [statusFrame ?? .zero, footerFrame ?? .zero, view.bounds]
        if let elements, key == madeFor { return elements }
        var made: [NSAccessibilityElement] = []
        for (index, frame) in rows {
            made.append(element(.row, Self.label(model.rows[index]), frame: frame, in: view, selected: index == model.highlighted))
        }
        if let status = model.statusText { made.append(element(.staticText, status, frame: statusFrame ?? .zero, in: view)) }
        if !model.footer.isEmpty { made.append(element(.staticText, model.footer, frame: footerFrame ?? .zero, in: view)) }
        (elements, madeFor) = (made, key)
        return made
    }

    private func element(_ role: NSAccessibility.Role, _ label: String, frame: NSRect, in view: NSView,
                         selected: Bool = false) -> NSAccessibilityElement {
        let element = NSAccessibilityElement()
        element.setAccessibilityRole(role)
        element.setAccessibilityLabel(label)
        element.setAccessibilityParent(view)
        element.setAccessibilitySelected(selected)
        // Its parent's coordinates, from the bottom left as the accessibility frames are.
        let y = view.isFlipped ? view.bounds.height - frame.maxY : frame.minY
        element.setAccessibilityFrameInParentSpace(NSRect(x: frame.minX, y: y, width: frame.width, height: frame.height))
        return element
    }

    /// Says `text` with VoiceOver, where it is on.
    public static func announce(_ text: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
#endif
