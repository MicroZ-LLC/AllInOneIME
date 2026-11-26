import AllInOneIMECore
import AppKit
import SwiftUI

extension SelfTest {
    /// Settings → AI's own checks: each key's row says whether it is set; the other AIs fold under one row (#161).
    static func testAIPage(snapshotDirectory: URL) {
        testKeyStatus(snapshotDirectory: snapshotDirectory)
        testAIPageFolds(snapshotDirectory: snapshotDirectory)
    }

    /// Settings → AI (#161): the other AIs folded under one row as the page shows; the row unfolds them, a card picked
    /// folds them again; the settings search's "kiro" lands with them unfolded, Kiro CLI's card scrolled to, and the start
    /// pointing at the AI in use leaves them folded. The page is drawn in a window of its own, on a config of its own, and
    /// its row found the way VoiceOver finds it.
    static func testAIPageFolds(snapshotDirectory: URL) {
        let groups = AIChoice.groups(hosted: true, apple: .available, keeping: .provider(.openai))
        var picker = AIPickerState(chosen: .provider(.openai), groups: groups)
        let others = groups.flatMap(\.choices).count - 1
        let folded = !picker.isExpanded && picker.otherGroups.isEmpty
        picker.toggle()
        let unfolded = picker.otherGroups.flatMap(\.choices).count == others
        picker.pick(.cli(.kiro))
        check(folded && unfolded && picker.chosen == .cli(.kiro) && !picker.isExpanded,
              "Settings → AI: the other AIs start folded, the row unfolds all \(others), a card picked folds them again")

        let url = snapshotDirectory.appendingPathComponent("ai-fold-config.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let looksUp = SettingsModel.looksUpKeys
        SettingsModel.looksUpKeys = false
        defer { SettingsModel.looksUpKeys = looksUp }
        let model = SettingsModel(configURL: url)
        // As the window is pointed: by the search (what was typed), by the start or the Doctor (a card).
        let kiro = SettingsSpot.search("kiro", trigger: "@", config: .default).first
        model.point(at: .provider, search: "kiro")
        let searched = model.aiCards.isExpanded && model.spotIDs.last == AnyHashable(AIChoice.cli(.kiro))
        check(kiro == .provider && searched,
              "searching for \"kiro\" lands on the AI page's cards unfolded, Kiro CLI's scrolled to (\(String(describing: kiro)))")
        model.point(at: .provider, card: model.config.ai)
        check(!model.aiCards.isExpanded && model.spotIDs == [AnyHashable(SettingsSpot.provider)],
              "pointed at the AI in use, the other cards stay folded under it (\(model.spotIDs))")
        model.point(at: nil)

        // The page as drawn, as VoiceOver sees it (`AXEnhancedUserInterface`, as Settings' other checks set it): one row
        // "Other AIs (N)", folded; pressed, Kiro CLI's card shows under it; pressed again, it's gone.
        func enhanced(_ on: Bool) {
            _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: on as NSNumber, with: "AXEnhancedUserInterface")
        }
        func ax(_ node: NSObject, _ key: String) -> Any? { node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil }
        func nodes(_ node: NSObject) -> [NSObject] { [node] + ((ax(node, "accessibilityChildren") as? [NSObject]) ?? []).flatMap(nodes) }
        /// The element `prefix` names: what can be pressed (a button, a disclosure) first.
        func named(_ prefix: String, in window: NSWindow) -> NSObject? {
            let found = nodes(window).filter { node in
                [ax(node, "accessibilityLabel"), ax(node, "accessibilityTitle")].contains { ($0 as? String)?.hasPrefix(prefix) == true }
            }
            let pressed = [NSAccessibility.Role.button, .disclosureTriangle].map(\.rawValue)
            return found.first { pressed.contains(ax($0, "accessibilityRole") as? String ?? "") } ?? found.first
        }
        enhanced(true)
        defer { enhanced(false) }
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, page: .ai)))
        window.setContentSize(NSSize(width: 880, height: 900))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let title = model.aiCards.rowTitle
        let card = AIChoice.cli(.kiro).name
        _ = pump(timeout: 2) { named(title, in: window) != nil }
        let row = named(title, in: window)
        let hidden = named(card, in: window) == nil
        _ = row?.perform(NSSelectorFromString("accessibilityPerformPress"))
        _ = pump(timeout: 1) { named(card, in: window) != nil }
        let shown = named(card, in: window) != nil && model.aiCards.isExpanded
        _ = named(title, in: window)?.perform(NSSelectorFromString("accessibilityPerformPress"))
        _ = pump(timeout: 1) { named(card, in: window) == nil }
        check(row != nil && hidden && shown && named(card, in: window) == nil && !model.aiCards.isExpanded,
              "Settings → AI shows the other AIs as one row, \"\(title)\", folded; pressed, their cards show (\(card)'s: \(shown)); "
                  + "pressed again, they fold (row: \(row != nil), folded at first: \(hidden))")
    }
}
