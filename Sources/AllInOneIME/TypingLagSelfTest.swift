import AllInOneIMECore
import AppKit

extension SelfTest {
    /// Issue #23: window reuse and idle cleanup, cached menu reads (including a broken config), and rapid
    /// commits through the controller with real Rime. No AI requests, posted keys or changes to the user's config.
    static func testTypingLag(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        section("typing lag: candidate window lifecycle")
        let panel = CandidatePanel()
        defer { panel.orderOut(nil) }
        let model = PanelModel(rows: [PanelModel.Row(label: "1", text: "你好", kind: .candidate)], highlighted: 0)
        let anchor = client.caretRect
        check(panel.animationBehavior == .none, "candidate, notice and translation chip window has no system animation")
        panel.show(model, anchor: anchor)
        check(panel.isShowing && panel.alphaValue == 1 && !panel.ignoresMouseEvents, "candidates are visible and accept clicks")
        let frame = panel.frame
        panel.show(model, anchor: anchor)
        check(panel.frame == frame && panel.shows(model, anchor: anchor), "the same model at the same caret keeps its frame")
        panel.hide()
        check(!panel.isShowing && panel.isVisible && panel.alphaValue == 0 && panel.ignoresMouseEvents,
              "commit hides candidates immediately without ordering out or intercepting clicks")
        check(!panel.shows(model, anchor: anchor), "a hidden window is not mistaken for an already shown chip")
        panel.hide()  // a second hide must not replace the saved opacity or postpone idle cleanup
        panel.show(model, anchor: anchor)
        check(panel.isShowing && panel.alphaValue == 1 && !panel.ignoresMouseEvents, "the next word restores the reused window")
        _ = pump(timeout: 0.6) { false }
        check(panel.isShowing, "a cancelled idle hide cannot close the next word's candidates")
        panel.hide()
        check(pump(timeout: 1) { !panel.isVisible }, "the window is ordered out after typing stops")
        panel.show(.notice("English"), anchor: anchor)
        check(panel.isShowing && panel.alphaValue == 1 && !panel.ignoresMouseEvents, "a notice can reopen after idle cleanup")
        panel.hide()
        panel.show(model, anchor: anchor.offsetBy(dx: 40, dy: 0))
        check(panel.isShowing && panel.frame != frame, "another field can reuse the window at its own caret")
        var durations: [Double] = []
        for _ in 0..<200 {
            let start = Date()
            panel.hide()
            panel.show(model, anchor: anchor)
            durations.append(Date().timeIntervalSince(start) * 1000)
        }
        let sorted = durations.sorted()
        print(String(format: "  200 hide/show cycles: median %.2f ms, p95 %.2f ms, max %.2f ms",
                     sorted[100], sorted[190], sorted[199]))
        check(panel.isShowing && panel.alphaValue == 1 && !panel.ignoresMouseEvents, "rapid hide/show cycles leave the final candidates usable")
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.hide()
        panel.show(model, anchor: anchor)
        check(panel.isShowing && panel.alphaValue == 0 && panel.ignoresMouseEvents,
              "offscreen self-tests keep their panel invisible and click-through across reuse")

        section("typing lag: cached input menu")
        let savedURL = Config.selfTestURL
        let language = UIText.choice
        let directory = Config.defaultURL.deletingLastPathComponent().appendingPathComponent("typing-lag-config")
        defer {
            Config.selfTestURL = savedURL
            UIText.choice = language
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let first = directory.appendingPathComponent("first.json")
            let second = directory.appendingPathComponent("second.json")
            var config = Config.default
            config.modelId = "typing-lag-first"
            try config.write(to: first)
            Config.selfTestURL = first
            check(LiveConfig.currentIfValid?.modelId == config.modelId, "menu cache reads a valid config")
            for _ in 0..<10 { _ = controller.makeMenu() }
            config.modelId = "typing-lag-second"
            try config.write(to: second)
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: first.path)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: second.path)
            _ = LiveConfig.current
            Config.selfTestURL = second
            check(LiveConfig.currentIfValid?.modelId == config.modelId, "cache follows a different file even with the same modification date")
            try Data("{broken json".utf8).write(to: second)
            check(LiveConfig.currentIfValid == nil && LiveConfig.current == .default, "broken config stays an error for the menu, defaults for typing")
            let menu = controller.makeMenu()
            check(menu.items.contains { $0.title == tr("配置文件有误", "The config file has an error") }, "menu reports a broken file")
            let writes = [#selector(AllInOneIMEInputController.setOutputLanguage(_:)),
                          #selector(AllInOneIMEInputController.setDefaultInput(_:)),
                          #selector(AllInOneIMEInputController.toggleStyle(_:))]
            let actions = menu.items.flatMap { $0.submenu?.items ?? [] }.filter { item in item.action.map(writes.contains) ?? false }
            check(!actions.isEmpty && actions.allSatisfy { !$0.isEnabled }, "config-changing menu choices stay disabled for a broken file")
            try config.write(to: second)
            check(LiveConfig.currentIfValid?.modelId == config.modelId, "menu recovers when the file is repaired")
        } catch {
            check(false, "config cache regression: \(error)")
        }
        Config.selfTestURL = savedURL
        UIText.choice = language

        section("typing lag: rapid pinyin commits", needs: .composing)
        let savedSettings = settings
        let load = controller.services.loadSettings
        let savedClient = (document: client.document, inserted: client.inserted)
        defer {
            _ = escape(controller, client)
            client.document = savedClient.document
            client.inserted = savedClient.inserted
            settings = savedSettings
            controller.services.loadSettings = load
            controller.applySettings()
        }
        controller.services.loadSettings = { SelfTest.settings }
        controller.applySettings()
        controller.ensureEngine()
        let before = client.inserted.count
        var commits: [Double] = []
        for _ in 0..<60 {
            let start = Date()
            type("nihao", controller, client)
            _ = space(controller, client)
            commits.append(Date().timeIntervalSince(start) * 1000)
        }
        check(client.inserted.count == before + 60 && client.inserted.suffix(60).allSatisfy { $0 == "你好" },
              "60 rapid words commit exactly once each with no lost or duplicated keys")
        check(!CandidatePanel.shared.isShowing && !controller.composer.isComposing, "the last commit leaves no stale candidates or marked text")
        let words = commits.sorted()
        print(String(format: "  60 real-Rime words (5 keys + Space): median %.2f ms, p95 %.2f ms, max %.2f ms",
                     words[30], words[57], words[59]))
    }
}
