import AllInOneIMECore
import AppKit
import SwiftUI

extension SelfTest {
    /// Settings → AI's own checks: each key's row says whether it is set; the other AIs show only while choosing (#174).
    static func testAIPage(snapshotDirectory: URL) {
        testKeyStatus(snapshotDirectory: snapshotDirectory)
        testAIPageChoosing(snapshotDirectory: snapshotDirectory)
    }

    /// Settings → AI (#174, 0.7.4's design): collapsed as the page shows, the AI in use with Change ▾ and no other AI's
    /// card; Change ▾ shows every card with Cancel, which collapses it again; the settings search's "kiro" lands with the
    /// choices open, Kiro CLI's card scrolled to, and the start pointing at the AI in use leaves the page collapsed. The
    /// page is drawn in a window of its own, on a config of its own, and its buttons found the way VoiceOver finds them.
    static func testAIPageChoosing(snapshotDirectory: URL) {
        let groups = AIChoice.groups(hosted: true, apple: .available, keeping: .provider(.openai))
        var picker = AIPickerState(chosen: .provider(.openai), groups: groups)
        let all = groups.flatMap(\.choices).count
        let collapsed = !picker.choosing && picker.visibleGroups.isEmpty
        picker.change()
        let open = picker.visibleGroups.flatMap(\.choices).count == all
        picker.cancel()
        let cancelled = !picker.choosing && picker.chosen == .provider(.openai)
        picker.change()
        picker.pick(.cli(.kiro))
        check(collapsed && open && cancelled && picker.chosen == .cli(.kiro) && !picker.choosing,
              "Settings → AI starts collapsed, Change shows all \(all) cards, Cancel changes nothing, a card picked collapses it")

        let url = snapshotDirectory.appendingPathComponent("ai-choosing-config.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let looksUp = SettingsModel.looksUpKeys
        SettingsModel.looksUpKeys = false
        defer { SettingsModel.looksUpKeys = looksUp }
        let model = SettingsModel(configURL: url)
        // As the window is pointed: by the search (what was typed), by the start or the Doctor (a card).
        let kiro = SettingsSpot.search("kiro", trigger: "@", config: .default).first
        model.point(at: .provider, search: "kiro")
        let searched = model.aiCards.choosing && model.spotIDs.last == AnyHashable(AIChoice.cli(.kiro))
        check(kiro == .provider && searched,
              "searching for \"kiro\" lands on the AI page with the choices open, Kiro CLI's card scrolled to (\(String(describing: kiro)))")
        model.point(at: .provider, card: model.config.ai)
        check(!model.aiCards.choosing && model.spotIDs == [AnyHashable(SettingsSpot.provider)],
              "pointed at the AI in use, the page stays collapsed (\(model.spotIDs))")
        model.point(at: nil)

        // The page as drawn, as VoiceOver sees it (`AXEnhancedUserInterface`, as Settings' other checks set it): Change the
        // AI, and no card of another AI; pressed, Kiro CLI's card and Cancel show; Cancel pressed, they're gone.
        func enhanced(_ on: Bool) {
            _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: on as NSNumber, with: "AXEnhancedUserInterface")
        }
        func ax(_ node: NSObject, _ key: String) -> Any? { node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil }
        func nodes(_ node: NSObject) -> [NSObject] { [node] + ((ax(node, "accessibilityChildren") as? [NSObject]) ?? []).flatMap(nodes) }
        /// The element `prefix` names: a button first.
        func named(_ prefix: String, in window: NSWindow) -> NSObject? {
            let found = nodes(window).filter { node in
                [ax(node, "accessibilityLabel"), ax(node, "accessibilityTitle")].contains { ($0 as? String)?.hasPrefix(prefix) == true }
            }
            return found.first { ax($0, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue } ?? found.first
        }
        enhanced(true)
        defer { enhanced(false) }
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, page: .ai)))
        window.setContentSize(NSSize(width: 880, height: 900))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let change = tr("更换 AI", "Change the AI")
        let cancel = tr("取消", "Cancel")
        let card = AIChoice.cli(.kiro).name
        _ = pump(timeout: 2) { named(change, in: window) != nil }
        let row = named(change, in: window)
        let hidden = named(card, in: window) == nil
        _ = row?.perform(NSSelectorFromString("accessibilityPerformPress"))
        _ = pump(timeout: 1) { named(card, in: window) != nil }
        let shown = named(card, in: window) != nil && model.aiCards.choosing
        _ = named(cancel, in: window)?.perform(NSSelectorFromString("accessibilityPerformPress"))
        _ = pump(timeout: 1) { named(card, in: window) == nil }
        check(row != nil && hidden && shown && named(card, in: window) == nil && !model.aiCards.choosing,
              "Settings → AI shows the AI in use with Change ▾ and no other AI's card; pressed, the cards show (\(card)'s: \(shown)); "
                  + "Cancel collapses it (row: \(row != nil), collapsed at first: \(hidden))")
    }
}
